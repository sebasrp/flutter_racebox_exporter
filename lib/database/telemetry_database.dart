import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../racebox_ble/models/racebox_data.dart';
import '../racebox_ble/models/gps_data.dart';
import '../racebox_ble/models/motion_data.dart';

/// Local database for storing telemetry data
class TelemetryDatabase {
  static final TelemetryDatabase _instance = TelemetryDatabase._internal();
  static Database? _database;
  static bool _ffiInitialized = false;

  factory TelemetryDatabase() => _instance;

  TelemetryDatabase._internal();

  /// Initialize FFI for desktop platforms
  static void _initializeFfi() {
    if (_ffiInitialized) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // Initialize FFI
      sqfliteFfiInit();
      // Set the database factory to use FFI
      databaseFactory = databaseFactoryFfi;
    }
    _ffiInitialized = true;
  }

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    try {
      // Initialize FFI for desktop platforms
      _initializeFfi();

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'telemetry.db');

      return await openDatabase(path, version: 1, onCreate: _onCreate);
    } catch (e) {
      // On platforms that don't support sqflite (e.g., web), throw a more informative error
      throw Exception(
        'Failed to initialize database: $e. '
        'Note: SQLite is not supported on web platform.',
      );
    }
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id TEXT UNIQUE NOT NULL,
        device_id TEXT,
        session_id TEXT,
        recorded_at INTEGER NOT NULL,
        itow INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        wgs_altitude REAL NOT NULL,
        msl_altitude REAL NOT NULL,
        speed REAL NOT NULL,
        heading REAL NOT NULL,
        num_satellites INTEGER NOT NULL,
        fix_status INTEGER NOT NULL,
        horizontal_accuracy REAL NOT NULL,
        vertical_accuracy REAL NOT NULL,
        speed_accuracy REAL NOT NULL,
        heading_accuracy REAL NOT NULL,
        pdop REAL NOT NULL,
        is_fix_valid INTEGER NOT NULL,
        g_force_x REAL NOT NULL,
        g_force_y REAL NOT NULL,
        g_force_z REAL NOT NULL,
        rotation_x REAL NOT NULL,
        rotation_y REAL NOT NULL,
        rotation_z REAL NOT NULL,
        battery REAL NOT NULL,
        is_charging INTEGER NOT NULL,
        time_accuracy INTEGER NOT NULL,
        validity_flags INTEGER NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        server_id INTEGER
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX idx_sync_status ON telemetry(sync_status)');
    await db.execute('CREATE INDEX idx_created_at ON telemetry(created_at)');
    await db.execute('CREATE INDEX idx_local_id ON telemetry(local_id)');
    await db.execute('CREATE INDEX idx_session_id ON telemetry(session_id)');
  }

  /// Insert telemetry data
  Future<int> insertTelemetry(
    RaceboxData data, {
    String? deviceId,
    String? sessionId,
    String? localId,
  }) async {
    final db = await database;

    final values = {
      'local_id': localId ?? _generateLocalId(),
      'device_id': deviceId,
      'session_id': sessionId,
      'recorded_at': data.timestamp.millisecondsSinceEpoch,
      'itow': data.iTOW,
      'latitude': data.gps.latitude,
      'longitude': data.gps.longitude,
      'wgs_altitude': data.gps.wgsAltitude,
      'msl_altitude': data.gps.mslAltitude,
      'speed': data.gps.speed,
      'heading': data.gps.heading,
      'num_satellites': data.gps.numSatellites,
      'fix_status': data.gps.fixStatus,
      'horizontal_accuracy': data.gps.horizontalAccuracy,
      'vertical_accuracy': data.gps.verticalAccuracy,
      'speed_accuracy': data.gps.speedAccuracy,
      'heading_accuracy': data.gps.headingAccuracy,
      'pdop': data.gps.pdop,
      'is_fix_valid': data.gps.isFixValid ? 1 : 0,
      'g_force_x': data.motion.gForceX,
      'g_force_y': data.motion.gForceY,
      'g_force_z': data.motion.gForceZ,
      'rotation_x': data.motion.rotationX,
      'rotation_y': data.motion.rotationY,
      'rotation_z': data.motion.rotationZ,
      'battery': data.battery,
      'is_charging': data.isCharging ? 1 : 0,
      'time_accuracy': data.timeAccuracy,
      'validity_flags': data.validityFlags,
      'sync_status': 'pending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };

    return await db.insert('telemetry', values);
  }

  /// Get pending telemetry records for sync
  Future<List<Map<String, dynamic>>> getPendingTelemetry({
    int limit = 100,
  }) async {
    final db = await database;
    return await db.query(
      'telemetry',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  /// Get count of pending records
  Future<int> getPendingCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM telemetry WHERE sync_status = ?',
      ['pending'],
    );
    return result.first['count'] as int;
  }

  /// Mark records as synced by local IDs
  Future<int> markAsSynced(List<String> localIds, List<int> serverIds) async {
    if (localIds.isEmpty || localIds.length != serverIds.length) {
      return 0;
    }

    final db = await database;
    final batch = db.batch();
    final syncedAt = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < localIds.length; i++) {
      batch.update(
        'telemetry',
        {
          'sync_status': 'synced',
          'synced_at': syncedAt,
          'server_id': serverIds[i],
        },
        where: 'local_id = ?',
        whereArgs: [localIds[i]],
      );
    }

    final results = await batch.commit();
    return results.where((r) => r != null && (r as int) > 0).length;
  }

  /// Delete synced records older than specified days
  Future<int> deleteSyncedOlderThan(int days) async {
    final db = await database;
    final cutoffTime =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

    return await db.delete(
      'telemetry',
      where: 'sync_status = ? AND synced_at < ?',
      whereArgs: ['synced', cutoffTime],
    );
  }

  /// Get sync statistics
  Future<Map<String, dynamic>> getSyncStats() async {
    final db = await database;

    final pendingResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM telemetry WHERE sync_status = ?',
      ['pending'],
    );

    final syncedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM telemetry WHERE sync_status = ?',
      ['synced'],
    );

    final lastSyncResult = await db.rawQuery(
      'SELECT MAX(synced_at) as last_sync FROM telemetry WHERE sync_status = ?',
      ['synced'],
    );

    final lastSync = lastSyncResult.first['last_sync'] as int?;

    return {
      'pending_count': pendingResult.first['count'] as int,
      'synced_count': syncedResult.first['count'] as int,
      'last_sync': lastSync != null
          ? DateTime.fromMillisecondsSinceEpoch(lastSync)
          : null,
    };
  }

  /// Convert database row to RaceboxData
  RaceboxData rowToRaceboxData(Map<String, dynamic> row) {
    final gps = GpsData(
      latitude: row['latitude'] as double,
      longitude: row['longitude'] as double,
      wgsAltitude: row['wgs_altitude'] as double,
      mslAltitude: row['msl_altitude'] as double,
      speed: row['speed'] as double,
      heading: row['heading'] as double,
      numSatellites: row['num_satellites'] as int,
      fixStatus: row['fix_status'] as int,
      horizontalAccuracy: row['horizontal_accuracy'] as double,
      verticalAccuracy: row['vertical_accuracy'] as double,
      speedAccuracy: row['speed_accuracy'] as double,
      headingAccuracy: row['heading_accuracy'] as double,
      pdop: row['pdop'] as double,
      isFixValid: (row['is_fix_valid'] as int) == 1,
    );

    final motion = MotionData(
      gForceX: row['g_force_x'] as double,
      gForceY: row['g_force_y'] as double,
      gForceZ: row['g_force_z'] as double,
      rotationX: row['rotation_x'] as double,
      rotationY: row['rotation_y'] as double,
      rotationZ: row['rotation_z'] as double,
    );

    return RaceboxData(
      iTOW: row['itow'] as int,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['recorded_at'] as int),
      gps: gps,
      motion: motion,
      battery: row['battery'] as double,
      isCharging: (row['is_charging'] as int) == 1,
      timeAccuracy: row['time_accuracy'] as int,
      validityFlags: row['validity_flags'] as int,
    );
  }

  /// Generate unique local ID
  String _generateLocalId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
