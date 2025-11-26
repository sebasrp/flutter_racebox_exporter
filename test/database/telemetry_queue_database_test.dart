import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/database/telemetry_queue_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';

void main() {
  // Initialize FFI for testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late TelemetryQueueDatabase db;

  setUp(() async {
    // Use unique database name for each test run
    final testDbName =
        'test_telemetry_queue_${DateTime.now().millisecondsSinceEpoch}.db';
    db = TelemetryQueueDatabase(testDatabaseName: testDbName);
    await db.database; // Initialize database
    await db.reset(); // Clear any existing data
  });

  tearDown(() async {
    await db.close();
  });

  group('TelemetryQueueDatabase - Schema Creation', () {
    test('should create database with correct schema', () async {
      final database = await db.database;

      // Verify telemetry_queue table exists
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='telemetry_queue'",
      );
      expect(tables.length, 1);

      // Verify upload_batches table exists
      final batchTables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='upload_batches'",
      );
      expect(batchTables.length, 1);

      // Verify upload_stats table exists
      final statsTables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='upload_stats'",
      );
      expect(statsTables.length, 1);
    });

    test('should create indices on telemetry_queue', () async {
      final database = await db.database;

      final indices = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='telemetry_queue'",
      );

      // Should have 3 indices (idx_uploaded, idx_timestamp, idx_batch_id)
      expect(indices.length, greaterThanOrEqualTo(3));
    });
  });

  group('TelemetryQueueDatabase - Insert Operations', () {
    test('should insert batch of records successfully', () async {
      final records = [
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'lat': 1.0, 'lon': 2.0}),
        },
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'lat': 3.0, 'lon': 4.0}),
        },
      ];

      final insertedCount = await db.insertBatch(records);
      expect(insertedCount, 2);

      final stats = await db.getQueueStats();
      expect(stats['unsent_count'], 2);
    });

    test('should set default values for new records', () async {
      final records = [
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ];

      await db.insertBatch(records);

      final unsent = await db.fetchUnsentRecords(limit: 1);
      expect(unsent.length, 1);
      expect(unsent[0]['retry_count'], 0);
      expect(unsent[0]['uploaded_at'], null);
      expect(unsent[0]['batch_id'], null);
    });
  });

  group('TelemetryQueueDatabase - Fetch Operations', () {
    test('should fetch unsent records in correct order', () async {
      // Insert records with different timestamps
      await Future.delayed(Duration(milliseconds: 10));
      final record1 = {
        'timestamp': DateTime.now().toIso8601String(),
        'data_json': jsonEncode({'order': 1}),
      };

      await db.insertBatch([record1]);
      await Future.delayed(Duration(milliseconds: 10));

      final record2 = {
        'timestamp': DateTime.now().toIso8601String(),
        'data_json': jsonEncode({'order': 2}),
      };

      await db.insertBatch([record2]);

      final unsent = await db.fetchUnsentRecords(limit: 10);
      expect(unsent.length, 2);

      // Should be ordered by created_at ASC (oldest first)
      final data1 = jsonDecode(unsent[0]['data_json']);
      expect(data1['order'], 1);
    });

    test('should respect limit parameter', () async {
      final records = List.generate(
        10,
        (i) => {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'index': i}),
        },
      );

      await db.insertBatch(records);

      final unsent = await db.fetchUnsentRecords(limit: 5);
      expect(unsent.length, 5);
    });

    test('should not fetch already uploaded records', () async {
      final records = [
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ];

      await db.insertBatch(records);
      final unsent = await db.fetchUnsentRecords();

      // Mark as uploaded
      await db.markAsUploaded([unsent[0]['id'] as int], 'batch-123');

      // Should not fetch uploaded records
      final stillUnsent = await db.fetchUnsentRecords();
      expect(stillUnsent.length, 0);
    });
  });

  group('TelemetryQueueDatabase - Upload Operations', () {
    test('should mark records as uploaded', () async {
      final records = [
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ];

      await db.insertBatch(records);
      final unsent = await db.fetchUnsentRecords();
      final recordId = unsent[0]['id'] as int;

      final updatedCount = await db.markAsUploaded([recordId], 'batch-123');
      expect(updatedCount, 1);

      // Verify record is marked as uploaded
      final stillUnsent = await db.fetchUnsentRecords();
      expect(stillUnsent.length, 0);
    });

    test('should increment retry count', () async {
      final records = [
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ];

      await db.insertBatch(records);
      final unsent = await db.fetchUnsentRecords();
      final recordId = unsent[0]['id'] as int;

      await db.incrementRetryCount([recordId]);
      await db.incrementRetryCount([recordId]);

      final database = await db.database;
      final result = await database.query(
        'telemetry_queue',
        where: 'id = ?',
        whereArgs: [recordId],
      );

      expect(result[0]['retry_count'], 2);
    });
  });

  group('TelemetryQueueDatabase - Idempotency', () {
    test('should track processed batches', () async {
      final batchId = 'batch-123';

      final isProcessed = await db.isBatchProcessed(batchId);
      expect(isProcessed, false);

      await db.markBatchProcessed(batchId, 10, serverResponse: 'OK');

      final isNowProcessed = await db.isBatchProcessed(batchId);
      expect(isNowProcessed, true);
    });

    test('should prevent duplicate batch processing', () async {
      final batchId = 'batch-456';

      await db.markBatchProcessed(batchId, 5);

      // Try to mark again (should replace)
      await db.markBatchProcessed(batchId, 10);

      final database = await db.database;
      final result = await database.query(
        'upload_batches',
        where: 'batch_id = ?',
        whereArgs: [batchId],
      );

      expect(result.length, 1);
      expect(result[0]['record_count'], 10);
    });
  });

  group('TelemetryQueueDatabase - Statistics', () {
    test('should record upload statistics', () async {
      await db.recordUploadStats(
        recordsUploaded: 100,
        batchSize: 500,
        networkQuality: 'excellent',
        success: true,
      );

      final stats = await db.getUploadStats(hours: 1);
      expect(stats.length, 1);
      expect(stats[0]['records_uploaded'], 100);
      expect(stats[0]['network_quality'], 'excellent');
      expect(stats[0]['success'], 1);
    });

    test('should calculate queue statistics correctly', () async {
      // Insert some records
      final records = List.generate(
        5,
        (i) => {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'index': i}),
        },
      );

      await db.insertBatch(records);

      // Mark some as uploaded
      final unsent = await db.fetchUnsentRecords();
      await db.markAsUploaded([
        unsent[0]['id'] as int,
        unsent[1]['id'] as int,
      ], 'batch-123');

      final stats = await db.getQueueStats();
      expect(stats['unsent_count'], 3);
      expect(stats['uploaded_count'], 2);
      expect(stats['oldest_unsent'], isNotNull);
    });

    test('should calculate success rate from recent uploads', () async {
      // Record some successful uploads
      for (int i = 0; i < 7; i++) {
        await db.recordUploadStats(
          recordsUploaded: 10,
          batchSize: 10,
          networkQuality: 'good',
          success: true,
        );
      }

      // Record some failures
      for (int i = 0; i < 3; i++) {
        await db.recordUploadStats(
          recordsUploaded: 0,
          batchSize: 10,
          networkQuality: 'poor',
          success: false,
          errorMessage: 'Network error',
        );
      }

      final stats = await db.getQueueStats();
      expect(stats['success_rate'], 70.0); // 7 out of 10 successful
    });
  });

  group('TelemetryQueueDatabase - Cleanup Operations', () {
    test('should delete old uploaded records', () async {
      final records = [
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ];

      await db.insertBatch(records);
      final unsent = await db.fetchUnsentRecords();
      await db.markAsUploaded([unsent[0]['id'] as int], 'batch-123');

      // Manually update uploaded_at to be old
      final database = await db.database;
      final oldTimestamp = DateTime.now()
          .subtract(Duration(days: 10))
          .millisecondsSinceEpoch;

      await database.update(
        'telemetry_queue',
        {'uploaded_at': oldTimestamp},
        where: 'id = ?',
        whereArgs: [unsent[0]['id']],
      );

      final deletedCount = await db.deleteUploadedOlderThan(7);
      expect(deletedCount, 1);
    });

    test('should cleanup old batch records', () async {
      final oldTimestamp = DateTime.now()
          .subtract(Duration(days: 10))
          .millisecondsSinceEpoch;

      final database = await db.database;
      await database.insert('upload_batches', {
        'batch_id': 'old-batch',
        'record_count': 10,
        'uploaded_at': oldTimestamp,
      });

      final deletedCount = await db.cleanupOldBatches(7);
      expect(deletedCount, 1);
    });

    test('should cleanup old statistics', () async {
      final oldTimestamp = DateTime.now()
          .subtract(Duration(days: 10))
          .millisecondsSinceEpoch;

      final database = await db.database;
      await database.insert('upload_stats', {
        'timestamp': oldTimestamp,
        'records_uploaded': 10,
        'batch_size': 10,
        'network_quality': 'good',
        'success': 1,
      });

      final deletedCount = await db.cleanupOldStats(7);
      expect(deletedCount, 1);
    });
  });

  group('TelemetryQueueDatabase - Edge Cases', () {
    test('should handle empty batch insert', () async {
      final insertedCount = await db.insertBatch([]);
      expect(insertedCount, 0);
    });

    test('should handle empty record list for markAsUploaded', () async {
      final updatedCount = await db.markAsUploaded([], 'batch-123');
      expect(updatedCount, 0);
    });

    test('should handle empty record list for incrementRetryCount', () async {
      final updatedCount = await db.incrementRetryCount([]);
      expect(updatedCount, 0);
    });

    test('should handle reset operation', () async {
      // Insert some data
      final records = [
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ];
      await db.insertBatch(records);
      await db.markBatchProcessed('batch-123', 1);
      await db.recordUploadStats(
        recordsUploaded: 1,
        batchSize: 1,
        networkQuality: 'good',
        success: true,
      );

      // Reset database
      await db.reset();

      // Verify all tables are empty
      final stats = await db.getQueueStats();
      expect(stats['unsent_count'], 0);
      expect(stats['uploaded_count'], 0);

      final batches = await db.isBatchProcessed('batch-123');
      expect(batches, false);
    });
  });
}
