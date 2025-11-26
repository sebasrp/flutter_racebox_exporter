import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:logger/logger.dart';

/// Database for managing telemetry upload queue with persistence
///
/// This database implements the queue schema from the Flutter integration
/// architecture, providing:
/// - Persistent queue for unsent telemetry data
/// - Idempotency tracking for uploaded batches
/// - Upload statistics for monitoring
class TelemetryQueueDatabase {
  static TelemetryQueueDatabase? _instance;
  static Database? _database;
  static bool _ffiInitialized = false;
  final Logger _logger = Logger();
  static String? _testDatabaseName;

  factory TelemetryQueueDatabase({String? testDatabaseName}) {
    if (testDatabaseName != null) {
      _testDatabaseName = testDatabaseName;
      _instance = null;
      _database = null;
    }
    _instance ??= TelemetryQueueDatabase._internal();
    return _instance!;
  }

  TelemetryQueueDatabase._internal();

  /// Reset the singleton instance (for testing only)
  static void resetInstance() {
    _instance = null;
    _database = null;
    _testDatabaseName = null;
  }

  /// Initialize FFI for desktop platforms
  static void _initializeFfi() {
    if (_ffiInitialized) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiInitialized = true;
  }

  /// Get the database instance, initializing if necessary
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database with the queue schema
  Future<Database> _initDatabase() async {
    try {
      _initializeFfi();

      final databasesPath = await getDatabasesPath();
      final dbName = _testDatabaseName ?? 'telemetry_queue.db';
      final path = join(databasesPath, dbName);

      _logger.i('Initializing telemetry queue database at: $path');

      return await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      throw Exception(
        'Failed to initialize telemetry queue database: $e. '
        'Note: SQLite is not supported on web platform.',
      );
    }
  }

  /// Create database schema on first initialization
  Future<void> _onCreate(Database db, int version) async {
    _logger.i('Creating telemetry queue database schema (version $version)');

    // Main telemetry queue table
    await db.execute('''
      CREATE TABLE telemetry_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        data_json TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        uploaded_at INTEGER,
        batch_id TEXT
      )
    ''');

    // Create indices for efficient queries
    await db.execute('''
      CREATE INDEX idx_uploaded ON telemetry_queue(uploaded_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_timestamp ON telemetry_queue(timestamp)
    ''');

    await db.execute('''
      CREATE INDEX idx_batch_id ON telemetry_queue(batch_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_retry_count ON telemetry_queue(retry_count)
    ''');

    // Track uploaded batches for idempotency
    await db.execute('''
      CREATE TABLE upload_batches (
        batch_id TEXT PRIMARY KEY,
        record_count INTEGER NOT NULL,
        uploaded_at INTEGER NOT NULL,
        server_response TEXT
      )
    ''');

    // Track upload statistics for monitoring
    await db.execute('''
      CREATE TABLE upload_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        records_uploaded INTEGER NOT NULL,
        batch_size INTEGER NOT NULL,
        network_quality TEXT NOT NULL,
        success INTEGER NOT NULL,
        error_message TEXT
      )
    ''');

    // Create index for stats queries
    await db.execute('''
      CREATE INDEX idx_stats_timestamp ON upload_stats(timestamp)
    ''');

    // Dead letter queue for permanently failed records
    await db.execute('''
      CREATE TABLE dead_letter_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_id INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        data_json TEXT NOT NULL,
        retry_count INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        failed_at INTEGER NOT NULL,
        last_error TEXT,
        UNIQUE(original_id)
      )
    ''');

    // Create index for DLQ queries
    await db.execute('''
      CREATE INDEX idx_dlq_failed_at ON dead_letter_queue(failed_at)
    ''');

    _logger.i('Telemetry queue database schema created successfully');
  }

  /// Handle database upgrades for future schema changes
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _logger.i(
      'Upgrading telemetry queue database from version $oldVersion to $newVersion',
    );

    // Future migrations will be handled here
    // Example:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE telemetry_queue ADD COLUMN new_field TEXT');
    // }
  }

  /// Insert a batch of telemetry records into the queue
  ///
  /// Returns the number of records inserted
  Future<int> insertBatch(List<Map<String, dynamic>> records) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final record in records) {
      batch.insert('telemetry_queue', {
        'timestamp': record['timestamp'],
        'data_json': record['data_json'],
        'retry_count': 0,
        'created_at': now,
        'uploaded_at': null,
        'batch_id': null,
      });
    }

    final results = await batch.commit(noResult: false);
    final insertedCount =
        results.where((r) => r != null && (r as int) > 0).length;

    _logger.d('Inserted $insertedCount records into telemetry queue');
    return insertedCount;
  }

  /// Fetch oldest N unsent records from the queue
  ///
  /// [limit] - Maximum number of records to fetch
  /// Returns list of queue records with their IDs
  Future<List<Map<String, dynamic>>> fetchUnsentRecords({
    int limit = 500,
  }) async {
    final db = await database;

    final records = await db.query(
      'telemetry_queue',
      where: 'uploaded_at IS NULL',
      orderBy: 'created_at ASC',
      limit: limit,
    );

    _logger.d('Fetched ${records.length} unsent records from queue');
    return records;
  }

  /// Mark records as uploaded
  ///
  /// [recordIds] - List of record IDs to mark as uploaded
  /// [batchId] - Batch ID for tracking
  /// Returns the number of records updated
  Future<int> markAsUploaded(List<int> recordIds, String batchId) async {
    if (recordIds.isEmpty) return 0;

    final db = await database;
    final uploadedAt = DateTime.now().millisecondsSinceEpoch;

    _logger.d(
      '📝 Attempting to mark ${recordIds.length} records as uploaded: $recordIds',
    );

    // Verify records exist before updating
    final existingRecords = await db.query(
      'telemetry_queue',
      columns: ['id', 'uploaded_at'],
      where: 'id IN (${recordIds.map((_) => '?').join(',')})',
      whereArgs: recordIds,
    );

    _logger.d(
      '📊 Found ${existingRecords.length}/${recordIds.length} records in database',
    );

    if (existingRecords.length != recordIds.length) {
      final existingIds = existingRecords.map((r) => r['id'] as int).toSet();
      final missingIds =
          recordIds.where((id) => !existingIds.contains(id)).toList();
      _logger.w('⚠️ Missing record IDs: $missingIds');
    }

    // Check if any are already uploaded
    final alreadyUploaded =
        existingRecords.where((r) => r['uploaded_at'] != null).length;
    if (alreadyUploaded > 0) {
      _logger.w('⚠️ $alreadyUploaded records already marked as uploaded');
    }

    final batch = db.batch();
    for (final id in recordIds) {
      batch.update(
        'telemetry_queue',
        {'uploaded_at': uploadedAt, 'batch_id': batchId},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    final results = await batch.commit(noResult: false);
    final updatedCount =
        results.where((r) => r != null && (r as int) > 0).length;

    _logger.d(
      '✅ Marked $updatedCount/${recordIds.length} records as uploaded (batch: $batchId)',
    );

    // Verify the update worked
    if (updatedCount != recordIds.length) {
      _logger.w(
        '⚠️ Update mismatch: expected ${recordIds.length}, got $updatedCount',
      );
    }

    return updatedCount;
  }

  /// Increment retry count for failed upload records
  ///
  /// [recordIds] - List of record IDs to increment retry count
  /// Returns the number of records updated
  Future<int> incrementRetryCount(List<int> recordIds) async {
    if (recordIds.isEmpty) return 0;

    final db = await database;
    final batch = db.batch();

    for (final id in recordIds) {
      batch.rawUpdate(
        'UPDATE telemetry_queue SET retry_count = retry_count + 1 WHERE id = ?',
        [id],
      );
    }

    final results = await batch.commit(noResult: false);
    final updatedCount =
        results.where((r) => r != null && (r as int) > 0).length;

    _logger.d('Incremented retry count for $updatedCount records');
    return updatedCount;
  }

  /// Delete uploaded records older than specified days
  ///
  /// [days] - Number of days to keep uploaded records
  /// Returns the number of records deleted
  Future<int> deleteUploadedOlderThan(int days) async {
    final db = await database;
    final cutoffTime =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

    final deletedCount = await db.delete(
      'telemetry_queue',
      where: 'uploaded_at IS NOT NULL AND uploaded_at < ?',
      whereArgs: [cutoffTime],
    );

    _logger.i('Deleted $deletedCount uploaded records older than $days days');
    return deletedCount;
  }

  /// Check if a batch has already been processed (idempotency check)
  ///
  /// [batchId] - Batch ID to check
  /// Returns true if batch was already processed
  Future<bool> isBatchProcessed(String batchId) async {
    final db = await database;

    final result = await db.query(
      'upload_batches',
      where: 'batch_id = ?',
      whereArgs: [batchId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  /// Mark a batch as processed for idempotency tracking
  ///
  /// [batchId] - Batch ID to mark as processed
  /// [recordCount] - Number of records in the batch
  /// [serverResponse] - Optional server response for debugging
  Future<void> markBatchProcessed(
    String batchId,
    int recordCount, {
    String? serverResponse,
  }) async {
    final db = await database;

    await db.insert(
        'upload_batches',
        {
          'batch_id': batchId,
          'record_count': recordCount,
          'uploaded_at': DateTime.now().millisecondsSinceEpoch,
          'server_response': serverResponse,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    _logger.d('Marked batch $batchId as processed ($recordCount records)');
  }

  /// Record upload statistics for monitoring
  ///
  /// [recordsUploaded] - Number of records uploaded
  /// [batchSize] - Size of the batch
  /// [networkQuality] - Network quality during upload
  /// [success] - Whether the upload was successful
  /// [errorMessage] - Optional error message if upload failed
  Future<void> recordUploadStats({
    required int recordsUploaded,
    required int batchSize,
    required String networkQuality,
    required bool success,
    String? errorMessage,
  }) async {
    final db = await database;

    await db.insert('upload_stats', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'records_uploaded': recordsUploaded,
      'batch_size': batchSize,
      'network_quality': networkQuality,
      'success': success ? 1 : 0,
      'error_message': errorMessage,
    });

    _logger.d(
      'Recorded upload stats: $recordsUploaded records, quality: $networkQuality, success: $success',
    );
  }

  /// Get queue statistics
  ///
  /// Returns a map with queue metrics
  Future<Map<String, dynamic>> getQueueStats() async {
    final db = await database;

    // Count unsent records
    final unsentResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM telemetry_queue WHERE uploaded_at IS NULL',
    );
    final unsentCount = unsentResult.first['count'] as int;

    // Count uploaded records
    final uploadedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM telemetry_queue WHERE uploaded_at IS NOT NULL',
    );
    final uploadedCount = uploadedResult.first['count'] as int;

    // Get oldest unsent record timestamp
    final oldestResult = await db.rawQuery(
      'SELECT MIN(created_at) as oldest FROM telemetry_queue WHERE uploaded_at IS NULL',
    );
    final oldestTimestamp = oldestResult.first['oldest'] as int?;

    // Get recent upload success rate (last 100 uploads)
    final recentStatsResult = await db.rawQuery(
      'SELECT COUNT(*) as total, SUM(success) as successful FROM '
      '(SELECT success FROM upload_stats ORDER BY timestamp DESC LIMIT 100)',
    );
    final totalRecent = recentStatsResult.first['total'] as int;
    final successfulRecent = recentStatsResult.first['successful'] as int? ?? 0;
    final successRate =
        totalRecent > 0 ? (successfulRecent / totalRecent * 100) : 0.0;

    return {
      'unsent_count': unsentCount,
      'uploaded_count': uploadedCount,
      'oldest_unsent': oldestTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(oldestTimestamp)
          : null,
      'success_rate': successRate,
    };
  }

  /// Get upload statistics for a time period
  ///
  /// [hours] - Number of hours to look back
  /// Returns list of upload stats
  Future<List<Map<String, dynamic>>> getUploadStats({int hours = 24}) async {
    final db = await database;
    final cutoffTime =
        DateTime.now().subtract(Duration(hours: hours)).millisecondsSinceEpoch;

    return await db.query(
      'upload_stats',
      where: 'timestamp >= ?',
      whereArgs: [cutoffTime],
      orderBy: 'timestamp DESC',
    );
  }

  /// Clean up old batch records
  ///
  /// [days] - Number of days to keep batch records
  /// Returns the number of records deleted
  Future<int> cleanupOldBatches(int days) async {
    final db = await database;
    final cutoffTime =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

    final deletedCount = await db.delete(
      'upload_batches',
      where: 'uploaded_at < ?',
      whereArgs: [cutoffTime],
    );

    _logger.i('Cleaned up $deletedCount old batch records');
    return deletedCount;
  }

  /// Clean up old upload statistics
  ///
  /// [days] - Number of days to keep statistics
  /// Returns the number of records deleted
  Future<int> cleanupOldStats(int days) async {
    final db = await database;
    final cutoffTime =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

    final deletedCount = await db.delete(
      'upload_stats',
      where: 'timestamp < ?',
      whereArgs: [cutoffTime],
    );

    _logger.i('Cleaned up $deletedCount old statistics records');
    return deletedCount;
  }

  /// Close the database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _instance = null;
      _logger.i('Telemetry queue database closed');
    }
  }

  /// Move records that exceeded max retries to dead letter queue
  ///
  /// [maxRetries] - Maximum number of retries before moving to DLQ (default: 5)
  /// [lastError] - Optional error message to store with DLQ records
  /// Returns the number of records moved to DLQ
  Future<int> moveFailedToDeadLetterQueue({
    int maxRetries = 5,
    String? lastError,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Find records that exceeded max retries
    final failedRecords = await db.query(
      'telemetry_queue',
      where: 'retry_count >= ? AND uploaded_at IS NULL',
      whereArgs: [maxRetries],
    );

    if (failedRecords.isEmpty) {
      return 0;
    }

    final batch = db.batch();

    // Move each failed record to DLQ
    for (final record in failedRecords) {
      batch.insert(
          'dead_letter_queue',
          {
            'original_id': record['id'],
            'timestamp': record['timestamp'],
            'data_json': record['data_json'],
            'retry_count': record['retry_count'],
            'created_at': record['created_at'],
            'failed_at': now,
            'last_error': lastError,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      // Delete from main queue
      batch.delete(
        'telemetry_queue',
        where: 'id = ?',
        whereArgs: [record['id']],
      );
    }

    await batch.commit(noResult: true);

    _logger.w(
      '⚠️ Moved ${failedRecords.length} permanently failed records to dead letter queue',
    );
    return failedRecords.length;
  }

  /// Get dead letter queue statistics
  ///
  /// Returns a map with DLQ metrics
  Future<Map<String, dynamic>> getDeadLetterQueueStats() async {
    final db = await database;

    // Count DLQ records
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM dead_letter_queue',
    );
    final count = countResult.first['count'] as int;

    // Get oldest DLQ record
    final oldestResult = await db.rawQuery(
      'SELECT MIN(failed_at) as oldest FROM dead_letter_queue',
    );
    final oldestTimestamp = oldestResult.first['oldest'] as int?;

    // Get most recent DLQ record
    final newestResult = await db.rawQuery(
      'SELECT MAX(failed_at) as newest FROM dead_letter_queue',
    );
    final newestTimestamp = newestResult.first['newest'] as int?;

    return {
      'count': count,
      'oldest_failed': oldestTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(oldestTimestamp)
          : null,
      'newest_failed': newestTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(newestTimestamp)
          : null,
    };
  }

  /// Get dead letter queue records
  ///
  /// [limit] - Maximum number of records to fetch
  /// [offset] - Number of records to skip
  /// Returns list of DLQ records
  Future<List<Map<String, dynamic>>> getDeadLetterQueueRecords({
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;

    return await db.query(
      'dead_letter_queue',
      orderBy: 'failed_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Retry a record from the dead letter queue
  ///
  /// Moves a record back to the main queue with reset retry count
  /// [dlqId] - ID of the record in the dead letter queue
  /// Returns true if successful
  Future<bool> retryFromDeadLetterQueue(int dlqId) async {
    final db = await database;

    // Get the DLQ record
    final dlqRecords = await db.query(
      'dead_letter_queue',
      where: 'id = ?',
      whereArgs: [dlqId],
      limit: 1,
    );

    if (dlqRecords.isEmpty) {
      _logger.w('⚠️ DLQ record $dlqId not found');
      return false;
    }

    final dlqRecord = dlqRecords.first;

    // Insert back into main queue with reset retry count
    await db.insert('telemetry_queue', {
      'timestamp': dlqRecord['timestamp'],
      'data_json': dlqRecord['data_json'],
      'retry_count': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'uploaded_at': null,
      'batch_id': null,
    });

    // Delete from DLQ
    await db.delete('dead_letter_queue', where: 'id = ?', whereArgs: [dlqId]);

    _logger.i('✅ Moved DLQ record $dlqId back to main queue');
    return true;
  }

  /// Delete old dead letter queue records
  ///
  /// [days] - Number of days to keep DLQ records
  /// Returns the number of records deleted
  Future<int> cleanupOldDeadLetterQueue(int days) async {
    final db = await database;
    final cutoffTime =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

    final deletedCount = await db.delete(
      'dead_letter_queue',
      where: 'failed_at < ?',
      whereArgs: [cutoffTime],
    );

    _logger.i('Cleaned up $deletedCount old DLQ records');
    return deletedCount;
  }

  /// Purge all dead letter queue records
  ///
  /// WARNING: This permanently deletes all DLQ records
  /// Returns the number of records deleted
  Future<int> purgeDeadLetterQueue() async {
    final db = await database;

    final deletedCount = await db.delete('dead_letter_queue');

    _logger.w('⚠️ Purged $deletedCount records from dead letter queue');
    return deletedCount;
  }

  /// Reset the database (for testing purposes)
  Future<void> reset() async {
    final db = await database;
    await db.delete('telemetry_queue');
    await db.delete('upload_batches');
    await db.delete('upload_stats');
    await db.delete('dead_letter_queue');
    _logger.w('Telemetry queue database reset - all data deleted');
  }
}
