import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/racebox_data.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/gps_data.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/motion_data.dart';

void main() {
  group('RaceboxData', () {
    final testGps = GpsData(
      latitude: 42.0,
      longitude: 23.0,
      wgsAltitude: 100.0,
      mslAltitude: 90.0,
      speed: 50.0,
      heading: 180.0,
      numSatellites: 10,
      fixStatus: 3,
      horizontalAccuracy: 1.0,
      verticalAccuracy: 2.0,
      speedAccuracy: 0.5,
      headingAccuracy: 10.0,
      pdop: 2.0,
      isFixValid: true,
    );

    final testMotion = MotionData(
      gForceX: 0.5,
      gForceY: -0.3,
      gForceZ: 1.0,
      rotationX: 10.0,
      rotationY: -5.0,
      rotationZ: 2.0,
    );

    test('constructor creates instance with all fields', () {
      final timestamp = DateTime.utc(2024, 1, 1, 12, 0, 0);
      final data = RaceboxData(
        iTOW: 123456789,
        timestamp: timestamp,
        gps: testGps,
        motion: testMotion,
        battery: 85.0,
        isCharging: false,
        timeAccuracy: 1000,
        validityFlags: 0x07,
      );

      expect(data.iTOW, 123456789);
      expect(data.timestamp, timestamp);
      expect(data.gps, testGps);
      expect(data.motion, testMotion);
      expect(data.battery, 85.0);
      expect(data.isCharging, false);
      expect(data.timeAccuracy, 1000);
      expect(data.validityFlags, 0x07);
    });

    test('isDateValid checks bit 0 correctly', () {
      final data1 = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x01, // Bit 0 set
      );

      final data2 = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x00, // Bit 0 not set
      );

      expect(data1.isDateValid, true);
      expect(data2.isDateValid, false);
    });

    test('isTimeValid checks bit 1 correctly', () {
      final data1 = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x02, // Bit 1 set
      );

      final data2 = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x00, // Bit 1 not set
      );

      expect(data1.isTimeValid, true);
      expect(data2.isTimeValid, false);
    });

    test('isTimeFullyResolved checks bit 2 correctly', () {
      final data1 = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x04, // Bit 2 set
      );

      final data2 = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x00, // Bit 2 not set
      );

      expect(data1.isTimeFullyResolved, true);
      expect(data2.isTimeFullyResolved, false);
    });

    test('validity flags can be combined', () {
      final data = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x07, // All three bits set
      );

      expect(data.isDateValid, true);
      expect(data.isTimeValid, true);
      expect(data.isTimeFullyResolved, true);
    });

    test('handles charging status correctly', () {
      final charging = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 50.0,
        isCharging: true,
        timeAccuracy: 0,
        validityFlags: 0x00,
      );

      final notCharging = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 50.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x00,
      );

      expect(charging.isCharging, true);
      expect(notCharging.isCharging, false);
    });

    test('toString includes key information', () {
      final timestamp = DateTime.utc(2024, 1, 1, 12, 0, 0);
      final data = RaceboxData(
        iTOW: 123456,
        timestamp: timestamp,
        gps: testGps,
        motion: testMotion,
        battery: 75.5,
        isCharging: true,
        timeAccuracy: 1000,
        validityFlags: 0x07,
      );

      final str = data.toString();

      expect(str, contains('2024-01-01'));
      expect(str, contains('75.5'));
      expect(str, contains('charging'));
    });

    test('handles different battery levels', () {
      for (final level in [0.0, 25.0, 50.0, 75.0, 100.0]) {
        final data = RaceboxData(
          iTOW: 0,
          timestamp: DateTime.now(),
          gps: testGps,
          motion: testMotion,
          battery: level,
          isCharging: false,
          timeAccuracy: 0,
          validityFlags: 0x00,
        );

        expect(data.battery, level);
      }
    });

    test('racebox data is immutable', () {
      final timestamp = DateTime.utc(2024, 1, 1);
      const validityFlags = 0x07;

      final data = RaceboxData(
        iTOW: 0,
        timestamp: timestamp,
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: validityFlags,
      );

      // Should be able to use const where applicable
      expect(data.validityFlags, 0x07);
    });

    test('handles extreme time accuracy values', () {
      final data = RaceboxData(
        iTOW: 0,
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 999999999,
        validityFlags: 0x00,
      );

      expect(data.timeAccuracy, 999999999);
    });

    test('handles large iTOW values', () {
      final data = RaceboxData(
        iTOW: 604800000, // One week in milliseconds
        timestamp: DateTime.now(),
        gps: testGps,
        motion: testMotion,
        battery: 100.0,
        isCharging: false,
        timeAccuracy: 0,
        validityFlags: 0x00,
      );

      expect(data.iTOW, 604800000);
    });
  });
}
