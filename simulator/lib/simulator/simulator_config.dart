import 'package:args/args.dart';

enum SimulatorMode { static, moving }

enum RouteType { circular, straight }

enum DeviceType { mini, miniS, micro }

class SimulatorConfig {
  final String deviceName;
  final DeviceType deviceType;
  final SimulatorMode mode;
  final double startLat;
  final double startLon;
  final double speed; // km/h
  final RouteType route;
  final int batteryLevel;
  final int satelliteCount;
  final double altitude;
  final int port;

  const SimulatorConfig({
    required this.deviceName,
    required this.deviceType,
    required this.mode,
    required this.startLat,
    required this.startLon,
    required this.speed,
    required this.route,
    required this.batteryLevel,
    required this.satelliteCount,
    required this.altitude,
    required this.port,
  });

  factory SimulatorConfig.fromArgs(ArgResults results) {
    return SimulatorConfig(
      deviceName: results['name'] as String,
      deviceType: _parseDeviceType(results['type'] as String),
      mode: results['mode'] == 'moving'
          ? SimulatorMode.moving
          : SimulatorMode.static,
      startLat: double.parse(results['lat'] as String),
      startLon: double.parse(results['lon'] as String),
      speed: double.parse(results['speed'] as String),
      route: results['route'] == 'straight'
          ? RouteType.straight
          : RouteType.circular,
      batteryLevel: int.parse(results['battery'] as String),
      satelliteCount: int.parse(results['satellites'] as String? ?? '10'),
      altitude: double.parse(results['altitude'] as String? ?? '50.0'),
      port: int.parse(results['port'] as String),
    );
  }

  static DeviceType _parseDeviceType(String type) {
    switch (type.toLowerCase()) {
      case 'minis':
        return DeviceType.miniS;
      case 'micro':
        return DeviceType.micro;
      default:
        return DeviceType.mini;
    }
  }

  String get deviceTypeString {
    switch (deviceType) {
      case DeviceType.miniS:
        return 'miniS';
      case DeviceType.micro:
        return 'micro';
      default:
        return 'mini';
    }
  }
}
