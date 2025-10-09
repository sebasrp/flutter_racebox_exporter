import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'models/racebox_data.dart';
import 'connection/device_connection_interface.dart';
import 'connection/ble_connection.dart';
import 'connection/http_connection.dart';
import 'connection/racebox_device.dart';

/// Main service for interacting with Racebox devices
class RaceboxService {
  final BleConnection _bleConnection = BleConnection();
  HttpConnection? _httpConnection;
  DeviceConnection? _activeConnection;
  StreamSubscription? _activeConnectionStateSubscription;
  StreamSubscription? _activeDataSubscription;

  final _aggregatedDevicesController =
      StreamController<List<RaceboxDevice>>.broadcast();
  final _aggregatedConnectionStateController =
      StreamController<DeviceConnectionState>.broadcast();
  final _aggregatedDataController = StreamController<RaceboxData>.broadcast();
  final _aggregatedErrorController = StreamController<String>.broadcast();

  List<RaceboxDevice> _lastBleDevices = [];
  List<RaceboxDevice> _lastSimDevices = [];

  RaceboxService({bool enableSimulator = kDebugMode}) {
    // In debug mode, enable simulator connection
    if (enableSimulator) {
      _httpConnection = HttpConnection();

      // Merge device streams from both sources
      _bleConnection.devicesStream.listen((bleDevices) {
        if (kDebugMode) {
          print('[RaceboxService] Received ${bleDevices.length} BLE devices');
        }
        _lastBleDevices = bleDevices;
        _mergeAndEmitDevices();
      });

      _httpConnection!.devicesStream.listen((simDevices) {
        if (kDebugMode) {
          print(
            '[RaceboxService] Received ${simDevices.length} simulator devices',
          );
        }
        _lastSimDevices = simDevices;
        _mergeAndEmitDevices();
      });

      // Forward error streams
      _bleConnection.errorStream.listen(_aggregatedErrorController.add);
      _httpConnection!.errorStream.listen(_aggregatedErrorController.add);
    }
  }

  /// Stream of discovered devices
  Stream<List<RaceboxDevice>> get devicesStream {
    if (_httpConnection != null) {
      return _aggregatedDevicesController.stream;
    }
    return _bleConnection.devicesStream;
  }

  /// Stream of connection state
  Stream<DeviceConnectionState> get connectionStateStream {
    if (_httpConnection != null) {
      return _aggregatedConnectionStateController.stream;
    }
    return _bleConnection.connectionStateStream;
  }

  /// Stream of telemetry data
  Stream<RaceboxData> get dataStream {
    if (_httpConnection != null) {
      return _aggregatedDataController.stream;
    }
    return _bleConnection.dataStream;
  }

  /// Stream of error messages
  Stream<String> get errorStream {
    if (_httpConnection != null) {
      return _aggregatedErrorController.stream;
    }
    return _bleConnection.errorStream;
  }

  /// Currently connected device
  RaceboxDevice? get connectedDevice => _activeConnection?.connectedDevice;

  /// Whether currently connected
  bool get isConnected => _activeConnection?.isConnected ?? false;

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    try {
      // Request Bluetooth permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location, // Required on some Android versions
      ].request();

      // Check if all permissions are granted
      return statuses.values.every((status) => status.isGranted);
    } catch (e) {
      return false;
    }
  }

  /// Start scanning for Racebox devices
  Future<void> startScan() async {
    if (kDebugMode) {
      print(
        '[RaceboxService] Starting scan. HTTP connection available: ${_httpConnection != null}',
      );
    }

    // Try BLE scan, but don't fail if Bluetooth is unavailable (especially in debug mode)
    try {
      if (kDebugMode) {
        print('[RaceboxService] Starting BLE scan...');
      }
      await _bleConnection.startScan();
      if (kDebugMode) {
        print('[RaceboxService] BLE scan started successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[RaceboxService] BLE scan failed: $e');
      }
      if (_httpConnection != null) {
        _aggregatedErrorController.add('Bluetooth scan failed: $e');
        // Continue to simulator scan even if BLE fails
      } else {
        rethrow; // In production mode, propagate the error
      }
    }

    // Always try simulator scan in debug mode
    if (_httpConnection != null) {
      try {
        if (kDebugMode) {
          print('[RaceboxService] Starting HTTP scan...');
        }
        await _httpConnection!.startScan();
        if (kDebugMode) {
          print('[RaceboxService] HTTP scan completed');
        }
      } catch (e) {
        if (kDebugMode) {
          print('[RaceboxService] Simulator scan failed: $e');
        }
        _aggregatedErrorController.add('Simulator scan failed: $e');
      }
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    try {
      await _bleConnection.stopScan();
    } catch (e) {
      // Ignore errors when stopping scan
    }

    if (_httpConnection != null) {
      try {
        await _httpConnection!.stopScan();
      } catch (e) {
        // Ignore errors when stopping scan
      }
    }
  }

  /// Connect to a device
  Future<void> connect(RaceboxDevice device) async {
    // Disconnect any existing connection
    if (_activeConnection != null) {
      await _activeConnection!.disconnect();
    }

    // Cancel previous subscriptions
    await _activeConnectionStateSubscription?.cancel();
    await _activeDataSubscription?.cancel();

    // Select the appropriate connection based on device source
    if (device.source == DeviceSource.bluetooth) {
      _activeConnection = _bleConnection;
    } else {
      _activeConnection = _httpConnection;
    }

    if (_activeConnection == null) {
      throw Exception(
        'No connection available for device source: ${device.source}',
      );
    }

    // Forward connection state and data from active connection
    if (_httpConnection != null) {
      // In debug mode with simulator, always forward from active connection
      _activeConnectionStateSubscription = _activeConnection!
          .connectionStateStream
          .listen(_aggregatedConnectionStateController.add);

      _activeDataSubscription = _activeConnection!.dataStream.listen((data) {
        if (kDebugMode) {
          print(
            '[RaceboxService] Received data from active connection, forwarding to aggregated stream',
          );
        }
        _aggregatedDataController.add(data);
      });
    }

    await _activeConnection!.connect(device);
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    if (_activeConnection != null) {
      await _activeConnection!.disconnect();
      _activeConnection = null;
    }
  }

  /// Dispose resources
  void dispose() {
    _activeConnectionStateSubscription?.cancel();
    _activeDataSubscription?.cancel();
    _bleConnection.dispose();
    _httpConnection?.dispose();
    _aggregatedDevicesController.close();
    _aggregatedConnectionStateController.close();
    _aggregatedDataController.close();
    _aggregatedErrorController.close();
  }

  void _mergeAndEmitDevices() {
    final allDevices = [..._lastBleDevices, ..._lastSimDevices];
    if (kDebugMode) {
      print(
        '[RaceboxService] Merging devices: ${_lastBleDevices.length} BLE + ${_lastSimDevices.length} Sim = ${allDevices.length} total',
      );
    }
    _aggregatedDevicesController.add(allDevices);
  }
}
