/// Motion data from accelerometer and gyroscope
class MotionData {
  /// G-Force on X axis (front/back) in g
  final double gForceX;

  /// G-Force on Y axis (right/left) in g
  final double gForceY;

  /// G-Force on Z axis (up/down) in g
  final double gForceZ;

  /// Rotation rate on X axis (roll) in degrees per second
  final double rotationX;

  /// Rotation rate on Y axis (pitch) in degrees per second
  final double rotationY;

  /// Rotation rate on Z axis (yaw) in degrees per second
  final double rotationZ;

  const MotionData({
    required this.gForceX,
    required this.gForceY,
    required this.gForceZ,
    required this.rotationX,
    required this.rotationY,
    required this.rotationZ,
  });

  /// Calculate total G-force magnitude
  double get totalGForce {
    return (gForceX * gForceX + gForceY * gForceY + gForceZ * gForceZ).abs();
  }

  @override
  String toString() {
    return 'MotionData(G: [${gForceX.toStringAsFixed(3)}, '
        '${gForceY.toStringAsFixed(3)}, ${gForceZ.toStringAsFixed(3)}], '
        'Rot: [${rotationX.toStringAsFixed(2)}, '
        '${rotationY.toStringAsFixed(2)}, ${rotationZ.toStringAsFixed(2)}])';
  }
}
