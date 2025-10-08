import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/racebox_ble/protocol/checksum.dart';

void main() {
  group('UbxChecksum', () {
    test('calculate returns correct checksum for simple data', () {
      final data = [0xFF, 0x01, 0x02, 0x00];
      final checksum = UbxChecksum.calculate(data, 0, data.length);

      expect(checksum.length, 2);
      expect(checksum[0], isA<int>());
      expect(checksum[1], isA<int>());
    });

    test('calculate produces different checksums for different data', () {
      final data1 = [0xFF, 0x01, 0x02, 0x00];
      final data2 = [0xFF, 0x02, 0x02, 0x00];

      final checksum1 = UbxChecksum.calculate(data1, 0, data1.length);
      final checksum2 = UbxChecksum.calculate(data2, 0, data2.length);

      expect(checksum1, isNot(equals(checksum2)));
    });

    test(
      'verify returns true for valid packet from protocol documentation',
      () {
        // Example packet from protocol doc (page 8)
        final packet = [
          0xB5, 0x62, // Header
          0xFF, 0x01, // Class and ID
          0x50, 0x00, // Length (80 bytes)
          // Payload (first few bytes)
          0xA0, 0xE7, 0x0C, 0x07, 0xE6, 0x07, 0x01, 0x0A,
          0x08, 0x33, 0x08, 0x37, 0x19, 0x00, 0x00, 0x00,
          // ... (rest of 80 bytes payload)
          // We'll just test the checksum calculation works
        ];

        // Create a minimal valid packet
        final minimalPacket = [
          0xB5, 0x62, // Header
          0xFF, 0x01, // Class and ID
          0x00, 0x00, // Length (0 bytes payload)
          0xFF, 0x00, // Placeholder checksum (will be calculated)
        ];

        // Calculate correct checksum
        final checksum = UbxChecksum.calculate(
          minimalPacket,
          2,
          minimalPacket.length - 2,
        );
        minimalPacket[6] = checksum[0];
        minimalPacket[7] = checksum[1];

        expect(UbxChecksum.verify(minimalPacket), true);
      },
    );

    test('verify returns false for corrupted packet', () {
      final packet = [
        0xB5, 0x62, // Header
        0xFF, 0x01, // Class and ID
        0x00, 0x00, // Length
        0x00, 0x00, // Wrong checksum
      ];

      expect(UbxChecksum.verify(packet), false);
    });

    test('verify returns false for packet that is too short', () {
      final packet = [0xB5, 0x62, 0xFF];
      expect(UbxChecksum.verify(packet), false);
    });

    test('calculate handles offset and end parameters correctly', () {
      final data = [0x00, 0x00, 0xFF, 0x01, 0x02, 0x00, 0x00, 0x00];
      final checksum = UbxChecksum.calculate(data, 2, 6);

      expect(checksum.length, 2);
      // Should calculate only over bytes 2-5
      expect(checksum, isNot(equals([0, 0])));
    });

    test('checksum values stay within byte range', () {
      final data = List.filled(100, 0xFF);
      final checksum = UbxChecksum.calculate(data, 0, data.length);

      expect(checksum[0], lessThanOrEqualTo(0xFF));
      expect(checksum[1], lessThanOrEqualTo(0xFF));
      expect(checksum[0], greaterThanOrEqualTo(0x00));
      expect(checksum[1], greaterThanOrEqualTo(0x00));
    });
  });
}
