import 'package:flutter/foundation.dart';
import 'telemetry_storage.dart';
import 'sqlite_telemetry_storage.dart';
import 'web_telemetry_storage.dart';

/// Factory for creating platform-specific TelemetryStorage implementations
///
/// This factory uses Flutter's kIsWeb constant to detect the platform at
/// compile time and instantiate the appropriate storage implementation:
///
/// - Web: WebTelemetryStorage (in-memory ring buffer + direct API sync)
/// - Native: SqliteTelemetryStorage (SQLite database + batch sync)
///
/// Usage:
/// ```dart
/// final storage = TelemetryStorageFactory.create();
/// ```
class TelemetryStorageFactory {
  /// Create a platform-specific TelemetryStorage instance
  ///
  /// Returns:
  /// - WebTelemetryStorage on web platform
  /// - SqliteTelemetryStorage on mobile/desktop platforms
  static TelemetryStorage create() {
    if (kIsWeb) {
      // Web platform: Use in-memory ring buffer with direct API sync
      if (kDebugMode) {
        print(
          '[TelemetryStorageFactory] Creating WebTelemetryStorage for web platform',
        );
      }
      return WebTelemetryStorage();
    } else {
      // Native platforms: Use SQLite database
      if (kDebugMode) {
        print(
          '[TelemetryStorageFactory] Creating SqliteTelemetryStorage for native platform',
        );
      }
      return SqliteTelemetryStorage();
    }
  }

  /// Create a WebTelemetryStorage with custom configuration
  ///
  /// This is useful for testing or when you need specific buffer settings.
  ///
  /// Parameters:
  /// - [bufferCapacity]: Maximum number of records in buffer (default: 125)
  /// - [flushThreshold]: Percentage full to trigger flush (default: 0.8)
  static WebTelemetryStorage createWebStorage({
    int bufferCapacity = 125,
    double flushThreshold = 0.8,
  }) {
    return WebTelemetryStorage(
      bufferCapacity: bufferCapacity,
      flushThreshold: flushThreshold,
    );
  }

  /// Create a SqliteTelemetryStorage
  ///
  /// This is useful for testing or when you explicitly need SQLite storage.
  static SqliteTelemetryStorage createSqliteStorage() {
    return SqliteTelemetryStorage();
  }

  /// Get the platform name for logging/debugging
  static String getPlatformName() {
    return kIsWeb ? 'web' : 'native';
  }

  /// Check if current platform is web
  static bool isWebPlatform() {
    return kIsWeb;
  }

  /// Check if current platform is native (mobile/desktop)
  static bool isNativePlatform() {
    return !kIsWeb;
  }
}
