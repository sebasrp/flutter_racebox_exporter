import 'telemetry_storage.dart';
import 'telemetry_database.dart';
import '../racebox_ble/models/racebox_data.dart';

/// SQLite-based implementation of TelemetryStorage
///
/// This implementation wraps the existing TelemetryDatabase and provides
/// the TelemetryStorage interface for mobile and desktop platforms.
///
/// Platforms: Android, iOS, Linux, macOS, Windows
class SqliteTelemetryStorage implements TelemetryStorage {
  final TelemetryDatabase _database;

  SqliteTelemetryStorage() : _database = TelemetryDatabase();

  @override
  Future<int> insertTelemetry(
    RaceboxData data, {
    String? deviceId,
    String? sessionId,
    String? localId,
  }) async {
    return await _database.insertTelemetry(
      data,
      deviceId: deviceId,
      sessionId: sessionId,
      localId: localId,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingTelemetry({
    int limit = 100,
  }) async {
    return await _database.getPendingTelemetry(limit: limit);
  }

  @override
  Future<int> getPendingCount() async {
    return await _database.getPendingCount();
  }

  @override
  Future<int> markAsSynced(List<String> localIds, List<int> serverIds) async {
    return await _database.markAsSynced(localIds, serverIds);
  }

  @override
  Future<int> deleteSyncedOlderThan(int days) async {
    return await _database.deleteSyncedOlderThan(days);
  }

  @override
  Future<Map<String, dynamic>> getSyncStats() async {
    return await _database.getSyncStats();
  }

  @override
  RaceboxData rowToRaceboxData(Map<String, dynamic> row) {
    return _database.rowToRaceboxData(row);
  }

  @override
  Future<void> close() async {
    await _database.close();
  }
}
