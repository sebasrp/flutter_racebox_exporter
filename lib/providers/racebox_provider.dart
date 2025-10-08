import 'package:flutter/foundation.dart';
import '../racebox_ble/racebox_service.dart';
import '../racebox_ble/models/racebox_data.dart';
import '../racebox_ble/connection/racebox_device.dart';
import '../racebox_ble/connection/ble_manager.dart';

/// Provider for managing Racebox service state
class RaceboxProvider extends ChangeNotifier {
  final RaceboxService _service = RaceboxService();

  List<RaceboxDevice> _devices = [];
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  RaceboxData? _latestData;
  String? _error;
  bool _isScanning = false;

  RaceboxProvider() {
    // Listen to service streams
    _service.devicesStream.listen((devices) {
      _devices = devices;
      notifyListeners();
    });

    _service.connectionStateStream.listen((state) {
      _connectionState = state;
      notifyListeners();
    });

    _service.dataStream.listen((data) {
      _latestData = data;
      notifyListeners();
    });

    _service.errorStream.listen((error) {
      _error = error;
      notifyListeners();
    });
  }

  /// List of discovered devices
  List<RaceboxDevice> get devices => _devices;

  /// Connection state
  BleConnectionState get connectionState => _connectionState;

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

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
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
      await _service.startScan();
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
    super.dispose();
  }
}
