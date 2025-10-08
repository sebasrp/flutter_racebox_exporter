import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/racebox_ble/protocol/ubx_packet.dart';

void main() {
  group('UbxPacket', () {
    test('toBytes creates valid packet with correct header', () {
      final packet = UbxPacket(
        messageClass: 0xFF,
        messageId: 0x01,
        payload: [0x01, 0x02, 0x03],
      );

      final bytes = packet.toBytes();

      expect(bytes[0], 0xB5); // Header byte 1
      expect(bytes[1], 0x62); // Header byte 2
      expect(bytes[2], 0xFF); // Message class
      expect(bytes[3], 0x01); // Message ID
      expect(bytes[4], 0x03); // Payload length low byte
      expect(bytes[5], 0x00); // Payload length high byte
    });

    test('toBytes includes payload correctly', () {
      final payload = [0xAA, 0xBB, 0xCC];
      final packet = UbxPacket(
        messageClass: 0xFF,
        messageId: 0x01,
        payload: payload,
      );

      final bytes = packet.toBytes();

      expect(bytes[6], 0xAA);
      expect(bytes[7], 0xBB);
      expect(bytes[8], 0xCC);
    });

    test('toBytes calculates valid checksum', () {
      final packet = UbxPacket(
        messageClass: 0xFF,
        messageId: 0x01,
        payload: [],
      );

      final bytes = packet.toBytes();

      // Verify checksum is at correct position
      expect(
        bytes.length,
        8,
      ); // 2 header + 2 class/id + 2 length + 0 payload + 2 checksum

      // Manual checksum calculation to verify
      int ckA = 0, ckB = 0;
      for (int i = 2; i < 6; i++) {
        ckA = (ckA + bytes[i]) & 0xFF;
        ckB = (ckB + ckA) & 0xFF;
      }

      expect(bytes[6], ckA);
      expect(bytes[7], ckB);
    });

    test('parse returns null for invalid header', () {
      final data = [0x00, 0x00, 0xFF, 0x01, 0x00, 0x00, 0x00, 0x00];
      final packet = UbxPacket.parse(data);

      expect(packet, isNull);
    });

    test('parse returns null for packet too short', () {
      final data = [0xB5, 0x62, 0xFF];
      final packet = UbxPacket.parse(data);

      expect(packet, isNull);
    });

    test('parse returns null for incorrect length', () {
      final data = [
        0xB5, 0x62, // Header
        0xFF, 0x01, // Class/ID
        0x05, 0x00, // Length says 5 bytes
        0x01, 0x02, // But only 2 bytes provided
        0x00, 0x00, // Checksum
      ];
      final packet = UbxPacket.parse(data);

      expect(packet, isNull);
    });

    test('parse successfully parses valid packet', () {
      // Create a valid packet
      final original = UbxPacket(
        messageClass: 0xFF,
        messageId: 0x01,
        payload: [0xAA, 0xBB, 0xCC],
      );
      final bytes = original.toBytes();

      // Parse it back
      final parsed = UbxPacket.parse(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.messageClass, 0xFF);
      expect(parsed.messageId, 0x01);
      expect(parsed.payload, [0xAA, 0xBB, 0xCC]);
    });

    test('parse returns null for invalid checksum', () {
      final data = [
        0xB5, 0x62, // Header
        0xFF, 0x01, // Class/ID
        0x02, 0x00, // Length
        0xAA, 0xBB, // Payload
        0xFF, 0xFF, // Wrong checksum
      ];
      final packet = UbxPacket.parse(data);

      expect(packet, isNull);
    });

    test('parse handles empty payload', () {
      final original = UbxPacket(
        messageClass: 0xFF,
        messageId: 0x02,
        payload: [],
      );
      final bytes = original.toBytes();
      final parsed = UbxPacket.parse(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.payload, isEmpty);
    });

    test('parse handles large payload', () {
      final largePayload = List.generate(504, (i) => i & 0xFF);
      final original = UbxPacket(
        messageClass: 0xFF,
        messageId: 0x03,
        payload: largePayload,
      );
      final bytes = original.toBytes();
      final parsed = UbxPacket.parse(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.payload.length, 504);
      expect(parsed.payload, equals(largePayload));
    });

    test('toString returns formatted string', () {
      final packet = UbxPacket(
        messageClass: 0xFF,
        messageId: 0x01,
        payload: [0x01, 0x02],
      );

      final str = packet.toString();

      expect(str, contains('0xff'));
      expect(str, contains('0x01'));
      expect(str, contains('2 bytes'));
    });

    test('round-trip encoding and parsing preserves data', () {
      final original = UbxPacket(
        messageClass: 0xAB,
        messageId: 0xCD,
        payload: List.generate(80, (i) => i),
      );

      final bytes = original.toBytes();
      final parsed = UbxPacket.parse(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.messageClass, original.messageClass);
      expect(parsed.messageId, original.messageId);
      expect(parsed.payload, equals(original.payload));
    });
  });
}
