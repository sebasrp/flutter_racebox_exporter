import '../racebox_ble/models/racebox_data.dart';

/// Abstract interface for telemetry data storage
///
/// This interface provides a platform-agnostic API for storing and retrieving
/// telemetry data. Implementations can use different storage backends:
/// - SQLite for mobile/desktop platforms
/// - In-memory ring buffer for web platform
abstract class TelemetryStorage {
  /// Insert telemetry data into storage
  ///
  /// Parameters:
  /// - [data]: The telemetry data to store
  /// - [deviceId]: Optional device identifier
  /// - [sessionId]: Optional session identifier
  /// - [localId]: Optional local identifier (auto-generated if not provided)
  ///
  /// Returns: The ID of the inserted record (implementation-specific)
  Future<int> insertTelemetry(
    RaceboxData data, {
    String? deviceId,
    String? sessionId,
    String? localId,
  });

  /// Get pending telemetry records that need to be synced
  ///
  /// Parameters:
  /// - [limit]: Maximum number of records to retrieve (default: 100)
  ///
  /// Returns: List of telemetry records as maps
  Future<List<Map<String, dynamic>>> getPendingTelemetry({int limit = 100});

  /// Get count of pending records waiting to be synced
  ///
  /// Returns: Number of pending records
  Future<int> getPendingCount();

  /// Mark records as successfully synced
  ///
  /// Parameters:
  /// - [localIds]: List of local IDs to mark as synced
  /// - [serverIds]: Corresponding server IDs from the API
  ///
  /// Returns: Number of records successfully marked as synced
  Future<int> markAsSynced(List<String> localIds, List<int> serverIds);

  /// Delete synced records older than specified days
  ///
  /// Parameters:
  /// - [days]: Age threshold in days
  ///
  /// Returns: Number of records deleted
  Future<int> deleteSyncedOlderThan(int days);

  /// Get sync statistics
  ///
  /// Returns: Map containing:
  /// - 'pending_count': Number of pending records
  /// - 'synced_count': Number of synced records
  /// - 'last_sync': DateTime of last successful sync (or null)
  Future<Map<String, dynamic>> getSyncStats();

  /// Convert database row to RaceboxData
  ///
  /// This is used by the sync service to reconstruct RaceboxData objects
  /// from stored records.
  ///
  /// Parameters:
  /// - [row]: Database row as a map
  ///
  /// Returns: Reconstructed RaceboxData object
  RaceboxData rowToRaceboxData(Map<String, dynamic> row);

  /// Close storage and cleanup resources
  ///
  /// This should be called when the storage is no longer needed.
  Future<void> close();
}
