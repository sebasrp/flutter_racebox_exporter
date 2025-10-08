import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/gps_data.dart';

void main() {
  group('GpsData', () {
    test('constructor creates instance with all fields', () {
      final gps = GpsData(
        latitude: 42.6719035,
        longitude: 23.2887238,
        wgsAltitude: 625.761,
        mslAltitude: 590.095,
        speed: 36.0,
        heading: 180.5,
        numSatellites: 11,
        fixStatus: 3,
        horizontalAccuracy: 0.924,
        verticalAccuracy: 1.836,
        speedAccuracy: 0.704,
        headingAccuracy: 145.26856,
        pdop: 3.0,
        isFixValid: true,
      );

      expect(gps.latitude, 42.6719035);
      expect(gps.longitude, 23.2887238);
      expect(gps.wgsAltitude, 625.761);
      expect(gps.mslAltitude, 590.095);
      expect(gps.speed, 36.0);
      expect(gps.heading, 180.5);
      expect(gps.numSatellites, 11);
      expect(gps.fixStatus, 3);
      expect(gps.horizontalAccuracy, 0.924);
      expect(gps.verticalAccuracy, 1.836);
      expect(gps.speedAccuracy, 0.704);
      expect(gps.headingAccuracy, 145.26856);
      expect(gps.pdop, 3.0);
      expect(gps.isFixValid, true);
    });

    test('toString formats GPS data correctly', () {
      final gps = GpsData(
        latitude: 42.6719035,
        longitude: 23.2887238,
        wgsAltitude: 625.761,
        mslAltitude: 590.095,
        speed: 36.0,
        heading: 180.5,
        numSatellites: 11,
        fixStatus: 3,
        horizontalAccuracy: 0.924,
        verticalAccuracy: 1.836,
        speedAccuracy: 0.704,
        headingAccuracy: 145.26856,
        pdop: 3.0,
        isFixValid: true,
      );

      final str = gps.toString();

      expect(str, contains('42.6719035'));
      expect(str, contains('23.2887238'));
      expect(str, contains('590.1')); // MSL altitude
      expect(str, contains('36.0')); // Speed
      expect(str, contains('11')); // Satellites
      expect(str, contains('Valid')); // Fix status
    });

    test('handles zero values', () {
      final gps = GpsData(
        latitude: 0.0,
        longitude: 0.0,
        wgsAltitude: 0.0,
        mslAltitude: 0.0,
        speed: 0.0,
        heading: 0.0,
        numSatellites: 0,
        fixStatus: 0,
        horizontalAccuracy: 0.0,
        verticalAccuracy: 0.0,
        speedAccuracy: 0.0,
        headingAccuracy: 0.0,
        pdop: 0.0,
        isFixValid: false,
      );

      expect(gps.latitude, 0.0);
      expect(gps.speed, 0.0);
      expect(gps.numSatellites, 0);
      expect(gps.isFixValid, false);
    });

    test('handles negative coordinates', () {
      final gps = GpsData(
        latitude: -33.8688,
        longitude: -151.2093,
        wgsAltitude: 100.0,
        mslAltitude: 50.0,
        speed: 10.0,
        heading: 90.0,
        numSatellites: 8,
        fixStatus: 3,
        horizontalAccuracy: 1.0,
        verticalAccuracy: 2.0,
        speedAccuracy: 0.5,
        headingAccuracy: 10.0,
        pdop: 2.0,
        isFixValid: true,
      );

      expect(gps.latitude, -33.8688);
      expect(gps.longitude, -151.2093);
    });

    test('handles high speed values', () {
      final gps = GpsData(
        latitude: 0.0,
        longitude: 0.0,
        wgsAltitude: 0.0,
        mslAltitude: 0.0,
        speed: 350.0, // 350 km/h
        heading: 0.0,
        numSatellites: 10,
        fixStatus: 3,
        horizontalAccuracy: 1.0,
        verticalAccuracy: 1.0,
        speedAccuracy: 1.0,
        headingAccuracy: 1.0,
        pdop: 1.0,
        isFixValid: true,
      );

      expect(gps.speed, 350.0);
    });

    test('handles all heading values (0-360)', () {
      for (final heading in [0.0, 90.0, 180.0, 270.0, 359.9]) {
        final gps = GpsData(
          latitude: 0.0,
          longitude: 0.0,
          wgsAltitude: 0.0,
          mslAltitude: 0.0,
          speed: 0.0,
          heading: heading,
          numSatellites: 0,
          fixStatus: 0,
          horizontalAccuracy: 0.0,
          verticalAccuracy: 0.0,
          speedAccuracy: 0.0,
          headingAccuracy: 0.0,
          pdop: 0.0,
          isFixValid: false,
        );

        expect(gps.heading, heading);
      }
    });

    test('handles different fix statuses', () {
      for (final status in [0, 2, 3]) {
        final gps = GpsData(
          latitude: 0.0,
          longitude: 0.0,
          wgsAltitude: 0.0,
          mslAltitude: 0.0,
          speed: 0.0,
          heading: 0.0,
          numSatellites: 0,
          fixStatus: status,
          horizontalAccuracy: 0.0,
          verticalAccuracy: 0.0,
          speedAccuracy: 0.0,
          headingAccuracy: 0.0,
          pdop: 0.0,
          isFixValid: status == 3,
        );

        expect(gps.fixStatus, status);
      }
    });
  });
}
