import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_racebox_exporter/buffer/telemetry_ring_buffer.dart';

void main() {
  group('TelemetryRingBuffer - Basic Operations', () {
    test('should create buffer with default capacity', () {
      final buffer = TelemetryRingBuffer<int>();

      expect(buffer.capacity, 125);
      expect(buffer.flushThreshold, 0.8);
      expect(buffer.isEmpty, true);
      expect(buffer.size, 0);
    });

    test('should create buffer with custom capacity', () {
      final buffer = TelemetryRingBuffer<int>(
        capacity: 50,
        flushThreshold: 0.7,
      );

      expect(buffer.capacity, 50);
      expect(buffer.flushThreshold, 0.7);
    });

    test('should add single item', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      final added = buffer.add(42);

      expect(added, true);
      expect(buffer.size, 1);
      expect(buffer.isEmpty, false);
    });

    test('should add multiple items', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      final count = buffer.addAll([1, 2, 3, 4, 5]);

      expect(count, 5);
      expect(buffer.size, 5);
    });

    test('should maintain FIFO order', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3, 4, 5]);
      final items = buffer.flush();

      expect(items, [1, 2, 3, 4, 5]);
    });
  });

  group('TelemetryRingBuffer - Overflow Handling', () {
    test('should handle overflow by removing oldest items', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 3);

      buffer.addAll([1, 2, 3]); // Fill buffer
      buffer.add(4); // Should remove 1
      buffer.add(5); // Should remove 2

      final items = buffer.flush();
      expect(items, [3, 4, 5]);
    });

    test('should track overflow count', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 3);

      buffer.addAll([1, 2, 3, 4, 5]); // 2 overflows

      final stats = buffer.getStats();
      expect(stats['overflow_count'], 2);
    });

    test('should handle large batch overflow', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 5);

      buffer.addAll([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      final items = buffer.flush();
      expect(items.length, 5);
      expect(items, [6, 7, 8, 9, 10]); // Last 5 items
    });
  });

  group('TelemetryRingBuffer - Flush Operations', () {
    test('should flush buffer manually', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3]);
      final items = buffer.flush();

      expect(items, [1, 2, 3]);
      expect(buffer.isEmpty, true);
      expect(buffer.size, 0);
    });

    test('should return empty list when flushing empty buffer', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      final items = buffer.flush();

      expect(items, []);
    });

    test('should trigger auto-flush at threshold', () {
      final buffer = TelemetryRingBuffer<int>(
        capacity: 10,
        flushThreshold: 0.8, // 80% = 8 items
      );

      List<int>? flushedItems;
      buffer.onFlush = (items) {
        flushedItems = items;
      };

      // Add 7 items - should not flush
      buffer.addAll([1, 2, 3, 4, 5, 6, 7]);
      expect(flushedItems, null);

      // Add 8th item - should trigger flush
      buffer.add(8);

      // Wait for microtask
      Future.microtask(() {
        expect(flushedItems, isNotNull);
        expect(flushedItems!.length, 8);
      });
    });

    test('should check shouldFlush correctly', () {
      final buffer = TelemetryRingBuffer<int>(
        capacity: 10,
        flushThreshold: 0.8,
      );

      buffer.addAll([1, 2, 3, 4, 5, 6, 7]);
      expect(buffer.shouldFlush(), false);

      buffer.add(8);
      expect(buffer.shouldFlush(), true);
    });
  });

  group('TelemetryRingBuffer - Statistics', () {
    test('should track total writes', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.add(1);
      buffer.addAll([2, 3, 4]);

      final stats = buffer.getStats();
      expect(stats['total_writes'], 4);
    });

    test('should track total flushes', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3]);
      buffer.flush();
      buffer.addAll([4, 5]);
      buffer.flush();

      final stats = buffer.getStats();
      expect(stats['total_flushes'], 2);
    });

    test('should calculate percentage full', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      expect(buffer.percentageFull, 0);

      buffer.addAll([1, 2, 3, 4, 5]); // 50%
      expect(buffer.percentageFull, 50);

      buffer.addAll([6, 7, 8, 9, 10]); // 100%
      expect(buffer.percentageFull, 100);
    });

    test('should provide complete statistics', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3, 4, 5]);
      buffer.flush();

      final stats = buffer.getStats();

      expect(stats['capacity'], 10);
      expect(stats['current_size'], 0); // After flush
      expect(stats['total_writes'], 5);
      expect(stats['total_flushes'], 1);
      expect(stats['overflow_count'], 0);
      expect(stats['flush_threshold'], 80);
    });

    test('should reset statistics', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3]);
      buffer.flush();

      buffer.resetStats();

      final stats = buffer.getStats();
      expect(stats['total_writes'], 0);
      expect(stats['total_flushes'], 0);
      expect(stats['overflow_count'], 0);
      expect(stats['current_size'], 0); // Buffer was cleared by flush
    });
  });

  group('TelemetryRingBuffer - Utility Operations', () {
    test('should peek at items without removing', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3, 4, 5]);

      final peeked = buffer.peek(3);
      expect(peeked, [1, 2, 3]);
      expect(buffer.size, 5); // Size unchanged
    });

    test('should peek all items by default', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3]);

      final peeked = buffer.peek();
      expect(peeked, [1, 2, 3]);
    });

    test('should return empty list when peeking empty buffer', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      final peeked = buffer.peek();
      expect(peeked, []);
    });

    test('should check if buffer is full', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 3);

      expect(buffer.isFull, false);

      buffer.addAll([1, 2, 3]);
      expect(buffer.isFull, true);
    });

    test('should clear buffer and reset stats', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3, 4, 5]);
      buffer.clear();

      expect(buffer.isEmpty, true);
      expect(buffer.size, 0);

      final stats = buffer.getStats();
      expect(stats['total_writes'], 0);
      expect(stats['total_flushes'], 0);
    });

    test('should dispose buffer properly', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3]);
      buffer.onFlush = (items) {};

      buffer.dispose();

      expect(buffer.isEmpty, true);
      expect(buffer.onFlush, null);
    });
  });

  group('TelemetryDataRingBuffer - Specialized Operations', () {
    test('should create telemetry data buffer', () {
      final buffer = TelemetryDataRingBuffer();

      expect(buffer.capacity, 125);
      expect(buffer.flushThreshold, 0.8);
    });

    test('should add telemetry data with automatic timestamp', () {
      final buffer = TelemetryDataRingBuffer(capacity: 10);

      final data = {'latitude': 1.234, 'longitude': 5.678};
      buffer.addTelemetry(data);

      final items = buffer.flush();
      expect(items.length, 1);
      expect(items[0].containsKey('timestamp'), true);
      expect(items[0]['latitude'], 1.234);
    });

    test('should preserve existing timestamp', () {
      final buffer = TelemetryDataRingBuffer(capacity: 10);

      final customTimestamp = '2024-01-01T12:00:00Z';
      final data = {'timestamp': customTimestamp, 'latitude': 1.234};

      buffer.addTelemetry(data);

      final items = buffer.flush();
      expect(items[0]['timestamp'], customTimestamp);
    });

    test('should estimate data size', () {
      final buffer = TelemetryDataRingBuffer(capacity: 10);

      buffer.addAll([
        {'lat': 1.0, 'lon': 2.0},
        {'lat': 3.0, 'lon': 4.0},
        {'lat': 5.0, 'lon': 6.0},
      ]);

      final size = buffer.getApproximateSize();
      expect(size, 1500); // 3 items * 500 bytes
    });

    test('should handle complex telemetry data', () {
      final buffer = TelemetryDataRingBuffer(capacity: 10);

      final telemetryData = {
        'gps': {'latitude': 1.234, 'longitude': 5.678, 'altitude': 100.0},
        'motion': {'gForceX': 0.1, 'gForceY': 0.2, 'gForceZ': 1.0},
        'battery': 85.5,
      };

      buffer.addTelemetry(telemetryData);

      final items = buffer.flush();
      expect(items.length, 1);
      expect(items[0]['gps']['latitude'], 1.234);
      expect(items[0]['motion']['gForceZ'], 1.0);
      expect(items[0]['battery'], 85.5);
    });
  });

  group('TelemetryRingBuffer - Edge Cases', () {
    test('should handle capacity of 1', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 1);

      buffer.add(1);
      buffer.add(2); // Should replace 1

      final items = buffer.flush();
      expect(items, [2]);
    });

    test('should handle flush threshold of 1.0', () {
      final buffer = TelemetryRingBuffer<int>(
        capacity: 10,
        flushThreshold: 1.0,
      );

      buffer.addAll([1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(buffer.shouldFlush(), false);

      buffer.add(10);
      expect(buffer.shouldFlush(), true);
    });

    test('should handle multiple consecutive flushes', () {
      final buffer = TelemetryRingBuffer<int>(capacity: 10);

      buffer.addAll([1, 2, 3]);
      buffer.flush();
      buffer.flush(); // Second flush on empty buffer

      expect(buffer.isEmpty, true);

      final stats = buffer.getStats();
      expect(stats['total_flushes'], 1); // Only first flush counted
    });

    test('should handle generic types', () {
      final stringBuffer = TelemetryRingBuffer<String>(capacity: 5);
      stringBuffer.addAll(['a', 'b', 'c']);
      expect(stringBuffer.flush(), ['a', 'b', 'c']);

      final mapBuffer = TelemetryRingBuffer<Map<String, int>>(capacity: 5);
      mapBuffer.add({'value': 42});
      expect(mapBuffer.flush()[0]['value'], 42);
    });

    test('should handle concurrent operations safely', () async {
      final buffer = TelemetryRingBuffer<int>(capacity: 100);

      // Simulate concurrent writes
      final futures = <Future>[];
      for (int i = 0; i < 10; i++) {
        futures.add(
          Future(() => buffer.addAll(List.generate(10, (j) => i * 10 + j))),
        );
      }

      await Future.wait(futures);

      expect(buffer.size, 100);
      final stats = buffer.getStats();
      expect(stats['total_writes'], 100);
    });
  });

  group('TelemetryRingBuffer - Callback Behavior', () {
    test('should call onFlush callback when auto-flushing', () async {
      final buffer = TelemetryRingBuffer<int>(
        capacity: 10,
        flushThreshold: 0.5, // 50% = 5 items
      );

      List<int>? flushedData;
      buffer.onFlush = (items) {
        flushedData = items;
      };

      buffer.addAll([1, 2, 3, 4, 5]);

      // Wait for microtask to complete
      await Future.delayed(Duration.zero);

      expect(flushedData, isNotNull);
      expect(flushedData, [1, 2, 3, 4, 5]);
      expect(buffer.isEmpty, true);
    });

    test('should not call onFlush if callback is null', () {
      final buffer = TelemetryRingBuffer<int>(
        capacity: 10,
        flushThreshold: 0.5,
      );

      buffer.onFlush = null;
      buffer.addAll([1, 2, 3, 4, 5]);

      // Should not throw, buffer should still have items
      expect(buffer.size, 5);
    });

    test('should handle callback errors gracefully', () async {
      final buffer = TelemetryRingBuffer<int>(
        capacity: 10,
        flushThreshold: 0.5,
      );

      bool callbackCalled = false;
      buffer.onFlush = (items) {
        callbackCalled = true;
        throw Exception('Callback error');
      };

      // Should not throw during add (error happens in microtask)
      expect(() => buffer.addAll([1, 2, 3, 4, 5]), returnsNormally);

      // Wait for microtask to complete (callback will throw but shouldn't crash)
      await Future.delayed(Duration(milliseconds: 10));

      // Callback should have been called
      expect(callbackCalled, true);

      // Buffer should still be cleared despite callback error
      expect(buffer.isEmpty, true);
    });
  });
}
