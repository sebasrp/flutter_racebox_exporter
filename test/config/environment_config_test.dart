import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/config/environment_config.dart';

void main() {
  group('EnvironmentConfig', () {
    group('getUrlForEnvironment', () {
      test('should return testing URL for testing environment', () {
        final url = EnvironmentConfig.getUrlForEnvironment(
          ApiEnvironment.testing,
        );

        // Should return a localhost variant (exact URL depends on platform)
        expect(url, contains('localhost'));
        expect(url, contains('8080'));
      });

      test('should return production URL for production environment', () {
        final url = EnvironmentConfig.getUrlForEnvironment(
          ApiEnvironment.production,
        );

        expect(url, 'http://avt.sebasr.com:8080');
      });
    });

    group('getTestingUrl', () {
      test('should return valid localhost URL', () {
        final url = EnvironmentConfig.getTestingUrl();

        // Should be either localhost or Android emulator address
        expect(url, anyOf('http://localhost:8080', 'http://10.0.2.2:8080'));
      });

      test('should include port 8080', () {
        final url = EnvironmentConfig.getTestingUrl();
        expect(url, contains(':8080'));
      });

      test('should use http protocol for testing', () {
        final url = EnvironmentConfig.getTestingUrl();
        expect(url, startsWith('http://'));
      });
    });

    group('parseEnvironment', () {
      test('should parse "production" to production environment', () {
        expect(
          EnvironmentConfig.parseEnvironment('production'),
          ApiEnvironment.production,
        );
      });

      test('should parse "PRODUCTION" (case insensitive)', () {
        expect(
          EnvironmentConfig.parseEnvironment('PRODUCTION'),
          ApiEnvironment.production,
        );
      });

      test('should parse "Production" (mixed case)', () {
        expect(
          EnvironmentConfig.parseEnvironment('Production'),
          ApiEnvironment.production,
        );
      });

      test('should parse "testing" to testing environment', () {
        expect(
          EnvironmentConfig.parseEnvironment('testing'),
          ApiEnvironment.testing,
        );
      });

      test('should parse "TESTING" (case insensitive)', () {
        expect(
          EnvironmentConfig.parseEnvironment('TESTING'),
          ApiEnvironment.testing,
        );
      });

      test('should default to testing for null', () {
        expect(
          EnvironmentConfig.parseEnvironment(null),
          ApiEnvironment.testing,
        );
      });

      test('should default to testing for empty string', () {
        expect(EnvironmentConfig.parseEnvironment(''), ApiEnvironment.testing);
      });

      test('should default to testing for unknown values', () {
        expect(
          EnvironmentConfig.parseEnvironment('unknown'),
          ApiEnvironment.testing,
        );
        expect(
          EnvironmentConfig.parseEnvironment('staging'),
          ApiEnvironment.testing,
        );
        expect(
          EnvironmentConfig.parseEnvironment('dev'),
          ApiEnvironment.testing,
        );
      });
    });

    group('environmentToString', () {
      test('should convert testing environment to "testing"', () {
        expect(
          EnvironmentConfig.environmentToString(ApiEnvironment.testing),
          'testing',
        );
      });

      test('should convert production environment to "production"', () {
        expect(
          EnvironmentConfig.environmentToString(ApiEnvironment.production),
          'production',
        );
      });
    });

    group('round-trip conversion', () {
      test('should maintain value through parse and toString', () {
        final original = ApiEnvironment.production;
        final stringValue = EnvironmentConfig.environmentToString(original);
        final parsed = EnvironmentConfig.parseEnvironment(stringValue);

        expect(parsed, original);
      });

      test('should work for testing environment', () {
        final original = ApiEnvironment.testing;
        final stringValue = EnvironmentConfig.environmentToString(original);
        final parsed = EnvironmentConfig.parseEnvironment(stringValue);

        expect(parsed, original);
      });
    });

    group('SharedPreferences keys', () {
      test('should have correct environment key constant', () {
        expect(EnvironmentConfig.environmentKey, 'api_environment');
      });

      test('should have correct custom URL key constant', () {
        expect(EnvironmentConfig.customUrlKey, 'avt_service_url');
      });

      test('keys should be unique', () {
        expect(
          EnvironmentConfig.environmentKey,
          isNot(EnvironmentConfig.customUrlKey),
        );
      });
    });

    group('URL validation', () {
      test('production URL should use HTTP', () {
        final url = EnvironmentConfig.getUrlForEnvironment(
          ApiEnvironment.production,
        );
        expect(url, startsWith('http://'));
      });

      test('production URL should have valid domain', () {
        final url = EnvironmentConfig.getUrlForEnvironment(
          ApiEnvironment.production,
        );
        expect(url, contains('avt.sebasr.com'));
      });

      test('all URLs should have port number', () {
        final productionUrl = EnvironmentConfig.getUrlForEnvironment(
          ApiEnvironment.production,
        );
        final testingUrl = EnvironmentConfig.getUrlForEnvironment(
          ApiEnvironment.testing,
        );

        expect(productionUrl, contains(':'));
        expect(testingUrl, contains(':'));
      });

      test('URLs should not have trailing slashes', () {
        final productionUrl = EnvironmentConfig.getUrlForEnvironment(
          ApiEnvironment.production,
        );
        final testingUrl = EnvironmentConfig.getUrlForEnvironment(
          ApiEnvironment.testing,
        );

        expect(productionUrl, isNot(endsWith('/')));
        expect(testingUrl, isNot(endsWith('/')));
      });
    });
  });

  group('ApiEnvironment enum', () {
    test('should have testing value', () {
      expect(ApiEnvironment.values, contains(ApiEnvironment.testing));
    });

    test('should have production value', () {
      expect(ApiEnvironment.values, contains(ApiEnvironment.production));
    });

    test('should have exactly 2 values', () {
      expect(ApiEnvironment.values.length, 2);
    });

    test('enum name should match expected values', () {
      expect(ApiEnvironment.testing.name, 'testing');
      expect(ApiEnvironment.production.name, 'production');
    });
  });
}
