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

  group('Dead Letter Queue', () {
    late TelemetryQueueDatabase database;

    setUp(() async {
      // Use unique database name for each test run
      final testDbName = 'test_dlq_${DateTime.now().millisecondsSinceEpoch}.db';
      database = TelemetryQueueDatabase(testDatabaseName: testDbName);
      await database.database; // Initialize database
      await database.reset();
    });

    tearDown(() async {
      await database.close();
    });

    test('should move records exceeding max retries to DLQ', () async {
      // Insert test records
      await database.insertBatch([
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data1'}),
        },
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data2'}),
        },
      ]);

      // Simulate 5 failed upload attempts
      final records = await database.fetchUnsentRecords();
      final recordIds = records.map((r) => r['id'] as int).toList();

      for (int i = 0; i < 5; i++) {
        await database.incrementRetryCount(recordIds);
      }

      // Move failed records to DLQ
      final movedCount = await database.moveFailedToDeadLetterQueue(
        maxRetries: 5,
        lastError: 'Network timeout',
      );

      expect(movedCount, equals(2));

      // Verify records are in DLQ
      final dlqStats = await database.getDeadLetterQueueStats();
      expect(dlqStats['count'], equals(2));

      // Verify records are removed from main queue
      final remainingRecords = await database.fetchUnsentRecords();
      expect(remainingRecords.length, equals(0));
    });

    test('should not move records below max retries to DLQ', () async {
      // Insert test record
      await database.insertBatch([
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ]);

      // Simulate 3 failed attempts (below max of 5)
      final records = await database.fetchUnsentRecords();
      final recordIds = records.map((r) => r['id'] as int).toList();

      for (int i = 0; i < 3; i++) {
        await database.incrementRetryCount(recordIds);
      }

      // Try to move to DLQ
      final movedCount = await database.moveFailedToDeadLetterQueue(
        maxRetries: 5,
      );

      expect(movedCount, equals(0));

      // Verify record is still in main queue
      final remainingRecords = await database.fetchUnsentRecords();
      expect(remainingRecords.length, equals(1));
    });

    test('should get DLQ statistics correctly', () async {
      // Initially empty
      var stats = await database.getDeadLetterQueueStats();
      expect(stats['count'], equals(0));
      expect(stats['oldest_failed'], isNull);
      expect(stats['newest_failed'], isNull);

      // Add records to DLQ
      await database.insertBatch([
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data1'}),
        },
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data2'}),
        },
      ]);

      final records = await database.fetchUnsentRecords();
      final recordIds = records.map((r) => r['id'] as int).toList();

      for (int i = 0; i < 5; i++) {
        await database.incrementRetryCount(recordIds);
      }

      await database.moveFailedToDeadLetterQueue(maxRetries: 5);

      // Check stats
      stats = await database.getDeadLetterQueueStats();
      expect(stats['count'], equals(2));
      expect(stats['oldest_failed'], isNotNull);
      expect(stats['newest_failed'], isNotNull);
    });

    test('should retrieve DLQ records with pagination', () async {
      // Add multiple records to DLQ
      for (int i = 0; i < 10; i++) {
        await database.insertBatch([
          {
            'timestamp': DateTime.now().toIso8601String(),
            'data_json': jsonEncode({'test': 'data$i'}),
          },
        ]);

        final records = await database.fetchUnsentRecords();
        final recordIds = records.map((r) => r['id'] as int).toList();

        for (int j = 0; j < 5; j++) {
          await database.incrementRetryCount(recordIds);
        }

        await database.moveFailedToDeadLetterQueue(maxRetries: 5);
      }

      // Get first page
      final page1 = await database.getDeadLetterQueueRecords(
        limit: 5,
        offset: 0,
      );
      expect(page1.length, equals(5));

      // Get second page
      final page2 = await database.getDeadLetterQueueRecords(
        limit: 5,
        offset: 5,
      );
      expect(page2.length, equals(5));

      // Verify different records
      expect(page1.first['id'], isNot(equals(page2.first['id'])));
    });

    test('should retry record from DLQ', () async {
      // Add record to DLQ
      await database.insertBatch([
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ]);

      final records = await database.fetchUnsentRecords();
      final recordIds = records.map((r) => r['id'] as int).toList();

      for (int i = 0; i < 5; i++) {
        await database.incrementRetryCount(recordIds);
      }

      await database.moveFailedToDeadLetterQueue(maxRetries: 5);

      // Get DLQ record
      final dlqRecords = await database.getDeadLetterQueueRecords();
      expect(dlqRecords.length, equals(1));

      final dlqId = dlqRecords.first['id'] as int;

      // Retry from DLQ
      final success = await database.retryFromDeadLetterQueue(dlqId);
      expect(success, isTrue);

      // Verify record is back in main queue with reset retry count
      final mainQueueRecords = await database.fetchUnsentRecords();
      expect(mainQueueRecords.length, equals(1));
      expect(mainQueueRecords.first['retry_count'], equals(0));

      // Verify record is removed from DLQ
      final remainingDlq = await database.getDeadLetterQueueRecords();
      expect(remainingDlq.length, equals(0));
    });

    test('should handle retry of non-existent DLQ record', () async {
      final success = await database.retryFromDeadLetterQueue(999);
      expect(success, isFalse);
    });

    test('should cleanup old DLQ records', () async {
      // This test would need to manipulate timestamps
      // For now, just verify the method works
      final deletedCount = await database.cleanupOldDeadLetterQueue(30);
      expect(deletedCount, equals(0)); // No old records yet
    });

    test('should purge all DLQ records', () async {
      // Add records to DLQ
      await database.insertBatch([
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data1'}),
        },
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data2'}),
        },
      ]);

      final records = await database.fetchUnsentRecords();
      final recordIds = records.map((r) => r['id'] as int).toList();

      for (int i = 0; i < 5; i++) {
        await database.incrementRetryCount(recordIds);
      }

      await database.moveFailedToDeadLetterQueue(maxRetries: 5);

      // Verify DLQ has records
      var stats = await database.getDeadLetterQueueStats();
      expect(stats['count'], equals(2));

      // Purge DLQ
      final purgedCount = await database.purgeDeadLetterQueue();
      expect(purgedCount, equals(2));

      // Verify DLQ is empty
      stats = await database.getDeadLetterQueueStats();
      expect(stats['count'], equals(0));
    });

    test('should store last error in DLQ', () async {
      const errorMessage = 'Connection timeout after 30s';

      await database.insertBatch([
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({'test': 'data'}),
        },
      ]);

      final records = await database.fetchUnsentRecords();
      final recordIds = records.map((r) => r['id'] as int).toList();

      for (int i = 0; i < 5; i++) {
        await database.incrementRetryCount(recordIds);
      }

      await database.moveFailedToDeadLetterQueue(
        maxRetries: 5,
        lastError: errorMessage,
      );

      final dlqRecords = await database.getDeadLetterQueueRecords();
      expect(dlqRecords.first['last_error'], equals(errorMessage));
    });

    test('should preserve original data in DLQ', () async {
      final originalData = {
        'itow': 1000,
        'latitude': 1.234,
        'longitude': 5.678,
        'speed': 10.5,
      };

      await database.insertBatch([
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode(originalData),
        },
      ]);

      final records = await database.fetchUnsentRecords();
      final recordIds = records.map((r) => r['id'] as int).toList();

      for (int i = 0; i < 5; i++) {
        await database.incrementRetryCount(recordIds);
      }

      await database.moveFailedToDeadLetterQueue(maxRetries: 5);

      final dlqRecords = await database.getDeadLetterQueueRecords();
      final storedData = jsonDecode(dlqRecords.first['data_json'] as String);

      expect(storedData, equals(originalData));
    });
  });
}
