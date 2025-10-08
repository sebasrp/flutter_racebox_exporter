/// GPS data from the Racebox device
class GpsData {
  /// Latitude in degrees
  final double latitude;

  /// Longitude in degrees
  final double longitude;

  /// WGS altitude in meters
  final double wgsAltitude;

  /// MSL altitude in meters
  final double mslAltitude;

  /// Speed in km/h
  final double speed;

  /// Heading in degrees (0-360, where 0 is North)
  final double heading;

  /// Number of satellites used in solution
  final int numSatellites;

  /// Fix status (0: no fix, 2: 2D fix, 3: 3D fix)
  final int fixStatus;

  /// Horizontal accuracy in meters
  final double horizontalAccuracy;

  /// Vertical accuracy in meters
  final double verticalAccuracy;

  /// Speed accuracy in km/h
  final double speedAccuracy;

  /// Heading accuracy in degrees
  final double headingAccuracy;

  /// PDOP (Position Dilution of Precision)
  final double pdop;

  /// Whether the fix is valid
  final bool isFixValid;

  const GpsData({
    required this.latitude,
    required this.longitude,
    required this.wgsAltitude,
    required this.mslAltitude,
    required this.speed,
    required this.heading,
    required this.numSatellites,
    required this.fixStatus,
    required this.horizontalAccuracy,
    required this.verticalAccuracy,
    required this.speedAccuracy,
    required this.headingAccuracy,
    required this.pdop,
    required this.isFixValid,
  });

  @override
  String toString() {
    return 'GpsData(lat: ${latitude.toStringAsFixed(7)}, '
        'lon: ${longitude.toStringAsFixed(7)}, '
        'alt: ${mslAltitude.toStringAsFixed(1)}m, '
        'speed: ${speed.toStringAsFixed(1)}km/h, '
        'sats: $numSatellites, '
        'fix: ${isFixValid ? "Valid" : "Invalid"})';
  }
}
