import 'dart:async';
import 'package:flutter/foundation.dart';
import 'telemetry_storage.dart';
import '../buffer/telemetry_ring_buffer.dart';
import '../racebox_ble/models/racebox_data.dart';
import '../racebox_ble/models/gps_data.dart';
import '../racebox_ble/models/motion_data.dart';
import '../services/avt_api_client.dart';

/// Web-based implementation of TelemetryStorage using in-memory ring buffer
///
/// This implementation uses TelemetryRingBuffer for temporary storage and
/// sends data directly to the AVT API when the buffer flushes.
///
/// Platform: Web only
///
/// Trade-offs:
/// - No persistence (data only in memory)
/// - Data loss on browser crash (max ~5 seconds worth)
/// - Simpler and more reliable than IndexedDB
/// - Aggressive sync strategy (every 5 seconds or 80% full)
class WebTelemetryStorage implements TelemetryStorage {
  final TelemetryRingBuffer<Map<String, dynamic>> _buffer;
  final AvtApiClient _apiClient;

  // Statistics
  int _totalInserted = 0;
  int _totalSynced = 0;
  int _pendingCount = 0;
  DateTime? _lastSync;
  String? _deviceId;
  String? _sessionId;

  WebTelemetryStorage({
    AvtApiClient? apiClient,
    int bufferCapacity = 125,
    double flushThreshold = 0.8,
  }) : _buffer = TelemetryRingBuffer<Map<String, dynamic>>(
         capacity: bufferCapacity,
         flushThreshold: flushThreshold,
       ),
       _apiClient = apiClient ?? AvtApiClient() {
    // Set up auto-flush callback
    _buffer.onFlush = _handleBufferFlush;

    if (kDebugMode) {
      print('[WebTelemetryStorage] Initialized with capacity: $bufferCapacity');
    }
  }

  /// Handle buffer flush by sending data to API
  Future<void> _handleBufferFlush(List<Map<String, dynamic>> data) async {
    if (data.isEmpty) return;

    try {
      if (kDebugMode) {
        print('[WebTelemetryStorage] Flushing ${data.length} records to API');
      }

      // Send batch to API
      final result = await _apiClient.sendBatch(
        data,
        deviceId: _deviceId,
        sessionId: _sessionId,
      );

      if (result.success) {
        _totalSynced += data.length;
        _lastSync = DateTime.now();
        _pendingCount = _buffer.size;

        if (kDebugMode) {
          print(
            '[WebTelemetryStorage] Successfully synced ${data.length} records',
          );
        }
      } else {
        if (kDebugMode) {
          print('[WebTelemetryStorage] Sync failed: ${result.error}');
        }
        // On failure, data is lost (acceptable for web platform)
        // Alternative: could re-add to buffer, but risks infinite loop
      }
    } catch (e) {
      if (kDebugMode) {
        print('[WebTelemetryStorage] Error during flush: $e');
      }
      // Data is lost on error (acceptable trade-off for simplicity)
    }
  }

  @override
  Future<int> insertTelemetry(
    RaceboxData data, {
    String? deviceId,
    String? sessionId,
    String? localId,
  }) async {
    // Update device/session IDs if provided
    if (deviceId != null) _deviceId = deviceId;
    if (sessionId != null) _sessionId = sessionId;

    // Convert RaceboxData to map format expected by API
    final record = {
      'local_id': localId ?? _generateLocalId(),
      'device_id': deviceId,
      'session_id': sessionId,
      'recorded_at': data.timestamp.millisecondsSinceEpoch,
      'itow': data.iTOW,
      'latitude': data.gps.latitude,
      'longitude': data.gps.longitude,
      'wgs_altitude': data.gps.wgsAltitude,
      'msl_altitude': data.gps.mslAltitude,
      'speed': data.gps.speed,
      'heading': data.gps.heading,
      'num_satellites': data.gps.numSatellites,
      'fix_status': data.gps.fixStatus,
      'horizontal_accuracy': data.gps.horizontalAccuracy,
      'vertical_accuracy': data.gps.verticalAccuracy,
      'speed_accuracy': data.gps.speedAccuracy,
      'heading_accuracy': data.gps.headingAccuracy,
      'pdop': data.gps.pdop,
      'is_fix_valid': data.gps.isFixValid ? 1 : 0,
      'g_force_x': data.motion.gForceX,
      'g_force_y': data.motion.gForceY,
      'g_force_z': data.motion.gForceZ,
      'rotation_x': data.motion.rotationX,
      'rotation_y': data.motion.rotationY,
      'rotation_z': data.motion.rotationZ,
      'battery': data.battery,
      'is_charging': data.isCharging ? 1 : 0,
      'time_accuracy': data.timeAccuracy,
      'validity_flags': data.validityFlags,
      'sync_status': 'pending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };

    // Add to buffer (will auto-flush if threshold reached)
    _buffer.add(record);
    _totalInserted++;
    _pendingCount = _buffer.size;

    return _totalInserted; // Return insertion count as ID
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingTelemetry({
    int limit = 100,
  }) async {
    // Return current buffer contents (up to limit)
    final pending = _buffer.peek(limit);
    return pending;
  }

  @override
  Future<int> getPendingCount() async {
    return _buffer.size;
  }

  @override
  Future<int> markAsSynced(List<String> localIds, List<int> serverIds) async {
    // For web storage, data is removed from buffer on flush
    // This method is called by sync service but is a no-op for web
    // since we handle sync directly in _handleBufferFlush
    return localIds.length;
  }

  @override
  Future<int> deleteSyncedOlderThan(int days) async {
    // No-op for web storage (no persistent storage to clean up)
    return 0;
  }

  @override
  Future<Map<String, dynamic>> getSyncStats() async {
    return {
      'pending_count': _pendingCount,
      'synced_count': _totalSynced,
      'last_sync': _lastSync,
      'total_inserted': _totalInserted,
      'buffer_capacity': _buffer.capacity,
      'buffer_percentage_full': _buffer.percentageFull,
    };
  }

  @override
  RaceboxData rowToRaceboxData(Map<String, dynamic> row) {
    final gps = GpsData(
      latitude: row['latitude'] as double,
      longitude: row['longitude'] as double,
      wgsAltitude: row['wgs_altitude'] as double,
      mslAltitude: row['msl_altitude'] as double,
      speed: row['speed'] as double,
      heading: row['heading'] as double,
      numSatellites: row['num_satellites'] as int,
      fixStatus: row['fix_status'] as int,
      horizontalAccuracy: row['horizontal_accuracy'] as double,
      verticalAccuracy: row['vertical_accuracy'] as double,
      speedAccuracy: row['speed_accuracy'] as double,
      headingAccuracy: row['heading_accuracy'] as double,
      pdop: row['pdop'] as double,
      isFixValid: (row['is_fix_valid'] as int) == 1,
    );

    final motion = MotionData(
      gForceX: row['g_force_x'] as double,
      gForceY: row['g_force_y'] as double,
      gForceZ: row['g_force_z'] as double,
      rotationX: row['rotation_x'] as double,
      rotationY: row['rotation_y'] as double,
      rotationZ: row['rotation_z'] as double,
    );

    return RaceboxData(
      iTOW: row['itow'] as int,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['recorded_at'] as int),
      gps: gps,
      motion: motion,
      battery: row['battery'] as double,
      isCharging: (row['is_charging'] as int) == 1,
      timeAccuracy: row['time_accuracy'] as int,
      validityFlags: row['validity_flags'] as int,
    );
  }

  @override
  Future<void> close() async {
    // Flush any remaining data before closing
    final remaining = _buffer.flush();
    if (remaining.isNotEmpty) {
      await _handleBufferFlush(remaining);
    }

    _buffer.dispose();
    _apiClient.dispose();

    if (kDebugMode) {
      print(
        '[WebTelemetryStorage] Closed. Total inserted: $_totalInserted, Total synced: $_totalSynced',
      );
    }
  }

  /// Generate unique local ID
  String _generateLocalId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }

  /// Manual flush for testing or immediate sync
  Future<void> flush() async {
    final data = _buffer.flush();
    if (data.isNotEmpty) {
      await _handleBufferFlush(data);
    }
  }

  /// Get buffer statistics
  Map<String, dynamic> getBufferStats() {
    return _buffer.getStats();
  }
}
