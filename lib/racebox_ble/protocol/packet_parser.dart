import 'dart:typed_data';
import '../models/racebox_data.dart';
import '../models/gps_data.dart';
import '../models/motion_data.dart';

/// Parser for Racebox data packets
class PacketParser {
  /// Message class for Racebox data
  static const int raceboxClass = 0xFF;

  /// Message ID for Racebox data
  static const int raceboxDataId = 0x01;

  /// Expected payload size for data message
  static const int dataPayloadSize = 80;

  /// Parse a Racebox data message from payload bytes
  static RaceboxData? parseDataMessage(List<int> payload) {
    if (payload.length != dataPayloadSize) {
      return null;
    }

    final buffer = ByteData.sublistView(Uint8List.fromList(payload));

    try {
      // Parse timestamp
      final iTOW = buffer.getUint32(0, Endian.little);
      final year = buffer.getUint16(4, Endian.little);
      final month = buffer.getUint8(6);
      final day = buffer.getUint8(7);
      final hour = buffer.getUint8(8);
      final minute = buffer.getUint8(9);
      final second = buffer.getUint8(10);

      final timestamp = DateTime.utc(year, month, day, hour, minute, second);

      // Parse validity and status flags
      final validityFlags = buffer.getUint8(11);
      final timeAccuracy = buffer.getUint32(12, Endian.little);
      final fixStatus = buffer.getUint8(20);
      final fixStatusFlags = buffer.getUint8(21);
      final numSatellites = buffer.getUint8(23);

      // Parse GPS data
      final longitude = buffer.getInt32(24, Endian.little) / 1e7;
      final latitude = buffer.getInt32(28, Endian.little) / 1e7;
      final wgsAltitude = buffer.getInt32(32, Endian.little) / 1000.0;
      final mslAltitude = buffer.getInt32(36, Endian.little) / 1000.0;
      final horizontalAccuracy = buffer.getUint32(40, Endian.little) / 1000.0;
      final verticalAccuracy = buffer.getUint32(44, Endian.little) / 1000.0;
      final speedMmPerSec = buffer.getInt32(48, Endian.little);
      final speed = speedMmPerSec / 1000.0 * 3.6; // Convert mm/s to km/h
      final heading = buffer.getInt32(52, Endian.little) / 1e5;
      final speedAccuracyMmPerSec = buffer.getUint32(56, Endian.little);
      final speedAccuracy =
          speedAccuracyMmPerSec / 1000.0 * 3.6; // mm/s to km/h
      final headingAccuracy = buffer.getUint32(60, Endian.little) / 1e5;
      final pdop = buffer.getUint16(64, Endian.little) / 100.0;

      final isFixValid = (fixStatusFlags & 0x01) != 0;

      final gps = GpsData(
        latitude: latitude,
        longitude: longitude,
        wgsAltitude: wgsAltitude,
        mslAltitude: mslAltitude,
        speed: speed,
        heading: heading,
        numSatellites: numSatellites,
        fixStatus: fixStatus,
        horizontalAccuracy: horizontalAccuracy,
        verticalAccuracy: verticalAccuracy,
        speedAccuracy: speedAccuracy,
        headingAccuracy: headingAccuracy,
        pdop: pdop,
        isFixValid: isFixValid,
      );

      // Parse battery status
      final batteryByte = buffer.getUint8(67);
      final isCharging = (batteryByte & 0x80) != 0;
      final battery = (batteryByte & 0x7F).toDouble();

      // Parse motion data
      final gForceX = buffer.getInt16(68, Endian.little) / 1000.0;
      final gForceY = buffer.getInt16(70, Endian.little) / 1000.0;
      final gForceZ = buffer.getInt16(72, Endian.little) / 1000.0;
      final rotationX = buffer.getInt16(74, Endian.little) / 100.0;
      final rotationY = buffer.getInt16(76, Endian.little) / 100.0;
      final rotationZ = buffer.getInt16(78, Endian.little) / 100.0;

      final motion = MotionData(
        gForceX: gForceX,
        gForceY: gForceY,
        gForceZ: gForceZ,
        rotationX: rotationX,
        rotationY: rotationY,
        rotationZ: rotationZ,
      );

      return RaceboxData(
        iTOW: iTOW,
        timestamp: timestamp,
        gps: gps,
        motion: motion,
        battery: battery,
        isCharging: isCharging,
        timeAccuracy: timeAccuracy,
        validityFlags: validityFlags,
      );
    } catch (e) {
      return null;
    }
  }
}
