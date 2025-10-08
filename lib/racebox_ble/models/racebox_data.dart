import 'gps_data.dart';
import 'motion_data.dart';

/// Complete telemetry data from a Racebox device
class RaceboxData {
  /// GPS time of week in milliseconds
  final int iTOW;

  /// UTC timestamp
  final DateTime timestamp;

  /// GPS data
  final GpsData gps;

  /// Motion data
  final MotionData motion;

  /// Battery level (0-100%) or input voltage for Micro (in volts)
  final double battery;

  /// Whether device is charging (Mini/Mini S only)
  final bool isCharging;

  /// Time accuracy in nanoseconds
  final int timeAccuracy;

  /// Validity flags
  final int validityFlags;

  /// Whether date is valid
  bool get isDateValid => (validityFlags & 0x01) != 0;

  /// Whether time is valid
  bool get isTimeValid => (validityFlags & 0x02) != 0;

  /// Whether time is fully resolved
  bool get isTimeFullyResolved => (validityFlags & 0x04) != 0;

  const RaceboxData({
    required this.iTOW,
    required this.timestamp,
    required this.gps,
    required this.motion,
    required this.battery,
    required this.isCharging,
    required this.timeAccuracy,
    required this.validityFlags,
  });

  @override
  String toString() {
    return 'RaceboxData(timestamp: $timestamp, '
        'gps: $gps, '
        'motion: $motion, '
        'battery: ${battery.toStringAsFixed(1)}${isCharging ? " (charging)" : ""})';
  }
}
