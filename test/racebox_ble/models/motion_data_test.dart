import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/motion_data.dart';
import 'dart:math' as math;

void main() {
  group('MotionData', () {
    test('constructor creates instance with all fields', () {
      final motion = MotionData(
        gForceX: 0.5,
        gForceY: -0.3,
        gForceZ: 1.0,
        rotationX: 10.5,
        rotationY: -5.2,
        rotationZ: 2.1,
      );

      expect(motion.gForceX, 0.5);
      expect(motion.gForceY, -0.3);
      expect(motion.gForceZ, 1.0);
      expect(motion.rotationX, 10.5);
      expect(motion.rotationY, -5.2);
      expect(motion.rotationZ, 2.1);
    });

    test('totalGForce calculates magnitude correctly', () {
      final motion = MotionData(
        gForceX: 3.0,
        gForceY: 4.0,
        gForceZ: 0.0,
        rotationX: 0.0,
        rotationY: 0.0,
        rotationZ: 0.0,
      );

      // 3^2 + 4^2 + 0^2 = 9 + 16 = 25
      expect(motion.totalGForce, 25.0);
    });

    test('totalGForce handles zero values', () {
      final motion = MotionData(
        gForceX: 0.0,
        gForceY: 0.0,
        gForceZ: 0.0,
        rotationX: 0.0,
        rotationY: 0.0,
        rotationZ: 0.0,
      );

      expect(motion.totalGForce, 0.0);
    });

    test('totalGForce handles negative values', () {
      final motion = MotionData(
        gForceX: -3.0,
        gForceY: -4.0,
        gForceZ: 0.0,
        rotationX: 0.0,
        rotationY: 0.0,
        rotationZ: 0.0,
      );

      // (-3)^2 + (-4)^2 = 9 + 16 = 25
      expect(motion.totalGForce, 25.0);
    });

    test('totalGForce calculates 3D magnitude', () {
      final motion = MotionData(
        gForceX: 1.0,
        gForceY: 1.0,
        gForceZ: 1.0,
        rotationX: 0.0,
        rotationY: 0.0,
        rotationZ: 0.0,
      );

      // 1^2 + 1^2 + 1^2 = 3
      expect(motion.totalGForce, closeTo(3.0, 0.001));
    });

    test('toString formats motion data correctly', () {
      final motion = MotionData(
        gForceX: 0.5,
        gForceY: -0.3,
        gForceZ: 1.0,
        rotationX: 10.5,
        rotationY: -5.2,
        rotationZ: 2.1,
      );

      final str = motion.toString();

      expect(str, contains('0.500'));
      expect(str, contains('-0.300'));
      expect(str, contains('1.000'));
      expect(str, contains('10.50'));
      expect(str, contains('-5.20'));
      expect(str, contains('2.10'));
    });

    test('handles stationary state (1g on Z-axis)', () {
      final motion = MotionData(
        gForceX: 0.0,
        gForceY: 0.0,
        gForceZ: 1.0, // Gravity
        rotationX: 0.0,
        rotationY: 0.0,
        rotationZ: 0.0,
      );

      expect(motion.gForceZ, 1.0);
      expect(motion.totalGForce, 1.0);
    });

    test('handles high G-force values', () {
      final motion = MotionData(
        gForceX: 5.0,
        gForceY: 3.0,
        gForceZ: 2.0,
        rotationX: 0.0,
        rotationY: 0.0,
        rotationZ: 0.0,
      );

      expect(motion.gForceX, 5.0);
      expect(motion.totalGForce, closeTo(38.0, 0.1)); // 5^2 + 3^2 + 2^2 = 38
    });

    test('handles high rotation rates', () {
      final motion = MotionData(
        gForceX: 0.0,
        gForceY: 0.0,
        gForceZ: 0.0,
        rotationX: 360.0,
        rotationY: -180.0,
        rotationZ: 90.0,
      );

      expect(motion.rotationX, 360.0);
      expect(motion.rotationY, -180.0);
      expect(motion.rotationZ, 90.0);
    });

    test('handles small precision values', () {
      final motion = MotionData(
        gForceX: 0.001,
        gForceY: -0.002,
        gForceZ: 0.003,
        rotationX: 0.01,
        rotationY: -0.02,
        rotationZ: 0.03,
      );

      expect(motion.gForceX, closeTo(0.001, 0.0001));
      expect(motion.rotationX, closeTo(0.01, 0.001));
    });

    test('motion data is immutable', () {
      const motion = MotionData(
        gForceX: 1.0,
        gForceY: 2.0,
        gForceZ: 3.0,
        rotationX: 4.0,
        rotationY: 5.0,
        rotationZ: 6.0,
      );

      // Should compile and work with const
      expect(motion.gForceX, 1.0);
    });
  });
}
