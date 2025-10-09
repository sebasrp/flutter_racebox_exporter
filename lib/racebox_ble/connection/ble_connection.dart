import '../models/racebox_data.dart';
import 'device_connection_interface.dart';
import 'racebox_device.dart';
import 'ble_manager.dart';

/// Wrapper around BleManager that implements DeviceConnection interface
class BleConnection implements DeviceConnection {
  final BleManager _bleManager = BleManager();

  @override
  Stream<List<RaceboxDevice>> get devicesStream => _bleManager.devicesStream;

  @override
  Stream<DeviceConnectionState> get connectionStateStream =>
      _bleManager.connectionStateStream.map(_mapConnectionState);

  @override
  Stream<RaceboxData> get dataStream => _bleManager.dataStream;

  @override
  Stream<String> get errorStream => _bleManager.errorStream;

  @override
  RaceboxDevice? get connectedDevice => _bleManager.connectedDevice;

  @override
  bool get isConnected => _bleManager.isConnected;

  @override
  Future<void> startScan() => _bleManager.startScan();

  @override
  Future<void> stopScan() => _bleManager.stopScan();

  @override
  Future<void> connect(RaceboxDevice device) => _bleManager.connect(device);

  @override
  Future<void> disconnect() => _bleManager.disconnect();

  @override
  void dispose() => _bleManager.dispose();

  /// Map BleConnectionState to DeviceConnectionState
  DeviceConnectionState _mapConnectionState(BleConnectionState state) {
    switch (state) {
      case BleConnectionState.disconnected:
        return DeviceConnectionState.disconnected;
      case BleConnectionState.connecting:
        return DeviceConnectionState.connecting;
      case BleConnectionState.connected:
        return DeviceConnectionState.connected;
    }
  }
}
