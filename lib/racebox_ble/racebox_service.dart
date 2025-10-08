import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'models/racebox_data.dart';
import 'connection/ble_manager.dart';
import 'connection/racebox_device.dart';

/// Main service for interacting with Racebox devices
class RaceboxService {
  final BleManager _bleManager = BleManager();

  /// Stream of discovered devices
  Stream<List<RaceboxDevice>> get devicesStream => _bleManager.devicesStream;

  /// Stream of connection state
  Stream<BleConnectionState> get connectionStateStream =>
      _bleManager.connectionStateStream;

  /// Stream of telemetry data
  Stream<RaceboxData> get dataStream => _bleManager.dataStream;

  /// Stream of error messages
  Stream<String> get errorStream => _bleManager.errorStream;

  /// Currently connected device
  RaceboxDevice? get connectedDevice => _bleManager.connectedDevice;

  /// Whether currently connected
  bool get isConnected => _bleManager.isConnected;

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    try {
      // Request Bluetooth permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location, // Required on some Android versions
      ].request();

      // Check if all permissions are granted
      return statuses.values.every((status) => status.isGranted);
    } catch (e) {
      return false;
    }
  }

  /// Start scanning for Racebox devices
  Future<void> startScan() async {
    await _bleManager.startScan();
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await _bleManager.stopScan();
  }

  /// Connect to a device
  Future<void> connect(RaceboxDevice device) async {
    await _bleManager.connect(device);
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    await _bleManager.disconnect();
  }

  /// Dispose resources
  void dispose() {
    _bleManager.dispose();
  }
}
