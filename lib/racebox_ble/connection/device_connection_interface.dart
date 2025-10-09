import '../models/racebox_data.dart';
import 'racebox_device.dart';

enum DeviceConnectionState { disconnected, connecting, connected }

/// Abstract interface for device connections (BLE or HTTP simulator)
abstract class DeviceConnection {
  /// Stream of discovered devices
  Stream<List<RaceboxDevice>> get devicesStream;

  /// Stream of connection state changes
  Stream<DeviceConnectionState> get connectionStateStream;

  /// Stream of parsed data packets
  Stream<RaceboxData> get dataStream;

  /// Stream of error messages
  Stream<String> get errorStream;

  /// Currently connected device
  RaceboxDevice? get connectedDevice;

  /// Whether currently connected to a device
  bool get isConnected;

  /// Start scanning for devices
  Future<void> startScan();

  /// Stop scanning for devices
  Future<void> stopScan();

  /// Connect to a device
  Future<void> connect(RaceboxDevice device);

  /// Disconnect from current device
  Future<void> disconnect();

  /// Dispose resources
  void dispose();
}
