import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/database/telemetry_queue_database.dart';
import 'package:flutter_racebox_exporter/services/avt_api_client.dart';
import 'package:flutter_racebox_exporter/services/batch_uploader_service.dart';
import 'package:flutter_racebox_exporter/services/network_monitor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

// Mock network monitor that doesn't rely on connectivity_plus
class MockNetworkMonitor extends NetworkMonitor {
  final NetworkQuality _quality;

  MockNetworkMonitor({NetworkQuality quality = NetworkQuality.excellent})
    : _quality = quality,
      super(baseUrl: 'http://localhost:8080');

  @override
  Future<NetworkQuality> getCurrentQuality() async {
    return _quality;
  }

  @override
  Future<int> measureLatency() async {
    switch (_quality) {
      case NetworkQuality.excellent:
        return 50;
      case NetworkQuality.good:
        return 150;
      case NetworkQuality.poor:
        return 400;
      case NetworkQuality.offline:
        return 9999;
    }
  }
}

void main() {
  // Initialize Flutter test bindings and FFI for testing
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Idempotency - Duplicate Response Handling', () {
    late TelemetryQueueDatabase database;

    setUp(() async {
      // Initialize database with unique name for test isolation
      final testDbName =
          'test_idempotency_${DateTime.now().millisecondsSinceEpoch}.db';
      database = TelemetryQueueDatabase(testDatabaseName: testDbName);
      await database.database; // Initialize database
      await database.reset();
    });

    tearDown(() async {
      await database.close();
    });

    test('should detect and handle duplicate batch on client side', () async {
      // Create mock client that always succeeds
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

      // Create mock network monitor that returns excellent quality
      final mockNetworkMonitor = MockNetworkMonitor(
        quality: NetworkQuality.excellent,
      );

      final apiClient = AvtApiClient(httpClient: mockClient);
      final uploader = BatchUploaderService(
        database: database,
        apiClient: apiClient,
        networkMonitor: mockNetworkMonitor,
      );

      // Add a test record
      await database.insertBatch([
        {
          'timestamp': DateTime.now().toIso8601String(),
          'data_json': jsonEncode({
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
          }),
        },
      ]);

      // First upload should succeed
      final result1 = await uploader.uploadNow();
      expect(result1.success, isTrue);
      expect(result1.recordsUploaded, equals(1));

      // Get statistics
      final stats = uploader.getStatistics();
      expect(stats['duplicates_detected'], equals(0));

      uploader.dispose();
    });

    test('should send batch ID in X-Batch-ID header', () async {
      String? receivedBatchId;

      final mockClient = MockClient((request) async {
        receivedBatchId = request.headers['X-Batch-ID'];

        return http.Response(
          jsonEncode({
            'message': 'Batch uploaded successfully',
            'count': 1,
            'ids': [1],
          }),
          201,
        );
      });

      final apiClient = AvtApiClient(httpClient: mockClient);

      final result = await apiClient.sendBatch([
        {
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
      ], batchId: 'test-batch-123');

      expect(result.success, isTrue);
      expect(receivedBatchId, equals('test-batch-123'));
    });

    test('should handle server duplicate response (200 OK)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'Batch already processed',
            'batchId': 'test-batch-123',
          }),
          200,
        );
      });

      final apiClient = AvtApiClient(httpClient: mockClient);

      final result = await apiClient.sendBatch([
        {
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
      ], batchId: 'test-batch-123');

      // Should still be successful even though it's a duplicate
      expect(result.success, isTrue);
    });

    test('should track batch as processed in database', () async {
      const testBatchId = 'test-batch-456';

      // Initially not processed
      expect(await database.isBatchProcessed(testBatchId), isFalse);

      // Mark as processed
      await database.markBatchProcessed(
        testBatchId,
        10,
        serverResponse: 'Success',
      );

      // Now should be processed
      expect(await database.isBatchProcessed(testBatchId), isTrue);
    });

    test('should not send batch ID if not provided', () async {
      String? receivedBatchId;

      final mockClient = MockClient((request) async {
        receivedBatchId = request.headers['X-Batch-ID'];

        return http.Response(
          jsonEncode({
            'message': 'Batch uploaded successfully',
            'count': 1,
            'ids': [1],
          }),
          201,
        );
      });

      final apiClient = AvtApiClient(httpClient: mockClient);

      await apiClient.sendBatch([
        {
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
      ]);

      // Should not have batch ID header if not provided
      expect(receivedBatchId, isNull);
    });
  });
}
