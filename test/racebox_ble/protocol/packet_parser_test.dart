import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/racebox_ble/protocol/packet_parser.dart';
import 'package:flutter_racebox_exporter/racebox_ble/models/racebox_data.dart';

void main() {
  group('PacketParser', () {
    test('parseDataMessage returns null for wrong payload size', () {
      final payload = List.filled(50, 0); // Wrong size (should be 80)
      final result = PacketParser.parseDataMessage(payload);

      expect(result, isNull);
    });

    test('parseDataMessage returns null for empty payload', () {
      final result = PacketParser.parseDataMessage([]);

      expect(result, isNull);
    });

    test('parseDataMessage parses valid data from protocol example', () {
      // This is the example from protocol doc page 8 (simplified)
      final buffer = ByteData(80);

      // iTOW
      buffer.setUint32(0, 118286240, Endian.little);

      // Year, Month, Day, Hour, Minute, Second
      buffer.setUint16(4, 2022, Endian.little);
      buffer.setUint8(6, 1); // January
      buffer.setUint8(7, 10);
      buffer.setUint8(8, 8);
      buffer.setUint8(9, 51);
      buffer.setUint8(10, 8);

      // Validity flags (0x37 = 0011 0111 - date, time, and resolved valid)
      buffer.setUint8(11, 0x07);

      // Time accuracy (25ns)
      buffer.setUint32(12, 25, Endian.little);

      // Nanoseconds
      buffer.setInt32(16, 239971626, Endian.little);

      // Fix Status (3 = 3D fix)
      buffer.setUint8(20, 3);

      // Fix Status Flags (0x01 = valid fix)
      buffer.setUint8(21, 0x01);

      // Date/Time Flags
      buffer.setUint8(22, 0xEA);

      // Number of SVs
      buffer.setUint8(23, 11);

      // Longitude (23.2887238 * 1e7)
      buffer.setInt32(24, 232887238, Endian.little);

      // Latitude (42.6719035 * 1e7)
      buffer.setInt32(28, 426719035, Endian.little);

      // WGS Altitude (625.761m in mm)
      buffer.setInt32(32, 625761, Endian.little);

      // MSL Altitude (590.095m in mm)
      buffer.setInt32(36, 590095, Endian.little);

      // Horizontal Accuracy (0.924m in mm)
      buffer.setUint32(40, 924, Endian.little);

      // Vertical Accuracy (1.836m in mm)
      buffer.setUint32(44, 1836, Endian.little);

      // Speed (35 mm/s)
      buffer.setInt32(48, 35, Endian.little);

      // Heading (0 degrees)
      buffer.setInt32(52, 0, Endian.little);

      // Speed Accuracy
      buffer.setUint32(56, 208, Endian.little);

      // Heading Accuracy
      buffer.setUint32(60, 14526856, Endian.little);

      // PDOP (3.0)
      buffer.setUint16(64, 300, Endian.little);

      // Lat/Lon Flags
      buffer.setUint8(66, 0x00);

      // Battery Status (89%, not charging)
      buffer.setUint8(67, 0x59);

      // GForce X (-0.003g = -3 milli-g)
      buffer.setInt16(68, -3, Endian.little);

      // GForce Y (0.113g = 113 milli-g)
      buffer.setInt16(70, 113, Endian.little);

      // GForce Z (0.974g = 974 milli-g)
      buffer.setInt16(72, 974, Endian.little);

      // Rotation X (-2.09 deg/s = -209 centi-deg/s)
      buffer.setInt16(74, -209, Endian.little);

      // Rotation Y (0.86 deg/s = 86 centi-deg/s)
      buffer.setInt16(76, 86, Endian.little);

      // Rotation Z (-0.04 deg/s = -4 centi-deg/s)
      buffer.setInt16(78, -4, Endian.little);

      final payload = buffer.buffer.asUint8List();
      final result = PacketParser.parseDataMessage(payload);

      expect(result, isNotNull);
      expect(result!.iTOW, 118286240);
      expect(result.timestamp.year, 2022);
      expect(result.timestamp.month, 1);
      expect(result.timestamp.day, 10);
      expect(result.gps.latitude, closeTo(42.6719035, 0.0001));
      expect(result.gps.longitude, closeTo(23.2887238, 0.0001));
      expect(result.gps.numSatellites, 11);
      expect(result.gps.fixStatus, 3);
      expect(result.gps.isFixValid, true);
      expect(result.battery, 89.0);
      expect(result.isCharging, false);
    });

    test('parseDataMessage correctly converts speed from mm/s to km/h', () {
      final buffer = ByteData(80);

      // Set speed to 10000 mm/s (36 km/h)
      buffer.setInt32(48, 10000, Endian.little);

      // Fill other required fields with minimal valid data
      buffer.setUint16(4, 2022, Endian.little);
      buffer.setUint8(6, 1);
      buffer.setUint8(7, 1);

      final payload = buffer.buffer.asUint8List();
      final result = PacketParser.parseDataMessage(payload);

      expect(result, isNotNull);
      expect(result!.gps.speed, closeTo(36.0, 0.1)); // 10000 mm/s = 36 km/h
    });

    test('parseDataMessage correctly parses battery charging status', () {
      final buffer = ByteData(80);

      // Battery at 75%, charging (0x80 | 75 = 0xCB)
      buffer.setUint8(67, 0xCB);

      // Fill other required fields
      buffer.setUint16(4, 2022, Endian.little);
      buffer.setUint8(6, 1);
      buffer.setUint8(7, 1);

      final payload = buffer.buffer.asUint8List();
      final result = PacketParser.parseDataMessage(payload);

      expect(result, isNotNull);
      expect(result!.battery, 75.0);
      expect(result.isCharging, true);
    });

    test('parseDataMessage correctly converts G-forces', () {
      final buffer = ByteData(80);

      // Set G-forces: X=1000mg, Y=-500mg, Z=2000mg
      buffer.setInt16(68, 1000, Endian.little);
      buffer.setInt16(70, -500, Endian.little);
      buffer.setInt16(72, 2000, Endian.little);

      // Fill other required fields
      buffer.setUint16(4, 2022, Endian.little);
      buffer.setUint8(6, 1);
      buffer.setUint8(7, 1);

      final payload = buffer.buffer.asUint8List();
      final result = PacketParser.parseDataMessage(payload);

      expect(result, isNotNull);
      expect(result!.motion.gForceX, closeTo(1.0, 0.001));
      expect(result.motion.gForceY, closeTo(-0.5, 0.001));
      expect(result.motion.gForceZ, closeTo(2.0, 0.001));
    });

    test('parseDataMessage correctly converts rotation rates', () {
      final buffer = ByteData(80);

      // Set rotation: X=100 cdeg/s, Y=-200 cdeg/s, Z=50 cdeg/s
      buffer.setInt16(74, 100, Endian.little);
      buffer.setInt16(76, -200, Endian.little);
      buffer.setInt16(78, 50, Endian.little);

      // Fill other required fields
      buffer.setUint16(4, 2022, Endian.little);
      buffer.setUint8(6, 1);
      buffer.setUint8(7, 1);

      final payload = buffer.buffer.asUint8List();
      final result = PacketParser.parseDataMessage(payload);

      expect(result, isNotNull);
      expect(result!.motion.rotationX, closeTo(1.0, 0.01));
      expect(result.motion.rotationY, closeTo(-2.0, 0.01));
      expect(result.motion.rotationZ, closeTo(0.5, 0.01));
    });

    test('parseDataMessage handles negative coordinates', () {
      final buffer = ByteData(80);

      // Set negative coordinates (e.g., Western hemisphere, Southern hemisphere)
      buffer.setInt32(24, -1234567890, Endian.little); // Longitude
      buffer.setInt32(28, -987654321, Endian.little); // Latitude

      // Fill other required fields
      buffer.setUint16(4, 2022, Endian.little);
      buffer.setUint8(6, 1);
      buffer.setUint8(7, 1);

      final payload = buffer.buffer.asUint8List();
      final result = PacketParser.parseDataMessage(payload);

      expect(result, isNotNull);
      expect(result!.gps.longitude, lessThan(0));
      expect(result.gps.latitude, lessThan(0));
    });

    test('parseDataMessage validates message class and ID constants', () {
      expect(PacketParser.raceboxClass, 0xFF);
      expect(PacketParser.raceboxDataId, 0x01);
      expect(PacketParser.dataPayloadSize, 80);
    });

    test('parseDataMessage handles exception during parsing', () {
      // Create malformed data that might cause exception
      final payload = List.filled(80, 0xFF);

      // This should not throw, just return null if parsing fails
      expect(() => PacketParser.parseDataMessage(payload), returnsNormally);
    });
  });
}
