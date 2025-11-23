import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/database/telemetry_queue_database.dart';
import 'package:flutter_racebox_exporter/services/avt_api_client.dart';
import 'package:flutter_racebox_exporter/services/batch_uploader_service.dart';
import 'package:flutter_racebox_exporter/services/network_monitor.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

void main() {
  group('BatchUploaderService', () {
    late TelemetryQueueDatabase database;
    late AvtApiClient apiClient;
    late NetworkMonitor networkMonitor;
    late BatchUploaderService uploader;

    setUp(() async {
      // Initialize database
      database = TelemetryQueueDatabase();
      await database.reset();

      // Create mock HTTP client that always succeeds
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'Batch uploaded successfully',
            'count': 1,
            'ids': [1],
          }),
          201,
        );
      });

      // Initialize API client with mock
      apiClient = AvtApiClient(httpClient: mockClient);

      // Initialize network monitor with mock that returns excellent quality
      final healthMockClient = MockClient((request) async {
        return http.Response('{"status":"healthy"}', 200);
      });

      networkMonitor = NetworkMonitor(
        baseUrl: 'https://api.example.com',
        httpClient: healthMockClient,
      );

      // Create uploader service
      uploader = BatchUploaderService(
        database: database,
        apiClient: apiClient,
        networkMonitor: networkMonitor,
      );
    });

    tearDown(() async {
      uploader.dispose();
      await database.close();
    });

    group('Statistics', () {
      test('should return initial statistics', () {
        final stats = uploader.getStatistics();

        expect(stats['total_uploaded'], equals(0));
        expect(stats['total_failed'], equals(0));
        expect(stats['last_successful_upload'], isNull);
        expect(stats['last_failed_upload'], isNull);
        expect(stats['is_uploading'], isFalse);
      });

      test('should return queue size', () async {
        // Initially empty
        expect(await uploader.getQueueSize(), equals(0));

        // Add some records
        await database.insertBatch([
          {
            'timestamp': DateTime.now().toIso8601String(),
            'data_json': {'test': 'data1'},
          },
          {
            'timestamp': DateTime.now().toIso8601String(),
            'data_json': {'test': 'data2'},
          },
        ]);

        expect(await uploader.getQueueSize(), equals(2));
      });

      test('should return oldest unsent timestamp', () async {
        // Initially null
        expect(await uploader.getOldestUnsentTimestamp(), isNull);

        // Add a record
        final now = DateTime.now();
        await database.insertBatch([
          {
            'timestamp': now.toIso8601String(),
            'data_json': {'test': 'data'},
          },
        ]);

        final oldest = await uploader.getOldestUnsentTimestamp();
        expect(oldest, isNotNull);
        expect(oldest!.difference(now).inSeconds, lessThan(2));
      });
    });

    group('Cleanup', () {
      test('should clean up old uploaded records', () async {
        // Add some records
        await database.insertBatch([
          {
            'timestamp': DateTime.now().toIso8601String(),
            'data_json': {'test': 'data1'},
          },
          {
            'timestamp': DateTime.now().toIso8601String(),
            'data_json': {'test': 'data2'},
          },
        ]);

        // Mark them as uploaded
        final records = await database.fetchUnsentRecords();
        final recordIds = records.map((r) => r['id'] as int).toList();
        await database.markAsUploaded(recordIds, 'test-batch');

        // Clean up (should delete records older than 7 days, so nothing deleted yet)
        final deleted = await uploader.cleanupOldRecords();
        expect(deleted, equals(0));

        // Verify records still exist
        final stats = await database.getQueueStats();
        expect(stats['uploaded_count'], equals(2));
      });
    });

    group('Auto Upload', () {
      test('should start and stop auto upload', () {
        uploader.startAutoUpload();
        // Should not throw when starting again
        uploader.startAutoUpload();

        uploader.stopAutoUpload();
        // Should not throw when stopping again
        uploader.stopAutoUpload();
      });
    });

    group('Manual Upload', () {
      test('should handle empty queue', () async {
        final result = await uploader.uploadNow();

        expect(result.success, isTrue);
        expect(result.recordsUploaded, equals(0));
      });

      test('should upload records from queue', () async {
        // Add test records to queue
        await database.insertBatch([
          {
            'timestamp': DateTime.now().toIso8601String(),
            'data_json': {
              'itow': 1000,
              'recorded_at': DateTime.now().millisecondsSinceEpoch,
              'latitude': 1.234,
              'longitude': 5.678,
              'wgs_altitude': 100.0,
              'msl_altitude': 95.0,
              'speed': 10.5,
              'heading': 45.0,
              'num_satellites': 12,
              'fix_status': 3,
              'horizontal_accuracy': 2.5,
              'vertical_accuracy': 3.0,
              'speed_accuracy': 0.5,
              'heading_accuracy': 1.0,
              'pdop': 1.5,
              'is_fix_valid': 1,
              'g_force_x': 0.1,
              'g_force_y': 0.2,
              'g_force_z': 1.0,
              'rotation_x': 0.0,
              'rotation_y': 0.0,
              'rotation_z': 0.0,
              'battery': 85.5,
              'is_charging': 0,
              'time_accuracy': 100,
              'validity_flags': 255,
            },
          },
        ]);

        // Verify queue has records
        expect(await uploader.getQueueSize(), equals(1));

        // Upload
        final result = await uploader.uploadNow();

        expect(result.success, isTrue);
        expect(result.recordsUploaded, equals(1));

        // Verify queue is now empty
        expect(await uploader.getQueueSize(), equals(0));

        // Verify statistics updated
        final stats = uploader.getStatistics();
        expect(stats['total_uploaded'], equals(1));
        expect(stats['total_failed'], equals(0));
        expect(stats['last_successful_upload'], isNotNull);
      });

      test('should handle upload failure', () async {
        // Create API client that fails
        final failingMockClient = MockClient((request) async {
          return http.Response(jsonEncode({'error': 'Server error'}), 500);
        });

        final failingApiClient = AvtApiClient(httpClient: failingMockClient);

        final failingUploader = BatchUploaderService(
          database: database,
          apiClient: failingApiClient,
          networkMonitor: networkMonitor,
        );

        // Add test record
        await database.insertBatch([
          {
            'timestamp': DateTime.now().toIso8601String(),
            'data_json': {
              'itow': 1000,
              'recorded_at': DateTime.now().millisecondsSinceEpoch,
              'latitude': 1.234,
              'longitude': 5.678,
              'wgs_altitude': 100.0,
              'msl_altitude': 95.0,
              'speed': 10.5,
              'heading': 45.0,
              'num_satellites': 12,
              'fix_status': 3,
              'horizontal_accuracy': 2.5,
              'vertical_accuracy': 3.0,
              'speed_accuracy': 0.5,
              'heading_accuracy': 1.0,
              'pdop': 1.5,
              'is_fix_valid': 1,
              'g_force_x': 0.1,
              'g_force_y': 0.2,
              'g_force_z': 1.0,
              'rotation_x': 0.0,
              'rotation_y': 0.0,
              'rotation_z': 0.0,
              'battery': 85.5,
              'is_charging': 0,
              'time_accuracy': 100,
              'validity_flags': 255,
            },
          },
        ]);

        // Upload should fail
        final result = await failingUploader.uploadNow();

        expect(result.success, isFalse);
        expect(result.recordsUploaded, equals(0));
        expect(result.error, isNotNull);

        // Records should still be in queue
        expect(await failingUploader.getQueueSize(), equals(1));

        // Verify statistics updated
        final stats = failingUploader.getStatistics();
        expect(stats['total_uploaded'], equals(0));
        expect(stats['total_failed'], equals(1));
        expect(stats['last_failed_upload'], isNotNull);

        failingUploader.dispose();
      });
    });
  });
}
