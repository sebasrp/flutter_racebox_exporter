import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

/// Network quality levels based on latency measurements
enum NetworkQuality {
  /// Latency < 100ms - Near real-time performance
  excellent,

  /// Latency 100-300ms - Good performance
  good,

  /// Latency > 300ms - Poor performance
  poor,

  /// No network connectivity
  offline,
}

/// Monitors network connectivity and quality
class NetworkMonitor {
  final String baseUrl;
  final http.Client? httpClient;
  final Logger _logger = Logger();

  NetworkMonitor({required this.baseUrl, this.httpClient});

  /// Get the current network quality based on connectivity and latency
  Future<NetworkQuality> getCurrentQuality() async {
    try {
      // 1. Check connectivity type
      final connectivityList = await Connectivity().checkConnectivity();

      if (connectivityList.contains(ConnectivityResult.none) ||
          connectivityList.isEmpty) {
        _logger.d('📡 Network quality: offline (no connectivity)');
        return NetworkQuality.offline;
      }

      // 2. Measure latency with health check ping
      final latency = await measureLatency();

      // 3. Classify quality based on latency
      final quality = _classifyQuality(latency);

      // Get the primary connectivity type (prefer WiFi > Ethernet > Mobile)
      final primaryType = _getPrimaryConnectivity(connectivityList);

      _logger.d(
        '📡 Network quality: ${quality.name} (latency: ${latency}ms, type: ${primaryType.name})',
      );

      return quality;
    } catch (e) {
      _logger.w('⚠️ Error checking network quality: $e');
      return NetworkQuality.offline;
    }
  }

  /// Measure network latency by pinging the health endpoint
  /// Returns latency in milliseconds, or 9999 if unreachable
  Future<int> measureLatency() async {
    final stopwatch = Stopwatch()..start();

    try {
      final client = httpClient ?? http.Client();
      final uri = Uri.parse('$baseUrl/api/v1/health');

      _logger.d('🏓 Pinging health endpoint: $uri');

      final response =
          await client.get(uri).timeout(const Duration(seconds: 5));

      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200) {
        _logger.d('✅ Health check successful: ${latency}ms');
        return latency;
      } else {
        _logger.w('⚠️ Health check returned ${response.statusCode}');
        return 9999; // Treat as poor/offline
      }
    } catch (e) {
      stopwatch.stop();
      _logger.w('❌ Health check failed: $e');
      return 9999; // Treat as poor/offline
    }
  }

  /// Classify network quality based on latency
  NetworkQuality _classifyQuality(int latencyMs) {
    if (latencyMs >= 9999) {
      return NetworkQuality.offline;
    } else if (latencyMs < 100) {
      return NetworkQuality.excellent;
    } else if (latencyMs < 300) {
      return NetworkQuality.good;
    } else {
      return NetworkQuality.poor;
    }
  }

  /// Get the recommended batch size based on network quality
  /// Returns number of telemetry points to batch together
  int getRecommendedBatchSize(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return 250; // 10 seconds at 25Hz
      case NetworkQuality.good:
        return 500; // 20 seconds at 25Hz
      case NetworkQuality.poor:
        return 1000; // 40 seconds at 25Hz
      case NetworkQuality.offline:
        return 0; // Don't upload when offline
    }
  }

  /// Get the recommended upload interval based on network quality
  /// Returns duration between upload attempts
  Duration getRecommendedUploadInterval(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return const Duration(seconds: 10);
      case NetworkQuality.good:
        return const Duration(seconds: 20);
      case NetworkQuality.poor:
        return const Duration(seconds: 40);
      case NetworkQuality.offline:
        return const Duration(seconds: 60); // Check every minute when offline
    }
  }

  /// Get a human-readable description of the network quality
  String getQualityDescription(NetworkQuality quality) {
    switch (quality) {
      case NetworkQuality.excellent:
        return 'Excellent (< 100ms)';
      case NetworkQuality.good:
        return 'Good (100-300ms)';
      case NetworkQuality.poor:
        return 'Poor (> 300ms)';
      case NetworkQuality.offline:
        return 'Offline';
    }
  }

  /// Check if the network is suitable for uploading
  bool canUpload(NetworkQuality quality) {
    return quality != NetworkQuality.offline;
  }

  /// Get connectivity type as a string
  Future<String> getConnectivityType() async {
    try {
      final connectivityList = await Connectivity().checkConnectivity();

      if (connectivityList.isEmpty ||
          connectivityList.contains(ConnectivityResult.none)) {
        return 'None';
      }

      // Get the primary connectivity type
      final primaryType = _getPrimaryConnectivity(connectivityList);

      if (primaryType == ConnectivityResult.wifi) {
        return 'WiFi';
      } else if (primaryType == ConnectivityResult.mobile) {
        return 'Mobile';
      } else if (primaryType == ConnectivityResult.ethernet) {
        return 'Ethernet';
      } else {
        return 'None';
      }
    } catch (e) {
      _logger.w('⚠️ Error getting connectivity type: $e');
      return 'Unknown';
    }
  }

  /// Check if currently connected to WiFi
  Future<bool> isWiFi() async {
    try {
      final connectivityList = await Connectivity().checkConnectivity();
      return connectivityList.contains(ConnectivityResult.wifi);
    } catch (e) {
      _logger.w('⚠️ Error checking WiFi status: $e');
      return false;
    }
  }

  /// Stream of connectivity changes
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return Connectivity().onConnectivityChanged;
  }

  /// Get the primary connectivity type from a list of connectivity results
  /// Prioritizes: WiFi > Ethernet > Mobile > Other
  ConnectivityResult _getPrimaryConnectivity(
    List<ConnectivityResult> connectivityList,
  ) {
    if (connectivityList.contains(ConnectivityResult.wifi)) {
      return ConnectivityResult.wifi;
    } else if (connectivityList.contains(ConnectivityResult.ethernet)) {
      return ConnectivityResult.ethernet;
    } else if (connectivityList.contains(ConnectivityResult.mobile)) {
      return ConnectivityResult.mobile;
    } else if (connectivityList.isNotEmpty) {
      return connectivityList.first;
    } else {
      return ConnectivityResult.none;
    }
  }
}
