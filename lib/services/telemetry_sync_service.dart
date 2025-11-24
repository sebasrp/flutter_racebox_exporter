import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../database/telemetry_database.dart';
import 'avt_api_client.dart';

/// Service for syncing telemetry data to AVT backend
class TelemetrySyncService extends ChangeNotifier {
  final TelemetryDatabase _database;
  final AvtApiClient _apiClient;
  final Connectivity _connectivity = Connectivity();

  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isSyncing = false;
  DateTime? _lastSyncAttempt;
  DateTime? _lastSuccessfulSync;
  String? _lastSyncError;
  int _pendingCount = 0;
  String? _currentSessionId;
  String? _deviceId;

  // Configuration
  static const Duration syncInterval = Duration(seconds: 30);
  static const int batchSize = 100;

  TelemetrySyncService({
    required TelemetryDatabase database,
    required AvtApiClient apiClient,
  }) : _database = database,
       _apiClient = apiClient {
    _initializeService();
  }

  // Getters
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncAttempt => _lastSyncAttempt;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;
  String? get lastSyncError => _lastSyncError;
  int get pendingCount => _pendingCount;
  String? get currentSessionId => _currentSessionId;
  String? get deviceId => _deviceId;
  String get baseUrl => _apiClient.baseUrl;

  /// Initialize the sync service
  void _initializeService() {
    // Generate session ID for this app session
    _currentSessionId = const Uuid().v4();

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        // Network is available, trigger sync
        syncNow();
      }
    });

    // Load initial stats (deferred to avoid initialization issues)
    Future.microtask(() => _loadSyncStats());

    // Start periodic sync
    _startPeriodicSync();
  }

  /// Set device ID
  void setDeviceId(String? id) {
    _deviceId = id;
    notifyListeners();
  }

  /// Start a new session
  void startNewSession() {
    _currentSessionId = const Uuid().v4();
    notifyListeners();
  }

  /// Load sync statistics from database
  Future<void> _loadSyncStats() async {
    try {
      final stats = await _database.getSyncStats();
      _pendingCount = stats['pending_count'] as int;
      _lastSuccessfulSync = stats['last_sync'] as DateTime?;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('[TelemetrySyncService] Error loading stats: $e');
      }
    }
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncInterval, (_) {
      syncNow();
    });
  }

  /// Stop periodic sync
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Resume periodic sync
  void resumePeriodicSync() {
    if (_syncTimer == null) {
      _startPeriodicSync();
    }
  }

  /// Trigger sync now
  Future<void> syncNow() async {
    if (_isSyncing) {
      if (kDebugMode) {
        print('[TelemetrySyncService] Sync already in progress');
      }
      return;
    }

    // Check network connectivity
    final connectivityResults = await _connectivity.checkConnectivity();
    if (connectivityResults.contains(ConnectivityResult.none) ||
        connectivityResults.isEmpty) {
      if (kDebugMode) {
        print('[TelemetrySyncService] No network connection');
      }
      _lastSyncError = 'No network connection';
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _lastSyncAttempt = DateTime.now();
    _lastSyncError = null;
    notifyListeners();

    try {
      // Get pending records
      final pendingRecords = await _database.getPendingTelemetry(
        limit: batchSize,
      );

      if (pendingRecords.isEmpty) {
        if (kDebugMode) {
          print('[TelemetrySyncService] No pending records to sync');
        }
        _pendingCount = 0;
        _isSyncing = false;
        notifyListeners();
        return;
      }

      if (kDebugMode) {
        print(
          '[TelemetrySyncService] Syncing ${pendingRecords.length} records',
        );
      }

      // Send batch to API
      final result = await _apiClient.sendBatch(
        pendingRecords,
        deviceId: _deviceId,
        sessionId: _currentSessionId,
      );

      if (result.success && result.savedIds.isNotEmpty) {
        // Extract local IDs from the records
        final localIds = pendingRecords
            .map((record) => record['local_id'] as String)
            .toList();

        // Mark records as synced
        final updatedCount = await _database.markAsSynced(
          localIds.take(result.savedIds.length).toList(),
          result.savedIds,
        );

        if (kDebugMode) {
          print(
            '[TelemetrySyncService] Marked $updatedCount records as synced',
          );
        }

        _lastSuccessfulSync = DateTime.now();

        // Update pending count
        _pendingCount = await _database.getPendingCount();

        // If there are more pending records, schedule immediate sync
        if (_pendingCount > 0) {
          Future.delayed(const Duration(seconds: 1), () {
            syncNow();
          });
        }
      } else {
        _lastSyncError = result.error ?? 'Unknown error';
        if (kDebugMode) {
          print('[TelemetrySyncService] Sync failed: $_lastSyncError');
        }
      }
    } catch (e) {
      _lastSyncError = e.toString();
      if (kDebugMode) {
        print('[TelemetrySyncService] Sync error: $e');
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Update pending count
  Future<void> updatePendingCount() async {
    _pendingCount = await _database.getPendingCount();
    notifyListeners();
  }

  /// Clean up old synced records
  Future<int> cleanupOldRecords({int days = 7}) async {
    try {
      final deletedCount = await _database.deleteSyncedOlderThan(days);
      if (kDebugMode) {
        print('[TelemetrySyncService] Deleted $deletedCount old records');
      }
      return deletedCount;
    } catch (e) {
      if (kDebugMode) {
        print('[TelemetrySyncService] Cleanup error: $e');
      }
      return 0;
    }
  }

  /// Test API connection
  Future<bool> testConnection() async {
    try {
      return await _apiClient.testConnection();
    } catch (e) {
      if (kDebugMode) {
        print('[TelemetrySyncService] Connection test error: $e');
      }
      return false;
    }
  }

  /// Update API base URL
  Future<void> updateApiUrl(String url) async {
    await _apiClient.setBaseUrl(url);
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _apiClient.dispose();
    super.dispose();
  }
}
