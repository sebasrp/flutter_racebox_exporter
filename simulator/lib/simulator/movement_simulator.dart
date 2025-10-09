import 'dart:math';
import 'simulator_config.dart';

class Position {
  final double latitude;
  final double longitude;
  final double speed;
  final double heading;
  final double gx;
  final double gy;
  final double gz;
  final double rx;
  final double ry;
  final double rz;

  const Position({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.rx,
    required this.ry,
    required this.rz,
  });
}

class MovementSimulator {
  final SimulatorConfig config;
  final Random _random = Random();

  MovementSimulator({required this.config});

  Position getCurrentPosition(int tick) {
    if (config.mode == SimulatorMode.static) {
      return _staticPosition();
    } else {
      return _movingPosition(tick);
    }
  }

  Position _staticPosition() {
    // Fixed position with small GPS noise (±5 meters)
    final noise = _random.nextDouble() * 0.00005 - 0.000025;
    return Position(
      latitude: config.startLat + noise,
      longitude: config.startLon + noise,
      speed: 0.0,
      heading: 0.0,
      gx: 0.0,
      gy: 0.0,
      gz: 1.0, // Stationary: 1g downward
      rx: 0.0,
      ry: 0.0,
      rz: 0.0,
    );
  }

  Position _movingPosition(int tick) {
    final timeSeconds = tick / 25.0; // 25Hz update rate
    final distanceKm = (config.speed / 3600.0) * timeSeconds;

    if (config.route == RouteType.circular) {
      return _circularRoute(distanceKm, timeSeconds);
    } else {
      return _straightRoute(distanceKm);
    }
  }

  Position _circularRoute(double distanceKm, double timeSeconds) {
    // Move in circle with radius based on speed
    final radius = 0.01; // ~1km radius in degrees
    final angle = (distanceKm / (2 * pi * radius)) * 2 * pi;

    // Calculate lateral G-force based on circular motion
    // centripetal acceleration = v^2 / r
    final speedMs = config.speed / 3.6; // Convert km/h to m/s
    final radiusM = radius * 111000; // Convert degrees to meters (approx)
    final lateralG = (speedMs * speedMs) / (radiusM * 9.81);

    return Position(
      latitude: config.startLat + radius * sin(angle),
      longitude: config.startLon + radius * cos(angle),
      speed: config.speed,
      heading: (angle * 180 / pi) % 360,
      gx: lateralG * cos(angle),
      gy: lateralG * sin(angle),
      gz: 1.0,
      rx: 0.0,
      ry: 0.0,
      rz: (config.speed / 50.0) * 0.5, // Rotation based on speed
    );
  }

  Position _straightRoute(double distanceKm) {
    // Move straight north
    final newLat = config.startLat + (distanceKm / 111.0); // ~111km per degree

    return Position(
      latitude: newLat,
      longitude: config.startLon,
      speed: config.speed,
      heading: 0.0, // North
      gx: 0.0,
      gy: 0.0,
      gz: 1.0,
      rx: 0.0,
      ry: 0.0,
      rz: 0.0,
    );
  }
}
