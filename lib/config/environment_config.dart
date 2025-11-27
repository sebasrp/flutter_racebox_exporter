import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Represents the available default API environments for the application.
enum ApiEnvironment { testing, production }

/// Configuration class for managing environment-specific settings.
///
/// This class provides utilities for switching between testing and production
/// environments, including platform-specific URL handling and SharedPreferences
/// key management.
class EnvironmentConfig {
  static const String environmentKey = 'api_environment';
  static const String customUrlKey = 'avt_service_url';

  static const String _productionUrl = 'https://avt.sebasr.com:8080';
  static const String _defaultTestingUrl = 'http://localhost:8080';
  static const String _androidEmulatorUrl = 'http://10.0.2.2:8080';

  /// Returns the appropriate testing URL based on the current platform.
  static String getTestingUrl() {
    if (kIsWeb) {
      return _defaultTestingUrl;
    }

    try {
      if (Platform.isAndroid) {
        return _androidEmulatorUrl;
      }
    } catch (_) {}
    return _defaultTestingUrl;
  }

  /// Returns the appropriate URL for the given environment.
  ///
  /// - [ApiEnvironment.testing]: Returns platform-specific testing URL via [getTestingUrl]
  /// - [ApiEnvironment.production]: Returns the production URL
  static String getUrlForEnvironment(ApiEnvironment env) {
    switch (env) {
      case ApiEnvironment.testing:
        return getTestingUrl();
      case ApiEnvironment.production:
        return _productionUrl;
    }
  }

  /// Parses a string value into an [ApiEnvironment] enum.
  ///
  /// - 'production' → [ApiEnvironment.production]
  /// - 'testing' or `null` → [ApiEnvironment.testing] (default)
  /// - Any other value → [ApiEnvironment.testing] (default)
  //
  static ApiEnvironment parseEnvironment(String? value) {
    if (value == null) {
      return ApiEnvironment.testing;
    }

    switch (value.toLowerCase()) {
      case 'production':
        return ApiEnvironment.production;
      case 'testing':
      default:
        return ApiEnvironment.testing;
    }
  }

  /// Converts an [ApiEnvironment] enum to its string representation.
  ///
  /// Returns the enum name without the class prefix:
  /// - [ApiEnvironment.testing] → 'testing'
  /// - [ApiEnvironment.production] → 'production'
  static String environmentToString(ApiEnvironment env) {
    return env.name;
  }
}
