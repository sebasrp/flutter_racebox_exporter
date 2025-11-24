import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/racebox_data.dart';
import '../protocol/ubx_packet.dart';
import '../protocol/packet_parser.dart';
import 'racebox_device.dart';

/// Manages BLE connection and data streaming from Racebox device
class BleManager {
  /// UART Service UUID
  static final Guid uartServiceUuid = Guid(
    '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
  );

  /// RX Characteristic UUID (for writing to device)
  static final Guid rxCharacteristicUuid = Guid(
    '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
  );

  /// TX Characteristic UUID (for receiving from device)
  static final Guid txCharacteristicUuid = Guid(
    '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
  );

  /// Currently connected device
  RaceboxDevice? _connectedDevice;

  /// TX characteristic for receiving data
  BluetoothCharacteristic? _txCharacteristic;

  /// Buffer for assembling packets from BLE notifications
  final List<int> _buffer = [];

  /// Stream controller for discovered devices
  final _devicesController = StreamController<List<RaceboxDevice>>.broadcast();

  /// Stream controller for connection state
  final _connectionStateController =
      StreamController<BleConnectionState>.broadcast();

  /// Stream controller for data packets
  final _dataController = StreamController<RaceboxData>.broadcast();

  /// Stream controller for errors
  final _errorController = StreamController<String>.broadcast();

  /// List of discovered devices
  final List<RaceboxDevice> _discoveredDevices = [];

  /// Subscription to scan results
  StreamSubscription? _scanSubscription;

  /// Subscription to device connection state
  StreamSubscription? _connectionStateSubscription;

  /// Subscription to characteristic notifications
  StreamSubscription? _notificationSubscription;

  /// Stream of discovered devices
  Stream<List<RaceboxDevice>> get devicesStream => _devicesController.stream;

  /// Stream of connection state changes
  Stream<BleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Stream of parsed data packets
  Stream<RaceboxData> get dataStream => _dataController.stream;

  /// Stream of error messages
  Stream<String> get errorStream => _errorController.stream;

  /// Currently connected device
  RaceboxDevice? get connectedDevice => _connectedDevice;

  /// Whether currently connected to a device
  bool get isConnected => _connectedDevice != null;

  /// Start scanning for Racebox devices
  Future<void> startScan() async {
    try {
      _discoveredDevices.clear();
      _devicesController.add(_discoveredDevices);

      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        _errorController.add('Bluetooth is not supported on this device');
        return;
      }

      // Start scanning with service UUID filter
      // This helps with service discovery on some platforms
      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 10),
          withServices: [uartServiceUuid],
        );
      } catch (e) {
        // Fallback: scan without service filter if filtered scan fails
        // Some devices have issues with service filtering
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      }

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final device = RaceboxDevice.fromScanResult(result);
          if (device != null) {
            // Update or add device
            final index = _discoveredDevices.indexWhere(
              (d) => d.device!.remoteId == device.device!.remoteId,
            );
            if (index >= 0) {
              _discoveredDevices[index] = device;
            } else {
              _discoveredDevices.add(device);
            }
          }
        }
        _devicesController.add(List.from(_discoveredDevices));
      });
    } catch (e) {
      _errorController.add('Failed to start scan: $e');
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    } catch (e) {
      _errorController.add('Failed to stop scan: $e');
    }
  }

  /// Connect to a device
  Future<void> connect(RaceboxDevice device) async {
    try {
      _connectionStateController.add(BleConnectionState.connecting);

      // Stop scanning
      await stopScan();

      // Ensure device has a Bluetooth device (not a simulator)
      if (device.device == null) {
        throw Exception(
          'Cannot connect to non-Bluetooth device via BLE manager',
        );
      }

      // Check if device is already connected
      final connectionState = await device.device!.connectionState.first;
      if (connectionState == BluetoothConnectionState.connected) {
        // Already connected, try to disconnect first
        try {
          await device.device!.disconnect();
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          // Ignore disconnect errors
        }
      }

      // Connect to device with longer timeout
      await device.device!.connect(
        timeout: const Duration(seconds: 35),
        autoConnect: false,
        license: License.free,
      );

      // Wait for connection to stabilize
      await Future.delayed(const Duration(seconds: 1));

      _connectedDevice = device;

      // Listen to connection state
      _connectionStateSubscription = device.device!.connectionState.listen((
        state,
      ) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // Request higher MTU for better data throughput
      try {
        await device.device!.requestMtu(512);
      } catch (e) {
        // MTU request may fail on some devices, continue anyway
      }

      // Discover services
      final services = await device.device!.discoverServices();

      // Small delay after service discovery to let device stabilize
      await Future.delayed(const Duration(milliseconds: 500));

      // Find UART service
      BluetoothService? uartService;
      for (final service in services) {
        if (service.uuid == uartServiceUuid) {
          uartService = service;
          break;
        }
      }

      if (uartService == null) {
        throw Exception('UART service not found');
      }

      // Find TX characteristic
      for (final characteristic in uartService.characteristics) {
        if (characteristic.uuid == txCharacteristicUuid) {
          _txCharacteristic = characteristic;
          break;
        }
      }

      if (_txCharacteristic == null) {
        throw Exception('TX characteristic not found');
      }

      // Use onValueReceived stream which auto-subscribes
      // This is more reliable on some devices
      _notificationSubscription = _txCharacteristic!.onValueReceived.listen(
        _handleNotification,
        onError: (error) {
          _errorController.add('Notification stream error: $error');
        },
      );

      // Try to enable notifications, but don't fail if it times out
      // Some devices automatically send notifications once you subscribe to the stream
      try {
        // Check if already subscribed
        if (!_txCharacteristic!.isNotifying) {
          // Try to enable with timeout - use try/catch instead of onTimeout
          try {
            await _txCharacteristic!
                .setNotifyValue(true)
                .timeout(const Duration(seconds: 15));
          } on TimeoutException {
            // Timeout - but don't throw, device might still work
            // Some Racebox devices start sending data without explicit enable
            _errorController.add(
              'Notification enable timed out, continuing anyway...',
            );
          }
        }

        // Small delay to verify
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // Log but don't fail - device may work anyway
        _errorController.add(
          'Note: Could not enable notifications, but connection may still work: $e',
        );
      }

      _connectionStateController.add(BleConnectionState.connected);
    } catch (e) {
      _errorController.add('Failed to connect: $e');
      _connectionStateController.add(BleConnectionState.disconnected);
      await disconnect();
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    try {
      // Disable notifications first
      if (_txCharacteristic != null) {
        try {
          await _txCharacteristic!.setNotifyValue(false);
        } catch (e) {
          // Ignore errors when disabling notifications
        }
      }

      await _notificationSubscription?.cancel();
      _notificationSubscription = null;

      await _connectionStateSubscription?.cancel();
      _connectionStateSubscription = null;

      if (_connectedDevice != null && _connectedDevice!.device != null) {
        await _connectedDevice!.device!.disconnect();
      }

      _txCharacteristic = null;
      _connectedDevice = null;
      _buffer.clear();

      _connectionStateController.add(BleConnectionState.disconnected);
    } catch (e) {
      _errorController.add('Failed to disconnect: $e');
    }
  }

  /// Handle disconnection
  void _handleDisconnection() {
    _txCharacteristic = null;
    _connectedDevice = null;
    _buffer.clear();
    _connectionStateController.add(BleConnectionState.disconnected);
  }

  /// Handle incoming notification data
  void _handleNotification(List<int> data) {
    // Add new data to buffer
    _buffer.addAll(data);

    // Try to extract complete packets from buffer
    _processBuffer();
  }

  /// Process buffer to extract complete packets
  void _processBuffer() {
    while (_buffer.length >= 8) {
      // Look for packet start
      int startIndex = -1;
      for (int i = 0; i < _buffer.length - 1; i++) {
        if (_buffer[i] == UbxPacket.header1 &&
            _buffer[i + 1] == UbxPacket.header2) {
          startIndex = i;
          break;
        }
      }

      // No packet start found
      if (startIndex == -1) {
        _buffer.clear();
        return;
      }

      // Remove data before packet start
      if (startIndex > 0) {
        _buffer.removeRange(0, startIndex);
      }

      // Check if we have enough data for header
      if (_buffer.length < 6) {
        return; // Wait for more data
      }

      // Extract payload length
      final payloadLength = _buffer[4] | (_buffer[5] << 8);
      final totalLength = 8 + payloadLength;

      // Check if we have complete packet
      if (_buffer.length < totalLength) {
        return; // Wait for more data
      }

      // Extract packet
      final packetData = _buffer.sublist(0, totalLength);
      _buffer.removeRange(0, totalLength);

      // Parse packet
      final packet = UbxPacket.parse(packetData);
      if (packet != null) {
        _handlePacket(packet);
      }
    }
  }

  /// Handle parsed packet
  void _handlePacket(UbxPacket packet) {
    // Check if it's a Racebox data message
    if (packet.messageClass == PacketParser.raceboxClass &&
        packet.messageId == PacketParser.raceboxDataId) {
      final data = PacketParser.parseDataMessage(packet.payload);
      if (data != null) {
        _dataController.add(data);
      }
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _notificationSubscription?.cancel();
    _devicesController.close();
    _connectionStateController.close();
    _dataController.close();
    _errorController.close();
  }
}

/// BLE connection states
enum BleConnectionState { disconnected, connecting, connected }
