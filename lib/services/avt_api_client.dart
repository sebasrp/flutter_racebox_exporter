import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import 'package:archive/archive.dart';

/// Configuration for AVT API
class AvtApiConfig {
  static const String urlKey = 'avt_service_url';

  /// Get the default AVT service URL based on platform
  /// Android emulators use 10.0.2.2 to access host machine
  /// Web and other platforms use localhost
  static String get defaultUrl {
    // Web platform always uses localhost
    if (kIsWeb) {
      return 'http://localhost:8080';
    }
    // Android emulators need special IP to reach host
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8080';
      }
    } catch (_) {
      // Platform check failed (shouldn't happen but handle gracefully)
    }
    // Default for iOS and other platforms
    return 'http://localhost:8080';
  }

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

/// Client for communicating with AVT service with gzip compression support
class AvtApiClient {
  final http.Client _httpClient;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();
  String _baseUrl = AvtApiConfig.defaultUrl;

  // Compression statistics
  int _totalUncompressedBytes = 0;
  int _totalCompressedBytes = 0;
  int _compressionCount = 0;

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

  /// Get compression statistics
  Map<String, dynamic> getCompressionStats() {
    final compressionRatio = _totalUncompressedBytes > 0
        ? (1 - (_totalCompressedBytes / _totalUncompressedBytes)) * 100
        : 0.0;

    return {
      'total_uncompressed_bytes': _totalUncompressedBytes,
      'total_compressed_bytes': _totalCompressedBytes,
      'compression_count': _compressionCount,
      'compression_ratio_percent': compressionRatio.toStringAsFixed(1),
      'bandwidth_saved_bytes': _totalUncompressedBytes - _totalCompressedBytes,
    };
  }

  /// Reset compression statistics
  void resetCompressionStats() {
    _totalUncompressedBytes = 0;
    _totalCompressedBytes = 0;
    _compressionCount = 0;
  }

  /// Send batch of telemetry data to AVT service
  Future<BatchUploadResult> sendBatch(
    List<Map<String, dynamic>> telemetryBatch, {
    String? deviceId,
    String? sessionId,
    String? batchId,
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
        // Generate unique request ID for tracking
        final requestId = _uuid.v4();

        // Serialize to JSON
        final jsonBody = jsonEncode(apiData);
        final uncompressedBytes = utf8.encode(jsonBody);
        final uncompressedSize = uncompressedBytes.length;

        // Compress with gzip using archive package (works on all platforms including web)
        final compressedBytes = GZipEncoder().encode(uncompressedBytes);
        final compressedSize = compressedBytes?.length ?? uncompressedSize;

        // Use compressed data if compression was successful
        final bodyBytes = compressedBytes ?? uncompressedBytes;
        final useCompression = compressedBytes != null;

        // Update compression statistics
        if (useCompression) {
          _totalUncompressedBytes += uncompressedSize;
          _totalCompressedBytes += compressedSize;
          _compressionCount++;
        }

        final compressionRatio = useCompression
            ? ((1 - (compressedSize / uncompressedSize)) * 100).toStringAsFixed(
                1,
              )
            : '0.0';

        final headers = {
          'Content-Type': 'application/json',
          'X-Request-ID': requestId,
        };

        // Add Content-Encoding header if compression was used
        if (useCompression) {
          headers['Content-Encoding'] = 'gzip';
        }

        _logger.d(
          'Uploading ${apiData.length} records: '
          'uncompressed=${uncompressedSize}B, '
          'compressed=${compressedSize}B, '
          'ratio=$compressionRatio%, '
          'requestId=$requestId',
        );

        if (kDebugMode && apiData.isNotEmpty) {
          print(
            '[AvtApiClient] First record timestamp: ${apiData.first['timestamp']}',
          );
        }

        // Add batch ID header for server-side idempotency if provided
        if (batchId != null) {
          headers['X-Batch-ID'] = batchId;
        }

        final response = await _httpClient
            .post(
              Uri.parse('$_baseUrl/api/telemetry/batch'),
              headers: headers,
              body: bodyBytes,
            )
            .timeout(AvtApiConfig.timeout);

        if (response.statusCode == 201 || response.statusCode == 200) {
          final responseData = jsonDecode(response.body);

          // Check if this was a duplicate batch (idempotency)
          final isDuplicate =
              responseData['message']?.toString().contains(
                'already processed',
              ) ??
              false;

          final ids =
              (responseData['ids'] as List<dynamic>?)
                  ?.map((id) => id as int)
                  .toList() ??
              [];

          if (isDuplicate) {
            _logger.i(
              'Batch already processed on server (batchId: $batchId, requestId=$requestId)',
            );
          } else {
            _logger.i(
              'Successfully uploaded ${ids.length} records '
              '(attempt $attempt, requestId=$requestId, compression=$compressionRatio%)',
            );
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
          _logger.w(
            'Upload failed (attempt $attempt, requestId=$requestId): $error',
          );

          if (kDebugMode) {
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
        _logger.w('Request timeout on attempt $attempt');
      } catch (e) {
        _logger.e('Error on attempt $attempt: $e');

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
      final url = '$_baseUrl/api/v1/health';
      if (kDebugMode) {
        print('[AvtApiClient] Testing connection to: $url');
      }

      final response = await _httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (kDebugMode) {
        print('[AvtApiClient] Response status: ${response.statusCode}');
        print('[AvtApiClient] Response body: ${response.body}');
      }

      // Health endpoint should return 200 OK
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('[AvtApiClient] Connection test failed: $e');
        print('[AvtApiClient] Base URL: $_baseUrl');
      }
      return false;
    }
  }

  /// Dispose of resources
  void dispose() {
    _httpClient.close();
  }
}
