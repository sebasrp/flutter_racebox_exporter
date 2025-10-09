import 'dart:typed_data';
import 'movement_simulator.dart';
import 'simulator_config.dart';

class DataGenerator {
  final MovementSimulator movement;
  final SimulatorConfig config;
  int _tickCount = 0;

  DataGenerator({required this.movement, required this.config});

  List<int> generate() {
    _tickCount++;
    final position = movement.getCurrentPosition(_tickCount);

    // Build 80-byte payload
    final payload = ByteData(80);

    // GPS Time and Date (bytes 0-15)
    final now = DateTime.now().toUtc();
    payload.setUint32(0, _calculateITOW(now), Endian.little);
    payload.setUint16(4, now.year, Endian.little);
    payload.setUint8(6, now.month);
    payload.setUint8(7, now.day);
    payload.setUint8(8, now.hour);
    payload.setUint8(9, now.minute);
    payload.setUint8(10, now.second);
    payload.setUint8(11, 0x07); // validityFlags: date, time, and fully resolved
    payload.setUint32(12, 20, Endian.little); // timeAccuracy in nanoseconds

    // GPS Fix Info (bytes 16-23)
    payload.setUint32(16, 0, Endian.little); // nanosecond (reserved)
    payload.setUint8(20, 3); // fixStatus: 3 = 3D fix
    payload.setUint8(21, 1); // fixValid: 1 = valid
    payload.setUint8(22, 0); // reserved
    payload.setUint8(23, config.satelliteCount); // numberOfSatellites

    // GPS Position (bytes 24-47)
    payload.setInt32(24, (position.longitude * 1e7).round(), Endian.little);
    payload.setInt32(28, (position.latitude * 1e7).round(), Endian.little);
    payload.setInt32(
      32,
      (config.altitude * 1000).round(),
      Endian.little,
    ); // wgsAltitude in mm
    payload.setInt32(
      36,
      (config.altitude * 1000).round(),
      Endian.little,
    ); // mslAltitude in mm
    payload.setUint32(40, 1500, Endian.little); // horizontalAccuracy in mm
    payload.setUint32(44, 2000, Endian.little); // verticalAccuracy in mm

    // GPS Velocity (bytes 48-63)
    payload.setInt32(
      48,
      (position.speed * 1000 / 3.6).round(),
      Endian.little,
    ); // speed in mm/s
    payload.setInt32(
      52,
      (position.heading * 1e5).round(),
      Endian.little,
    ); // heading in 1e-5 degrees
    payload.setUint32(56, 500, Endian.little); // speedAccuracy in mm/s
    payload.setUint32(
      60,
      (2.0 * 1e5).round(),
      Endian.little,
    ); // headingAccuracy in 1e-5 degrees
    payload.setUint16(64, 120, Endian.little); // pdop * 100
    payload.setUint8(66, 0); // reserved

    // Battery (byte 67)
    payload.setUint8(67, config.batteryLevel); // batteryStatus (0-100%)

    // Motion Data - Accelerometer (bytes 68-73)
    payload.setInt16(
      68,
      (position.gx * 1000).round(),
      Endian.little,
    ); // gForceX in milli-g
    payload.setInt16(
      70,
      (position.gy * 1000).round(),
      Endian.little,
    ); // gForceY in milli-g
    payload.setInt16(
      72,
      (position.gz * 1000).round(),
      Endian.little,
    ); // gForceZ in milli-g

    // Motion Data - Gyroscope (bytes 74-79)
    payload.setInt16(
      74,
      (position.rx * 100).round(),
      Endian.little,
    ); // rotationX in 0.01 deg/s
    payload.setInt16(
      76,
      (position.ry * 100).round(),
      Endian.little,
    ); // rotationY in 0.01 deg/s
    payload.setInt16(
      78,
      (position.rz * 100).round(),
      Endian.little,
    ); // rotationZ in 0.01 deg/s

    // Build complete UBX packet
    return _buildUbxPacket(payload.buffer.asUint8List());
  }

  int _calculateITOW(DateTime time) {
    // iTOW = milliseconds since start of GPS week
    // For simulation, just use milliseconds since midnight
    final midnight = DateTime(time.year, time.month, time.day);
    final diff = time.difference(midnight);
    return diff.inMilliseconds;
  }

  List<int> _buildUbxPacket(List<int> payload) {
    final packet = <int>[];

    // Header
    packet.add(0xB5);
    packet.add(0x62);

    // Class and ID
    packet.add(0xFF);
    packet.add(0x01);

    // Length
    final length = payload.length;
    packet.add(length & 0xFF);
    packet.add((length >> 8) & 0xFF);

    // Payload
    packet.addAll(payload);

    // Calculate checksum (Fletcher-8 algorithm)
    int ckA = 0;
    int ckB = 0;

    // Checksum is calculated over class, ID, length, and payload
    for (int i = 2; i < packet.length; i++) {
      ckA = (ckA + packet[i]) & 0xFF;
      ckB = (ckB + ckA) & 0xFF;
    }

    packet.add(ckA);
    packet.add(ckB);

    return packet;
  }
}
