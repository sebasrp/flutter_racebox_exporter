import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/services/avt_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_racebox_exporter/config/environment_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AvtApiClient - Compression', () {
    test('should compress request body with gzip', () async {
      bool compressionHeaderPresent = false;
      bool requestIdPresent = false;
      List<int>? receivedBody;

      final mockClient = MockClient((request) async {
        // Verify headers
        compressionHeaderPresent =
            request.headers['Content-Encoding'] == 'gzip';
        requestIdPresent = request.headers.containsKey('X-Request-ID');

        // Store the body for verification
        receivedBody = request.bodyBytes;

        return http.Response(
          jsonEncode({
            'message': 'Batch uploaded successfully',
            'count': 2,
            'ids': [1, 2],
          }),
          201,
        );
      });

      final client = AvtApiClient(httpClient: mockClient);

      final telemetryBatch = [
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
        {
          'itow': 1001,
          'recorded_at': DateTime.now().millisecondsSinceEpoch,
          'latitude': 1.235,
          'longitude': 5.679,
          'wgs_altitude': 101.0,
          'msl_altitude': 96.0,
          'speed': 11.0,
          'heading': 46.0,
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
          'battery': 85.4,
          'is_charging': 0,
          'time_accuracy': 100,
          'validity_flags': 255,
        },
      ];

      final result = await client.sendBatch(
        telemetryBatch,
        deviceId: 'test-device',
        sessionId: 'test-session',
      );

      expect(result.success, true);
      expect(compressionHeaderPresent, true);
      expect(requestIdPresent, true);
      expect(receivedBody, isNotNull);

      // Verify the body is actually compressed (gzip magic bytes)
      expect(receivedBody![0], 0x1f); // gzip magic byte 1
      expect(receivedBody![1], 0x8b); // gzip magic byte 2

      // Decompress and verify content
      final decompressed = gzip.decode(receivedBody!);
      final decompressedJson = utf8.decode(decompressed);
      final data = jsonDecode(decompressedJson) as List;

      expect(data.length, 2);
      expect(data[0]['deviceId'], 'test-device');
      expect(data[0]['sessionId'], 'test-session');
    });

    test('should track compression statistics', () async {
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

      final client = AvtApiClient(httpClient: mockClient);

      // Reset stats to start fresh
      client.resetCompressionStats();

      final telemetryBatch = [
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
      ];

      await client.sendBatch(telemetryBatch);

      final stats = client.getCompressionStats();

      expect(stats['compression_count'], 1);
      expect(stats['total_uncompressed_bytes'], greaterThan(0));
      expect(stats['total_compressed_bytes'], greaterThan(0));
      expect(
        stats['total_compressed_bytes'],
        lessThan(stats['total_uncompressed_bytes']),
      );
      expect(stats['bandwidth_saved_bytes'], greaterThan(0));

      // Compression ratio should be positive (we saved bandwidth)
      final ratio = double.parse(stats['compression_ratio_percent']);
      expect(ratio, greaterThan(0));
      expect(ratio, lessThan(100));
    });

    test('should achieve significant compression ratio', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'Batch uploaded successfully',
            'count': 10,
            'ids': List.generate(10, (i) => i + 1),
          }),
          201,
        );
      });

      final client = AvtApiClient(httpClient: mockClient);
      client.resetCompressionStats();

      // Create a batch of 10 records (more data = better compression)
      final telemetryBatch = List.generate(
        10,
        (i) => {
          'itow': 1000 + i,
          'recorded_at': DateTime.now().millisecondsSinceEpoch + (i * 1000),
          'latitude': 1.234 + (i * 0.001),
          'longitude': 5.678 + (i * 0.001),
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
      );

      await client.sendBatch(telemetryBatch);

      final stats = client.getCompressionStats();
      final ratio = double.parse(stats['compression_ratio_percent']);

      // With JSON telemetry data, we should achieve at least 50% compression
      expect(ratio, greaterThan(50.0));
    });

    test('should reset compression statistics', () async {
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

      final client = AvtApiClient(httpClient: mockClient);

      final telemetryBatch = [
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
      ];

      await client.sendBatch(telemetryBatch);

      var stats = client.getCompressionStats();
      expect(stats['compression_count'], 1);

      client.resetCompressionStats();

      stats = client.getCompressionStats();
      expect(stats['compression_count'], 0);
      expect(stats['total_uncompressed_bytes'], 0);
      expect(stats['total_compressed_bytes'], 0);
      expect(stats['bandwidth_saved_bytes'], 0);
    });

    test('should include X-Request-ID header', () async {
      String? requestId;

      final mockClient = MockClient((request) async {
        requestId = request.headers['X-Request-ID'];

        return http.Response(
          jsonEncode({
            'message': 'Batch uploaded successfully',
            'count': 1,
            'ids': [1],
          }),
          201,
        );
      });

      final client = AvtApiClient(httpClient: mockClient);

      final telemetryBatch = [
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
      ];

      await client.sendBatch(telemetryBatch);

      expect(requestId, isNotNull);
      expect(requestId, isNotEmpty);

      // UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      expect(
        requestId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('should handle compression with empty batch', () async {
      final mockClient = MockClient((request) async {
        return http.Response('', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);
      client.resetCompressionStats();

      final result = await client.sendBatch([]);

      expect(result.success, true);

      final stats = client.getCompressionStats();
      expect(stats['compression_count'], 0);
    });
  });

  group('AvtApiClient - Existing Functionality', () {
    test('should handle successful upload', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'Batch uploaded successfully',
            'count': 1,
            'ids': [123],
          }),
          201,
        );
      });

      final client = AvtApiClient(httpClient: mockClient);

      final result = await client.sendBatch([
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

      expect(result.success, true);
      expect(result.savedIds, [123]);
      expect(result.attemptCount, 1);
    });

    test('should handle server error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Internal server error'}),
          500,
        );
      });

      final client = AvtApiClient(httpClient: mockClient);

      final result = await client.sendBatch([
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

      expect(result.success, false);
      // After retries, the error message is "Failed after N attempts"
      expect(result.error, contains('Failed after'));
      expect(result.attemptCount, 3);
    });

    test('should handle non-JSON response on success status code', () async {
      final mockClient = MockClient((request) async {
        // Server returns 200 but with non-JSON body
        return http.Response('OK', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      final result = await client.sendBatch([
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

      expect(result.success, false);
      expect(result.error, contains('Failed to parse response'));
      expect(result.error, contains('Body: OK'));
      expect(result.attemptCount, 1);
    });

    test(
      'should handle malformed JSON response on success status code',
      () async {
        final mockClient = MockClient((request) async {
          // Server returns 201 but with malformed JSON
          return http.Response('{"incomplete": ', 201);
        });

        final client = AvtApiClient(httpClient: mockClient);

        final result = await client.sendBatch([
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

        expect(result.success, false);
        expect(result.error, contains('Failed to parse response'));
        expect(result.attemptCount, 1);
      },
    );
  });

  group('AvtApiClient - Environment Configuration', () {
    setUp(() {
      // Clear all preferences before each test
      SharedPreferences.setMockInitialValues({});
    });

    test('should use default testing URL when no preferences set', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for async config loading
      await Future.delayed(const Duration(milliseconds: 100));

      final url = client.baseUrl;

      // Should be testing URL (localhost or Android emulator)
      expect(url, anyOf('http://localhost:8080', 'http://10.0.2.2:8080'));
    });

    test('should load production environment from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        EnvironmentConfig.environmentKey: 'production',
      });

      final mockClient = MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for async config loading
      await Future.delayed(const Duration(milliseconds: 100));

      expect(client.baseUrl, 'https://avt.sebasr.com:8080');
    });

    test('should load testing environment from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        EnvironmentConfig.environmentKey: 'testing',
      });

      final mockClient = MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for async config loading
      await Future.delayed(const Duration(milliseconds: 100));

      final url = client.baseUrl;
      expect(url, anyOf('http://localhost:8080', 'http://10.0.2.2:8080'));
    });

    test('should fall back to custom URL if environment not set', () async {
      SharedPreferences.setMockInitialValues({
        AvtApiConfig.urlKey: 'http://custom-server:9000',
      });

      final mockClient = MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for async config loading
      await Future.delayed(const Duration(milliseconds: 100));

      expect(client.baseUrl, 'http://custom-server:9000');
    });

    test('should prioritize environment over custom URL', () async {
      SharedPreferences.setMockInitialValues({
        EnvironmentConfig.environmentKey: 'production',
        AvtApiConfig.urlKey: 'http://custom-server:9000',
      });

      final mockClient = MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for async config loading
      await Future.delayed(const Duration(milliseconds: 100));

      // Environment should take priority
      expect(client.baseUrl, 'https://avt.sebasr.com:8080');
    });

    test('should save custom URL to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});

      final mockClient = MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for initial config load
      await Future.delayed(const Duration(milliseconds: 100));

      await client.setBaseUrl('http://new-server:8888');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AvtApiConfig.urlKey), 'http://new-server:8888');

      // The baseUrl getter returns the internal _baseUrl which is set by setBaseUrl
      expect(client.baseUrl, 'http://new-server:8888');
    });

    test('should strip trailing slash when setting URL', () async {
      SharedPreferences.setMockInitialValues({});

      final mockClient = MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for initial config load
      await Future.delayed(const Duration(milliseconds: 100));

      await client.setBaseUrl('http://new-server:8888/');

      expect(client.baseUrl, 'http://new-server:8888');
    });

    test('should handle environment parsing errors gracefully', () async {
      // Invalid environment value should default to testing
      SharedPreferences.setMockInitialValues({
        EnvironmentConfig.environmentKey: 'invalid-env',
      });

      final mockClient = MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for async config loading
      await Future.delayed(const Duration(milliseconds: 100));

      final url = client.baseUrl;
      // Should fall back to testing URL
      expect(url, anyOf('http://localhost:8080', 'http://10.0.2.2:8080'));
    });

    test('should use correct URL in API requests', () async {
      SharedPreferences.setMockInitialValues({
        EnvironmentConfig.environmentKey: 'production',
      });

      String? requestedUrl;
      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for async config loading
      await Future.delayed(const Duration(milliseconds: 100));

      await client.testConnection();

      expect(requestedUrl, 'https://avt.sebasr.com:8080/api/v1/health');
    });

    test('should update URL and make requests to new endpoint', () async {
      SharedPreferences.setMockInitialValues({});

      String? requestedUrl;
      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for initial config load
      await Future.delayed(const Duration(milliseconds: 100));

      await client.setBaseUrl('http://test-server:7777');
      await client.testConnection();

      expect(requestedUrl, 'http://test-server:7777/api/v1/health');
    });

    test('should maintain URL across multiple requests', () async {
      SharedPreferences.setMockInitialValues({
        EnvironmentConfig.environmentKey: 'production',
      });

      final requestedUrls = <String>[];
      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        return http.Response('{"status": "ok"}', 200);
      });

      final client = AvtApiClient(httpClient: mockClient);

      // Give time for async config loading
      await Future.delayed(const Duration(milliseconds: 100));

      await client.testConnection();
      await client.testConnection();
      await client.testConnection();

      expect(requestedUrls.length, 3);
      for (final url in requestedUrls) {
        expect(url, 'https://avt.sebasr.com:8080/api/v1/health');
      }
    });
  });

  group('AvtApiConfig', () {
    test('should have correct default URL', () {
      final url = AvtApiConfig.defaultUrl;

      // Should be a testing URL (platform-specific)
      expect(url, anyOf('http://localhost:8080', 'http://10.0.2.2:8080'));
    });

    test('should have correct timeout duration', () {
      expect(AvtApiConfig.timeout, const Duration(seconds: 30));
    });

    test('should have correct max retries', () {
      expect(AvtApiConfig.maxRetries, 3);
    });

    test('should have correct URL storage key', () {
      expect(AvtApiConfig.urlKey, 'avt_service_url');
    });
  });
}
