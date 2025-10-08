import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Represents a discovered Racebox device
class RaceboxDevice {
  /// The underlying BLE device
  final BluetoothDevice device;

  /// Device name
  final String name;

  /// Device type (Mini, Mini S, or Micro)
  final RaceboxDeviceType type;

  /// Signal strength (RSSI)
  final int rssi;

  RaceboxDevice({
    required this.device,
    required this.name,
    required this.type,
    required this.rssi,
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
    return other is RaceboxDevice && other.device.remoteId == device.remoteId;
  }

  @override
  int get hashCode => device.remoteId.hashCode;
}

/// Racebox device types
enum RaceboxDeviceType { mini, miniS, micro }
