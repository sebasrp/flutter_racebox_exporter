import 'checksum.dart';

/// UBX packet structure
class UbxPacket {
  /// Packet header (always 0xB5 0x62)
  static const int header1 = 0xB5;
  static const int header2 = 0x62;

  /// Message class
  final int messageClass;

  /// Message ID
  final int messageId;

  /// Payload data
  final List<int> payload;

  UbxPacket({
    required this.messageClass,
    required this.messageId,
    required this.payload,
  });

  /// Get the complete packet as bytes (including header and checksum)
  List<int> toBytes() {
    final packet = <int>[
      header1,
      header2,
      messageClass,
      messageId,
      payload.length & 0xFF,
      (payload.length >> 8) & 0xFF,
      ...payload,
    ];

    final checksum = UbxChecksum.calculate(packet, 2, packet.length);
    packet.addAll(checksum);

    return packet;
  }

  /// Parse a UBX packet from bytes
  /// Returns null if packet is invalid
  static UbxPacket? parse(List<int> data) {
    if (data.length < 8) {
      return null; // Too short
    }

    // Verify header
    if (data[0] != header1 || data[1] != header2) {
      return null;
    }

    // Extract message class and ID
    final messageClass = data[2];
    final messageId = data[3];

    // Extract payload length
    final payloadLength = data[4] | (data[5] << 8);

    // Verify packet length
    if (data.length != 8 + payloadLength) {
      return null;
    }

    // Verify checksum
    if (!UbxChecksum.verify(data)) {
      return null;
    }

    // Extract payload
    final payload = data.sublist(6, 6 + payloadLength);

    return UbxPacket(
      messageClass: messageClass,
      messageId: messageId,
      payload: payload,
    );
  }

  @override
  String toString() {
    return 'UbxPacket(class: 0x${messageClass.toRadixString(16).padLeft(2, '0')}, '
        'id: 0x${messageId.toRadixString(16).padLeft(2, '0')}, '
        'payload: ${payload.length} bytes)';
  }
}
