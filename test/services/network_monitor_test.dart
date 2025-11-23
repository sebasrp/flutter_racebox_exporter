import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/services/network_monitor.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('NetworkMonitor', () {
    const baseUrl = 'https://api.example.com';

    group('measureLatency', () {
      test(
        'should return latency in milliseconds for successful health check',
        () async {
          final mockClient = MockClient((request) async {
            // Simulate a small delay
            await Future.delayed(const Duration(milliseconds: 50));
            return http.Response('{"status":"healthy"}', 200);
          });

          final monitor = NetworkMonitor(
            baseUrl: baseUrl,
            httpClient: mockClient,
          );

          final latency = await monitor.measureLatency();

          expect(latency, greaterThan(0));
          expect(latency, lessThan(9999));
        },
      );

      test('should return 9999 for failed health check', () async {
        final mockClient = MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        });

        final monitor = NetworkMonitor(
          baseUrl: baseUrl,
          httpClient: mockClient,
        );

        final latency = await monitor.measureLatency();

        expect(latency, equals(9999));
      });

      test('should return 9999 for timeout', () async {
        final mockClient = MockClient((request) async {
          // Simulate a timeout by waiting longer than the timeout duration
          await Future.delayed(const Duration(seconds: 10));
          return http.Response('{"status":"healthy"}', 200);
        });

        final monitor = NetworkMonitor(
          baseUrl: baseUrl,
          httpClient: mockClient,
        );

        final latency = await monitor.measureLatency();

        expect(latency, equals(9999));
      });

      test('should return 9999 for network error', () async {
        final mockClient = MockClient((request) async {
          throw Exception('Network error');
        });

        final monitor = NetworkMonitor(
          baseUrl: baseUrl,
          httpClient: mockClient,
        );

        final latency = await monitor.measureLatency();

        expect(latency, equals(9999));
      });
    });

    group('getRecommendedBatchSize', () {
      test('should return 250 for excellent quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getRecommendedBatchSize(NetworkQuality.excellent),
          equals(250),
        );
      });

      test('should return 500 for good quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getRecommendedBatchSize(NetworkQuality.good),
          equals(500),
        );
      });

      test('should return 1000 for poor quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getRecommendedBatchSize(NetworkQuality.poor),
          equals(1000),
        );
      });

      test('should return 0 for offline', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getRecommendedBatchSize(NetworkQuality.offline),
          equals(0),
        );
      });
    });

    group('getRecommendedUploadInterval', () {
      test('should return 10 seconds for excellent quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getRecommendedUploadInterval(NetworkQuality.excellent),
          equals(const Duration(seconds: 10)),
        );
      });

      test('should return 20 seconds for good quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getRecommendedUploadInterval(NetworkQuality.good),
          equals(const Duration(seconds: 20)),
        );
      });

      test('should return 40 seconds for poor quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getRecommendedUploadInterval(NetworkQuality.poor),
          equals(const Duration(seconds: 40)),
        );
      });

      test('should return 60 seconds for offline', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getRecommendedUploadInterval(NetworkQuality.offline),
          equals(const Duration(seconds: 60)),
        );
      });
    });

    group('getQualityDescription', () {
      test('should return correct description for excellent', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getQualityDescription(NetworkQuality.excellent),
          equals('Excellent (< 100ms)'),
        );
      });

      test('should return correct description for good', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getQualityDescription(NetworkQuality.good),
          equals('Good (100-300ms)'),
        );
      });

      test('should return correct description for poor', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getQualityDescription(NetworkQuality.poor),
          equals('Poor (> 300ms)'),
        );
      });

      test('should return correct description for offline', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(
          monitor.getQualityDescription(NetworkQuality.offline),
          equals('Offline'),
        );
      });
    });

    group('canUpload', () {
      test('should return true for excellent quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(monitor.canUpload(NetworkQuality.excellent), isTrue);
      });

      test('should return true for good quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(monitor.canUpload(NetworkQuality.good), isTrue);
      });

      test('should return true for poor quality', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(monitor.canUpload(NetworkQuality.poor), isTrue);
      });

      test('should return false for offline', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        expect(monitor.canUpload(NetworkQuality.offline), isFalse);
      });
    });

    group('Quality Classification', () {
      test('should classify latency < 100ms as excellent', () async {
        final mockClient = MockClient((request) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response('{"status":"healthy"}', 200);
        });

        final monitor = NetworkMonitor(
          baseUrl: baseUrl,
          httpClient: mockClient,
        );

        final latency = await monitor.measureLatency();
        // Note: We can't directly test _classifyQuality as it's private,
        // but we can verify the latency is in the expected range
        expect(latency, lessThan(100));
      });

      test('should classify latency 100-300ms as good', () async {
        final mockClient = MockClient((request) async {
          await Future.delayed(const Duration(milliseconds: 150));
          return http.Response('{"status":"healthy"}', 200);
        });

        final monitor = NetworkMonitor(
          baseUrl: baseUrl,
          httpClient: mockClient,
        );

        final latency = await monitor.measureLatency();
        expect(latency, greaterThanOrEqualTo(100));
        expect(latency, lessThan(300));
      });

      test('should classify latency > 300ms as poor', () async {
        final mockClient = MockClient((request) async {
          await Future.delayed(const Duration(milliseconds: 350));
          return http.Response('{"status":"healthy"}', 200);
        });

        final monitor = NetworkMonitor(
          baseUrl: baseUrl,
          httpClient: mockClient,
        );

        final latency = await monitor.measureLatency();
        expect(latency, greaterThanOrEqualTo(300));
        expect(latency, lessThan(9999));
      });
    });

    group('Batch Size Calculations', () {
      test('excellent quality batch size should equal 10 seconds at 25Hz', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        final batchSize = monitor.getRecommendedBatchSize(
          NetworkQuality.excellent,
        );
        final interval = monitor.getRecommendedUploadInterval(
          NetworkQuality.excellent,
        );

        // At 25Hz, 10 seconds = 250 points
        expect(batchSize, equals(250));
        expect(interval.inSeconds, equals(10));
        expect(batchSize, equals(interval.inSeconds * 25));
      });

      test('good quality batch size should equal 20 seconds at 25Hz', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        final batchSize = monitor.getRecommendedBatchSize(NetworkQuality.good);
        final interval = monitor.getRecommendedUploadInterval(
          NetworkQuality.good,
        );

        // At 25Hz, 20 seconds = 500 points
        expect(batchSize, equals(500));
        expect(interval.inSeconds, equals(20));
        expect(batchSize, equals(interval.inSeconds * 25));
      });

      test('poor quality batch size should equal 40 seconds at 25Hz', () {
        final monitor = NetworkMonitor(baseUrl: baseUrl);
        final batchSize = monitor.getRecommendedBatchSize(NetworkQuality.poor);
        final interval = monitor.getRecommendedUploadInterval(
          NetworkQuality.poor,
        );

        // At 25Hz, 40 seconds = 1000 points
        expect(batchSize, equals(1000));
        expect(interval.inSeconds, equals(40));
        expect(batchSize, equals(interval.inSeconds * 25));
      });
    });
  });
}
