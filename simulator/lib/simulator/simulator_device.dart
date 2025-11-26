import 'dart:async';
import 'simulator_config.dart';
import 'movement_simulator.dart';
import 'data_generator.dart';

class SimulatorDevice {
  final String id;
  final SimulatorConfig config;
  final MovementSimulator movement;
  final DataGenerator dataGenerator;

  bool _isConnected = false;
  Timer? _dataTimer;
  final List<StreamController<List<int>>> _dataControllers = [];

  SimulatorDevice({required this.config})
    : id = DateTime.now().millisecondsSinceEpoch.toString(),
      movement = MovementSimulator(config: config),
      dataGenerator = DataGenerator(
        movement: MovementSimulator(config: config),
        config: config,
      );

  bool get isConnected => _isConnected;
  String get name => config.deviceName;
  String get type => config.deviceTypeString;

  void connect() {
    if (_isConnected) return;

    _isConnected = true;
    _startDataGeneration();
  }

  void disconnect() {
    if (!_isConnected) return;

    _isConnected = false;
    _dataTimer?.cancel();
    _dataTimer = null;

    // Close all data streams
    for (final controller in _dataControllers) {
      controller.close();
    }
    _dataControllers.clear();
  }

  Stream<List<int>> createDataStream() {
    final controller = StreamController<List<int>>();
    _dataControllers.add(controller);
    return controller.stream;
  }

  void _startDataGeneration() {
    // Generate data at 25Hz (every 40ms)
    _dataTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!_isConnected) {
        timer.cancel();
        return;
      }

      final packet = dataGenerator.generate();

      // Send to all connected streams
      for (final controller in _dataControllers) {
        if (!controller.isClosed) {
          controller.add(packet);
        }
      }
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'rssi': -45,
      'connected': _isConnected,
    };
  }
}
