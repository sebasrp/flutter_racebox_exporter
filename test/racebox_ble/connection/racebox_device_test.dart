import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/racebox_ble/connection/racebox_device.dart';

void main() {
  group('RaceboxDevice', () {
    test('parseDeviceType detects Mini correctly', () {
      final type = RaceboxDevice.parseDeviceType('RaceBox Mini 1234567890');
      expect(type, RaceboxDeviceType.mini);
    });

    test('parseDeviceType detects Mini S correctly', () {
      final type = RaceboxDevice.parseDeviceType('RaceBox Mini S 1234567890');
      expect(type, RaceboxDeviceType.miniS);
    });

    test('parseDeviceType detects Micro correctly', () {
      final type = RaceboxDevice.parseDeviceType('RaceBox Micro 1234567890');
      expect(type, RaceboxDeviceType.micro);
    });

    test('parseDeviceType returns null for invalid name', () {
      final type = RaceboxDevice.parseDeviceType('Some Other Device');
      expect(type, isNull);
    });

    test('parseDeviceType returns null for empty string', () {
      final type = RaceboxDevice.parseDeviceType('');
      expect(type, isNull);
    });

    test('parseDeviceType handles case-sensitive names', () {
      // Should not match if case is different
      final type = RaceboxDevice.parseDeviceType('racebox mini 1234');
      expect(type, isNull);
    });

    test('parseDeviceType handles Mini S before Mini', () {
      // Important: Mini S should be detected before Mini
      // because "RaceBox Mini S" starts with "RaceBox Mini"
      final type = RaceboxDevice.parseDeviceType('RaceBox Mini S 1234567890');
      expect(type, RaceboxDeviceType.miniS);
      expect(type, isNot(RaceboxDeviceType.mini));
    });

    test('parseDeviceType requires exact prefix match', () {
      final type1 = RaceboxDevice.parseDeviceType('XRaceBox Mini 1234');
      final type2 = RaceboxDevice.parseDeviceType('RaceBoxMini1234');

      expect(type1, isNull);
      expect(type2, isNull);
    });

    test('device type enum has all expected values', () {
      expect(RaceboxDeviceType.values.length, 3);
      expect(RaceboxDeviceType.values, contains(RaceboxDeviceType.mini));
      expect(RaceboxDeviceType.values, contains(RaceboxDeviceType.miniS));
      expect(RaceboxDeviceType.values, contains(RaceboxDeviceType.micro));
    });

    test('device type enum has correct names', () {
      expect(RaceboxDeviceType.mini.name, 'mini');
      expect(RaceboxDeviceType.miniS.name, 'miniS');
      expect(RaceboxDeviceType.micro.name, 'micro');
    });
  });
}
