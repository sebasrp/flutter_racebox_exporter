/// Calculate UBX checksum for a packet
class UbxChecksum {
  /// Calculate checksum for packet data
  /// Returns [CK_A, CK_B] as a list of 2 bytes
  static List<int> calculate(List<int> data, int start, int end) {
    int ckA = 0;
    int ckB = 0;

    for (int i = start; i < end; i++) {
      ckA = (ckA + data[i]) & 0xFF;
      ckB = (ckB + ckA) & 0xFF;
    }

    return [ckA, ckB];
  }

  /// Verify checksum of a complete packet
  static bool verify(List<int> packet) {
    if (packet.length < 8) {
      return false; // Packet too short
    }

    // Calculate checksum over class, ID, length, and payload
    final calculated = calculate(packet, 2, packet.length - 2);
    final providedA = packet[packet.length - 2];
    final providedB = packet[packet.length - 1];

    return calculated[0] == providedA && calculated[1] == providedB;
  }
}
