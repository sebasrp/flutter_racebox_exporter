import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Device source (Bluetooth or Simulator)
enum DeviceSource { bluetooth, simulator }

/// Represents a discovered Racebox device
class RaceboxDevice {
  /// The underlying BLE device (null for simulator devices)
  final BluetoothDevice? device;

  /// Device name
  final String name;

  /// Device type (Mini, Mini S, or Micro)
  final RaceboxDeviceType type;

  /// Signal strength (RSSI)
  final int rssi;

  /// Device source (bluetooth or simulator)
  final DeviceSource source;

  /// Simulator device ID (null for Bluetooth devices)
  final String? simulatorId;

  RaceboxDevice({
    this.device,
    required this.name,
    required this.type,
    required this.rssi,
    this.source = DeviceSource.bluetooth,
    this.simulatorId,
  });

  /// Parse device type from name
  static RaceboxDeviceType? parseDeviceType(String name) {
    if (name.startsWith('RaceBox Mini S')) {
      return RaceboxDeviceType.miniS;
    } else if (name.startsWith('RaceBox Mini')) {
      return RaceboxDeviceType.mini;
    } else if (name.startsWith('RaceBox Micro')) {
      return RaceboxDeviceType.micro;
    }
    return null;
  }

  /// Create from scan result
  static RaceboxDevice? fromScanResult(ScanResult result) {
    final name = result.device.platformName;
    final type = parseDeviceType(name);

    if (type == null) {
      return null;
    }

    return RaceboxDevice(
      device: result.device,
      name: name,
      type: type,
      rssi: result.rssi,
    );
  }

  @override
  String toString() {
    return 'RaceboxDevice($name, ${type.name}, RSSI: $rssi)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RaceboxDevice) return false;

    // For Bluetooth devices, compare by remoteId
    if (source == DeviceSource.bluetooth &&
        other.source == DeviceSource.bluetooth) {
      return device != null &&
          other.device != null &&
          other.device!.remoteId == device!.remoteId;
    }

    // For simulator devices, compare by simulatorId
    if (source == DeviceSource.simulator &&
        other.source == DeviceSource.simulator) {
      return simulatorId == other.simulatorId;
    }

    return false;
  }

  @override
  int get hashCode {
    if (source == DeviceSource.bluetooth && device != null) {
      return device!.remoteId.hashCode;
    }
    if (source == DeviceSource.simulator && simulatorId != null) {
      return simulatorId.hashCode;
    }
    return name.hashCode;
  }
}

/// Racebox device types
enum RaceboxDeviceType { mini, miniS, micro }
