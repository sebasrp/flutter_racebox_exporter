import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Configuration for AVT API
class AvtApiConfig {
  static const String urlKey = 'avt_service_url';
  static const String defaultUrl = 'http://localhost:8080';
  static const Duration timeout = Duration(seconds: 30);
  static const int maxRetries = 3;
}

/// Result of a batch upload operation
class BatchUploadResult {
  final bool success;
  final List<int> savedIds;
  final String? error;
  final int attemptCount;

  BatchUploadResult({
    required this.success,
    this.savedIds = const [],
    this.error,
    this.attemptCount = 1,
  });
}

/// Client for communicating with AVT service
class AvtApiClient {
  final http.Client _httpClient;
  String _baseUrl = AvtApiConfig.defaultUrl;

  AvtApiClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client() {
    // Load config deferred to avoid initialization issues
    Future.microtask(() => _loadConfig());
  }

  /// Load configuration from shared preferences
  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _baseUrl =
          prefs.getString(AvtApiConfig.urlKey) ?? AvtApiConfig.defaultUrl;
    } catch (e) {
      if (kDebugMode) {
        print('[AvtApiClient] Error loading config: $e');
      }
      // Keep using default URL on error
      _baseUrl = AvtApiConfig.defaultUrl;
    }
  }

  /// Get current base URL
  String get baseUrl => _baseUrl;

  /// Set and save base URL
  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AvtApiConfig.urlKey, _baseUrl);
  }

  /// Send batch of telemetry data to AVT service
  Future<BatchUploadResult> sendBatch(
    List<Map<String, dynamic>> telemetryBatch, {
    String? deviceId,
    String? sessionId,
  }) async {
    if (telemetryBatch.isEmpty) {
      return BatchUploadResult(success: true, savedIds: []);
    }

    // Convert database rows to API format
    final apiData = telemetryBatch.map((row) {
      // Ensure recorded_at is an integer
      final recordedAt = row['recorded_at'];
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        recordedAt is int ? recordedAt : int.parse(recordedAt.toString()),
        isUtc: true,
      ).toIso8601String();

      return {
        'iTOW': row['itow'] ?? 0,
        'timestamp': timestamp,
        'deviceId': deviceId ?? row['device_id'],
        'sessionId': sessionId ?? row['session_id'],
        'gps': {
          'latitude': (row['latitude'] as num?)?.toDouble() ?? 0.0,
          'longitude': (row['longitude'] as num?)?.toDouble() ?? 0.0,
          'wgsAltitude': (row['wgs_altitude'] as num?)?.toDouble() ?? 0.0,
          'mslAltitude': (row['msl_altitude'] as num?)?.toDouble() ?? 0.0,
          'speed': (row['speed'] as num?)?.toDouble() ?? 0.0,
          'heading': (row['heading'] as num?)?.toDouble() ?? 0.0,
          'numSatellites': row['num_satellites'] ?? 0,
          'fixStatus': row['fix_status'] ?? 0,
          'horizontalAccuracy':
              (row['horizontal_accuracy'] as num?)?.toDouble() ?? 0.0,
          'verticalAccuracy':
              (row['vertical_accuracy'] as num?)?.toDouble() ?? 0.0,
          'speedAccuracy': (row['speed_accuracy'] as num?)?.toDouble() ?? 0.0,
          'headingAccuracy':
              (row['heading_accuracy'] as num?)?.toDouble() ?? 0.0,
          'pdop': (row['pdop'] as num?)?.toDouble() ?? 0.0,
          'isFixValid': (row['is_fix_valid'] ?? 0) == 1,
        },
        'motion': {
          'gForceX': (row['g_force_x'] as num?)?.toDouble() ?? 0.0,
          'gForceY': (row['g_force_y'] as num?)?.toDouble() ?? 0.0,
          'gForceZ': (row['g_force_z'] as num?)?.toDouble() ?? 0.0,
          'rotationX': (row['rotation_x'] as num?)?.toDouble() ?? 0.0,
          'rotationY': (row['rotation_y'] as num?)?.toDouble() ?? 0.0,
          'rotationZ': (row['rotation_z'] as num?)?.toDouble() ?? 0.0,
        },
        'battery': (row['battery'] as num?)?.toDouble() ?? 0.0,
        'isCharging': (row['is_charging'] ?? 0) == 1,
        'timeAccuracy': row['time_accuracy'] ?? 0,
        'validityFlags': row['validity_flags'] ?? 0,
      };
    }).toList();

    // Attempt upload with retries
    for (int attempt = 1; attempt <= AvtApiConfig.maxRetries; attempt++) {
      try {
        final jsonBody = jsonEncode(apiData);

        if (kDebugMode) {
          print('[AvtApiClient] Uploading ${apiData.length} records');
          if (apiData.isNotEmpty) {
            print(
              '[AvtApiClient] First record timestamp: ${apiData.first['timestamp']}',
            );
          }
        }

        final response = await _httpClient
            .post(
              Uri.parse('$_baseUrl/api/telemetry/batch'),
              headers: {'Content-Type': 'application/json'},
              body: jsonBody,
            )
            .timeout(AvtApiConfig.timeout);

        if (response.statusCode == 201) {
          final responseData = jsonDecode(response.body);
          final ids = (responseData['ids'] as List<dynamic>)
              .map((id) => id as int)
              .toList();

          if (kDebugMode) {
            print('[AvtApiClient] Successfully uploaded ${ids.length} records');
          }

          return BatchUploadResult(
            success: true,
            savedIds: ids,
            attemptCount: attempt,
          );
        } else {
          String errorDetails = response.body;
          try {
            final errorJson = jsonDecode(response.body);
            errorDetails =
                errorJson['error'] ?? errorJson['details'] ?? response.body;
          } catch (_) {
            // If not JSON, use raw body
          }

          final error = 'Server returned ${response.statusCode}: $errorDetails';
          if (kDebugMode) {
            print('[AvtApiClient] Upload failed: $error');
            print('[AvtApiClient] Full response: ${response.body}');
          }

          // Don't retry on client errors (4xx)
          if (response.statusCode >= 400 && response.statusCode < 500) {
            return BatchUploadResult(
              success: false,
              error: error,
              attemptCount: attempt,
            );
          }
        }
      } on TimeoutException {
        if (kDebugMode) {
          print('[AvtApiClient] Request timeout on attempt $attempt');
        }
      } catch (e) {
        if (kDebugMode) {
          print('[AvtApiClient] Error on attempt $attempt: $e');
        }

        // Don't retry on certain errors
        if (e.toString().contains('Failed host lookup') ||
            e.toString().contains('No route to host')) {
          return BatchUploadResult(
            success: false,
            error: 'Network unavailable: $e',
            attemptCount: attempt,
          );
        }
      }

      // Wait before retry (exponential backoff)
      if (attempt < AvtApiConfig.maxRetries) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    return BatchUploadResult(
      success: false,
      error: 'Failed after ${AvtApiConfig.maxRetries} attempts',
      attemptCount: AvtApiConfig.maxRetries,
    );
  }

  /// Test connection to AVT service
  Future<bool> testConnection() async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$_baseUrl/api/telemetry'))
          .timeout(const Duration(seconds: 5));

      // We expect 405 Method Not Allowed since GET is not supported
      // This still confirms the endpoint exists
      return response.statusCode == 405 || response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('[AvtApiClient] Connection test failed: $e');
      }
      return false;
    }
  }

  /// Dispose of resources
  void dispose() {
    _httpClient.close();
  }
}
