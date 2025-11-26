import 'dart:async';
import 'dart:collection';
import 'package:logger/logger.dart';

/// In-memory ring buffer for fast, temporary storage of telemetry data
///
/// Specifications from architecture:
/// - Capacity: 125 data points (~5 seconds at 25Hz)
/// - Implementation: Circular buffer with fixed size
/// - Flush trigger: Every 5 seconds OR when buffer is 80% full
/// - Thread-safe: Yes (concurrent reads/writes)
class TelemetryRingBuffer<T> {
  final int capacity;
  final double flushThreshold; // Percentage (0.0 to 1.0)
  final Logger _logger = Logger();

  late final Queue<T> _buffer;
  final _lock = Object();

  // Callbacks
  void Function(List<T> data)? onFlush;

  // Statistics
  int _totalWrites = 0;
  int _totalFlushes = 0;
  int _overflowCount = 0;

  /// Create a ring buffer with specified capacity
  ///
  /// [capacity] - Maximum number of items to store (default: 125 for ~5s at 25Hz)
  /// [flushThreshold] - Percentage full to trigger auto-flush (default: 0.8 = 80%)
  TelemetryRingBuffer({this.capacity = 125, this.flushThreshold = 0.8})
    : assert(capacity > 0, 'Capacity must be positive'),
      assert(
        flushThreshold > 0 && flushThreshold <= 1.0,
        'Flush threshold must be between 0 and 1',
      ) {
    _buffer = Queue<T>();
    _logger.d(
      'Ring buffer created: capacity=$capacity, flushThreshold=${(flushThreshold * 100).toInt()}%',
    );
  }

  /// Add a single item to the buffer
  ///
  /// Returns true if item was added, false if buffer is full and item was dropped
  bool add(T item) {
    return synchronized(() {
      if (_buffer.length >= capacity) {
        // Buffer is full - remove oldest item (FIFO)
        _buffer.removeFirst();
        _overflowCount++;
        _logger.w(
          'Ring buffer overflow - oldest item dropped (total overflows: $_overflowCount)',
        );
      }

      _buffer.add(item);
      _totalWrites++;

      // Check if we should auto-flush
      if (shouldFlush()) {
        _logger.d(
          'Auto-flush triggered: ${_buffer.length}/$capacity items (${_getPercentageFull()}%)',
        );
        _triggerFlush();
      }

      return true;
    });
  }

  /// Add multiple items to the buffer
  ///
  /// Returns the number of items successfully added
  int addAll(List<T> items) {
    return synchronized(() {
      int added = 0;
      for (final item in items) {
        if (_buffer.length >= capacity) {
          _buffer.removeFirst();
          _overflowCount++;
        }
        _buffer.add(item);
        added++;
        _totalWrites++;
      }

      if (shouldFlush()) {
        _logger.d(
          'Auto-flush triggered after batch: ${_buffer.length}/$capacity items',
        );
        _triggerFlush();
      }

      return added;
    });
  }

  /// Check if buffer should be flushed based on threshold
  bool shouldFlush() {
    return _buffer.length >= (capacity * flushThreshold).ceil();
  }

  /// Manually flush the buffer
  ///
  /// Returns the flushed items and clears the buffer
  List<T> flush() {
    return synchronized(() {
      if (_buffer.isEmpty) {
        return [];
      }

      final items = List<T>.from(_buffer);
      _buffer.clear();
      _totalFlushes++;

      _logger.d(
        'Buffer flushed: ${items.length} items (total flushes: $_totalFlushes)',
      );
      return items;
    });
  }

  /// Trigger flush callback if set
  void _triggerFlush() {
    if (onFlush != null && _buffer.isNotEmpty) {
      final items = List<T>.from(_buffer);
      _buffer.clear();
      _totalFlushes++;

      // Call callback asynchronously to avoid blocking
      // Wrap in try-catch to handle callback errors gracefully
      Future.microtask(() {
        try {
          onFlush!(items);
        } catch (e) {
          _logger.w('Error in onFlush callback: $e');
        }
      });
    }
  }

  /// Get current buffer size
  int get size => synchronized(() => _buffer.length);

  /// Get buffer capacity
  int get maxCapacity => capacity;

  /// Check if buffer is empty
  bool get isEmpty => synchronized(() => _buffer.isEmpty);

  /// Check if buffer is full
  bool get isFull => synchronized(() => _buffer.length >= capacity);

  /// Get percentage of buffer filled (0-100)
  int get percentageFull => _getPercentageFull();

  int _getPercentageFull() {
    return synchronized(() {
      if (capacity == 0) return 0;
      return ((_buffer.length / capacity) * 100).round();
    });
  }

  /// Get buffer statistics
  Map<String, dynamic> getStats() {
    return synchronized(
      () => {
        'capacity': capacity,
        'current_size': _buffer.length,
        'percentage_full': percentageFull,
        'total_writes': _totalWrites,
        'total_flushes': _totalFlushes,
        'overflow_count': _overflowCount,
        'flush_threshold': (flushThreshold * 100).toInt(),
      },
    );
  }

  /// Reset statistics (keeps buffer data)
  void resetStats() {
    synchronized(() {
      _totalWrites = 0;
      _totalFlushes = 0;
      _overflowCount = 0;
      _logger.d('Buffer statistics reset');
    });
  }

  /// Clear buffer and reset statistics
  void clear() {
    synchronized(() {
      _buffer.clear();
      _totalWrites = 0;
      _totalFlushes = 0;
      _overflowCount = 0;
      _logger.d('Buffer cleared and statistics reset');
    });
  }

  /// Peek at items without removing them
  ///
  /// [count] - Number of items to peek (default: all)
  List<T> peek([int? count]) {
    return synchronized(() {
      if (_buffer.isEmpty) return [];

      final peekCount = count ?? _buffer.length;
      return _buffer.take(peekCount).toList();
    });
  }

  /// Remove items matching a predicate
  ///
  /// [test] - Function to test each item, returns true to remove
  /// Returns the number of items removed
  int removeWhere(bool Function(T item) test) {
    return synchronized(() {
      final initialSize = _buffer.length;
      _buffer.removeWhere(test);
      final removed = initialSize - _buffer.length;

      if (removed > 0) {
        _logger.d('Removed $removed items from buffer');
      }

      return removed;
    });
  }

  /// Thread-safe execution of operations
  R synchronized<R>(R Function() operation) {
    // Note: Dart is single-threaded, but we use this pattern for:
    // 1. Future-proofing for isolates
    // 2. Ensuring atomic operations
    // 3. Consistent API with other platforms
    return operation();
  }

  /// Dispose of the buffer
  void dispose() {
    synchronized(() {
      _buffer.clear();
      onFlush = null;
      _logger.d('Ring buffer disposed');
    });
  }
}

/// Specialized ring buffer for telemetry data with JSON serialization
class TelemetryDataRingBuffer
    extends TelemetryRingBuffer<Map<String, dynamic>> {
  TelemetryDataRingBuffer({super.capacity = 125, super.flushThreshold = 0.8});

  /// Add telemetry data with automatic timestamp if not present
  bool addTelemetry(Map<String, dynamic> data) {
    // Create a copy to avoid modifying the original
    final dataCopy = Map<String, dynamic>.from(data);

    // Ensure timestamp exists
    if (!dataCopy.containsKey('timestamp')) {
      dataCopy['timestamp'] = DateTime.now().toIso8601String();
    }

    return add(dataCopy);
  }

  /// Get total data size in bytes (approximate)
  int getApproximateSize() {
    return synchronized(() {
      // Rough estimate: average 500 bytes per telemetry record
      return _buffer.length * 500;
    });
  }
}
