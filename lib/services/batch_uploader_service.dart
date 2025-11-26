import 'dart:async';
import 'dart:convert';
import 'package:flutter_racebox_exporter/database/telemetry_queue_database.dart';
import 'package:flutter_racebox_exporter/services/avt_api_client.dart';
import 'package:flutter_racebox_exporter/services/network_monitor.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

/// Result of a batch upload attempt
class UploadResult {
  final bool success;
  final int recordsUploaded;
  final String? error;
  final NetworkQuality networkQuality;
  final int attemptCount;

  UploadResult({
    required this.success,
    required this.recordsUploaded,
    this.error,
    required this.networkQuality,
    required this.attemptCount,
  });
}

/// Service responsible for uploading batched telemetry data
class BatchUploaderService {
  final TelemetryQueueDatabase database;
  final AvtApiClient apiClient;
  final NetworkMonitor networkMonitor;
  final Logger _logger = Logger();
  final Uuid _uuid = const Uuid();

  // Configuration
  static const int maxRetries = 5;

  // Upload state
  bool _isUploading = false;
  Timer? _uploadTimer;
  StreamSubscription? _connectivitySubscription;

  // Statistics
  int _totalUploaded = 0;
  int _totalFailed = 0;
  int _duplicatesDetected = 0;
  int _movedToDeadLetterQueue = 0;
  DateTime? _lastSuccessfulUpload;
  DateTime? _lastFailedUpload;

  BatchUploaderService({
    required this.database,
    required this.apiClient,
    required this.networkMonitor,
  });

  /// Start the automatic upload scheduler
  void startAutoUpload() {
    if (_uploadTimer != null) {
      _logger.w('⚠️ Auto-upload already started');
      return;
    }

    _logger.i('🚀 Starting auto-upload scheduler');

    // Initial upload attempt
    _scheduleNextUpload();

    // Listen for connectivity changes
    _connectivitySubscription = networkMonitor.onConnectivityChanged.listen((
      connectivity,
    ) {
      _logger.d('📡 Connectivity changed: ${connectivity.name}');
      // Trigger an upload check when connectivity changes
      _scheduleNextUpload(immediate: true);
    });
  }

  /// Stop the automatic upload scheduler
  void stopAutoUpload() {
    _logger.i('🛑 Stopping auto-upload scheduler');
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  /// Schedule the next upload based on network quality
  void _scheduleNextUpload({bool immediate = false}) {
    _uploadTimer?.cancel();

    if (immediate) {
      // Upload immediately
      _performUpload();
    } else {
      // Schedule based on network quality
      networkMonitor.getCurrentQuality().then((quality) {
        final interval = networkMonitor.getRecommendedUploadInterval(quality);
        _logger.d(
          '⏰ Scheduling next upload in ${interval.inSeconds}s (quality: ${quality.name})',
        );

        _uploadTimer = Timer(interval, () {
          _performUpload();
        });
      });
    }
  }

  /// Perform a single upload attempt
  Future<UploadResult> _performUpload() async {
    if (_isUploading) {
      _logger.d('Upload already in progress, skipping');
      return UploadResult(
        success: false,
        recordsUploaded: 0,
        error: 'Upload already in progress',
        networkQuality: NetworkQuality.offline,
        attemptCount: 0,
      );
    }

    _isUploading = true;

    try {
      // Check network quality
      final quality = await networkMonitor.getCurrentQuality();

      if (!networkMonitor.canUpload(quality)) {
        _logger.d('📵 Network offline, skipping upload');
        return UploadResult(
          success: false,
          recordsUploaded: 0,
          error: 'Network offline',
          networkQuality: quality,
          attemptCount: 0,
        );
      }

      // Get recommended batch size
      final batchSize = networkMonitor.getRecommendedBatchSize(quality);

      // Fetch unsent records from database
      final records = await database.fetchUnsentRecords(limit: batchSize);

      if (records.isEmpty) {
        _logger.d('✅ No records to upload');
        return UploadResult(
          success: true,
          recordsUploaded: 0,
          networkQuality: quality,
          attemptCount: 0,
        );
      }

      // Generate unique batch ID for idempotency
      final batchId = _uuid.v4();

      // Check if this batch was already processed (idempotency check)
      final alreadyProcessed = await database.isBatchProcessed(batchId);
      if (alreadyProcessed) {
        _logger.w(
          '⚠️ Batch $batchId already processed, skipping (${records.length} records)',
        );
        _duplicatesDetected++;

        // Mark records as uploaded since they were already sent
        final recordIds = records.map((r) => r['id'] as int).toList();
        await database.markAsUploaded(recordIds, batchId);

        return UploadResult(
          success: true,
          recordsUploaded: records.length,
          networkQuality: quality,
          attemptCount: 0,
        );
      }

      _logger.i(
        '📤 Uploading ${records.length} records (batchId: $batchId, quality: ${quality.name})',
      );

      // Convert database records to API format
      // data_json is stored as a JSON string, so we need to parse it
      final batch = records
          .map(
            (record) =>
                jsonDecode(record['data_json'] as String)
                    as Map<String, dynamic>,
          )
          .toList();

      // Upload batch with batch ID for server-side idempotency
      final result = await apiClient.sendBatch(batch, batchId: batchId);

      if (result.success) {
        // Mark records as uploaded
        final recordIds = records.map((r) => r['id'] as int).toList();
        _logger.d(
          '📋 Marking ${recordIds.length} records as uploaded: $recordIds',
        );

        final markedCount = await database.markAsUploaded(recordIds, batchId);
        _logger.i(
          '✅ Marked $markedCount/${recordIds.length} records as uploaded',
        );

        if (markedCount != recordIds.length) {
          _logger.w(
            '⚠️ Expected to mark ${recordIds.length} records but only marked $markedCount',
          );
        }

        // Mark batch as processed for client-side idempotency
        await database.markBatchProcessed(
          batchId,
          records.length,
          serverResponse: 'Success: ${result.savedIds.length} records saved',
        );

        // Update statistics
        _totalUploaded += records.length;
        _lastSuccessfulUpload = DateTime.now();

        // Record upload stats
        await database.recordUploadStats(
          recordsUploaded: records.length,
          batchSize: records.length,
          networkQuality: quality.name,
          success: true,
        );

        _logger.i(
          '✅ Successfully uploaded ${records.length} records (total: $_totalUploaded)',
        );

        return UploadResult(
          success: true,
          recordsUploaded: records.length,
          networkQuality: quality,
          attemptCount: result.attemptCount,
        );
      } else {
        // Upload failed
        _totalFailed += records.length;
        _lastFailedUpload = DateTime.now();

        // Increment retry count for failed records
        final recordIds = records.map((r) => r['id'] as int).toList();
        await database.incrementRetryCount(recordIds);

        // Check for records that exceeded max retries and move to DLQ
        final movedToDlq = await database.moveFailedToDeadLetterQueue(
          maxRetries: maxRetries,
          lastError: result.error,
        );

        if (movedToDlq > 0) {
          _movedToDeadLetterQueue += movedToDlq;
          _logger.w(
            '⚠️ Moved $movedToDlq records to dead letter queue (total: $_movedToDeadLetterQueue)',
          );
        }

        // Record upload stats
        await database.recordUploadStats(
          recordsUploaded: 0,
          batchSize: records.length,
          networkQuality: quality.name,
          success: false,
          errorMessage: result.error,
        );

        _logger.w('❌ Upload failed: ${result.error} (failed: $_totalFailed)');

        return UploadResult(
          success: false,
          recordsUploaded: 0,
          error: result.error,
          networkQuality: quality,
          attemptCount: result.attemptCount,
        );
      }
    } catch (e, stackTrace) {
      _logger.e('💥 Upload error: $e', error: e, stackTrace: stackTrace);
      return UploadResult(
        success: false,
        recordsUploaded: 0,
        error: e.toString(),
        networkQuality: NetworkQuality.offline,
        attemptCount: 0,
      );
    } finally {
      _isUploading = false;
      // Schedule next upload
      _scheduleNextUpload();
    }
  }

  /// Manually trigger an upload
  Future<UploadResult> uploadNow() async {
    _logger.i('🔄 Manual upload triggered');
    return await _performUpload();
  }

  /// Get current upload statistics
  Map<String, dynamic> getStatistics() {
    return {
      'total_uploaded': _totalUploaded,
      'total_failed': _totalFailed,
      'duplicates_detected': _duplicatesDetected,
      'moved_to_dlq': _movedToDeadLetterQueue,
      'last_successful_upload': _lastSuccessfulUpload?.toIso8601String(),
      'last_failed_upload': _lastFailedUpload?.toIso8601String(),
      'is_uploading': _isUploading,
    };
  }

  /// Get queue size (number of unsent records)
  Future<int> getQueueSize() async {
    final stats = await database.getQueueStats();
    return stats['unsent_count'] as int;
  }

  /// Get oldest unsent record timestamp
  Future<DateTime?> getOldestUnsentTimestamp() async {
    final stats = await database.getQueueStats();
    return stats['oldest_unsent'] as DateTime?;
  }

  /// Clean up old uploaded records
  Future<int> cleanupOldRecords({int daysToKeep = 7}) async {
    _logger.i('🧹 Cleaning up records older than $daysToKeep days');
    return await database.deleteUploadedOlderThan(daysToKeep);
  }

  /// Get dead letter queue statistics
  Future<Map<String, dynamic>> getDeadLetterQueueStats() async {
    return await database.getDeadLetterQueueStats();
  }

  /// Get dead letter queue records
  Future<List<Map<String, dynamic>>> getDeadLetterQueueRecords({
    int limit = 100,
    int offset = 0,
  }) async {
    return await database.getDeadLetterQueueRecords(
      limit: limit,
      offset: offset,
    );
  }

  /// Retry a record from the dead letter queue
  Future<bool> retryFromDeadLetterQueue(int dlqId) async {
    return await database.retryFromDeadLetterQueue(dlqId);
  }

  /// Clean up old dead letter queue records
  Future<int> cleanupOldDeadLetterQueue({int daysToKeep = 30}) async {
    _logger.i('🧹 Cleaning up DLQ records older than $daysToKeep days');
    return await database.cleanupOldDeadLetterQueue(daysToKeep);
  }

  /// Purge all dead letter queue records
  Future<int> purgeDeadLetterQueue() async {
    _logger.w('⚠️ Purging all dead letter queue records');
    return await database.purgeDeadLetterQueue();
  }

  /// Dispose resources
  void dispose() {
    stopAutoUpload();
  }
}
