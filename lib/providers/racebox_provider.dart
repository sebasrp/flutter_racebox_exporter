import 'package:flutter/foundation.dart';
import '../racebox_ble/racebox_service.dart';
import '../racebox_ble/models/racebox_data.dart';
import '../racebox_ble/connection/racebox_device.dart';
import '../racebox_ble/connection/device_connection_interface.dart';
import '../database/telemetry_database.dart';
import '../services/telemetry_sync_service.dart';
import '../services/avt_api_client.dart';

/// Provider for managing Racebox service state
class RaceboxProvider extends ChangeNotifier {
  final RaceboxService _service = RaceboxService();
  final TelemetryDatabase _database = TelemetryDatabase();
  late final TelemetrySyncService _syncService;

  List<RaceboxDevice> _devices = [];
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  RaceboxData? _latestData;
  String? _error;
  bool _isScanning = false;
  bool _isRecording = false;
  int _recordedCount = 0;

  RaceboxProvider() {
    // Initialize sync service
    _syncService = TelemetrySyncService(
      database: _database,
      apiClient: AvtApiClient(),
    );

    // Listen to sync service changes
    _syncService.addListener(_onSyncServiceChanged);

    // Listen to service streams
    _service.devicesStream.listen((devices) {
      _devices = devices;
      notifyListeners();
    });

    _service.connectionStateStream.listen((state) {
      _connectionState = state;
      if (state == DeviceConnectionState.connected) {
        // Set device ID when connected
        _syncService.setDeviceId(connectedDevice?.name);
      }
      notifyListeners();
    });

    _service.dataStream.listen((data) {
      _latestData = data;

      // Save to database if recording
      if (_isRecording && data.gps.isFixValid) {
        _saveDataToDatabase(data);
      }

      notifyListeners();
    });

    _service.errorStream.listen((error) {
      _error = error;
      notifyListeners();
    });
  }

  void _onSyncServiceChanged() {
    notifyListeners();
  }

  /// List of discovered devices
  List<RaceboxDevice> get devices => _devices;

  /// Connection state
  DeviceConnectionState get connectionState => _connectionState;

  /// Latest telemetry data
  RaceboxData? get latestData => _latestData;

  /// Latest error message
  String? get error => _error;

  /// Whether currently scanning
  bool get isScanning => _isScanning;

  /// Whether connected to a device
  bool get isConnected => _service.isConnected;

  /// Currently connected device
  RaceboxDevice? get connectedDevice => _service.connectedDevice;

  /// Whether currently recording data
  bool get isRecording => _isRecording;

  /// Number of recorded data points in current session
  int get recordedCount => _recordedCount;

  /// Sync service for monitoring sync status
  TelemetrySyncService get syncService => _syncService;

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Start recording telemetry data
  void startRecording() {
    _isRecording = true;
    _recordedCount = 0;
    _syncService.startNewSession();
    notifyListeners();
  }

  /// Stop recording telemetry data
  void stopRecording() {
    _isRecording = false;
    notifyListeners();
  }

  /// Save data to database
  Future<void> _saveDataToDatabase(RaceboxData data) async {
    try {
      await _database.insertTelemetry(
        data,
        deviceId: connectedDevice?.name,
        sessionId: _syncService.currentSessionId,
      );
      _recordedCount++;

      // Update sync service pending count
      await _syncService.updatePendingCount();
    } catch (e) {
      if (kDebugMode) {
        print('[RaceboxProvider] Error saving data: $e');
      }
    }
  }

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    return await _service.requestPermissions();
  }

  /// Start scanning for devices
  Future<void> startScan() async {
    _isScanning = true;
    notifyListeners();

    try {
      if (kDebugMode) {
        print('[RaceboxProvider] Starting scan...');
      }
      await _service.startScan();
      if (kDebugMode) {
        print('[RaceboxProvider] Scan completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[RaceboxProvider] Scan error: $e');
      }
      _error = 'Scan failed: $e';
      notifyListeners();
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await _service.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  /// Connect to a device
  Future<void> connect(RaceboxDevice device) async {
    await _service.connect(device);
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    await _service.disconnect();
    _latestData = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    _syncService.removeListener(_onSyncServiceChanged);
    _syncService.dispose();
    _database.close();
    super.dispose();
  }
}
