import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/racebox_data.dart';
import '../protocol/packet_parser.dart';
import '../protocol/ubx_packet.dart';
import 'device_connection_interface.dart';
import 'racebox_device.dart';

/// HTTP-based connection to simulator devices
class HttpConnection implements DeviceConnection {
  final String simulatorUrl;

  RaceboxDevice? _connectedDevice;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;

  final _devicesController = StreamController<List<RaceboxDevice>>.broadcast();
  final _connectionStateController =
      StreamController<DeviceConnectionState>.broadcast();
  final _dataController = StreamController<RaceboxData>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  HttpConnection({this.simulatorUrl = 'http://localhost:8080'});

  @override
  Stream<List<RaceboxDevice>> get devicesStream => _devicesController.stream;

  @override
  Stream<DeviceConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  @override
  Stream<RaceboxData> get dataStream => _dataController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  RaceboxDevice? get connectedDevice => _connectedDevice;

  @override
  bool get isConnected => _connectedDevice != null;

  @override
  Future<void> startScan() async {
    if (kDebugMode) {
      print('[HttpConnection] startScan() called, URL: $simulatorUrl');
    }

    try {
      final uri = Uri.parse('$simulatorUrl/api/devices');
      if (kDebugMode) {
        print('[HttpConnection] Fetching devices from: $uri');
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 2));

      if (kDebugMode) {
        print('[HttpConnection] Response status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final deviceList = (data['devices'] as List).map((d) {
          return RaceboxDevice(
            name: d['name'] as String,
            type: _parseDeviceType(d['type'] as String),
            rssi: d['rssi'] as int,
            source: DeviceSource.simulator,
            simulatorId: d['id'] as String,
          );
        }).toList();

        if (kDebugMode) {
          print(
            '[HttpConnection] Found ${deviceList.length} simulator devices, emitting to stream',
          );
        }
        _devicesController.add(deviceList);
      } else {
        if (kDebugMode) {
          print('[HttpConnection] No devices found, emitting empty list');
        }
        _devicesController.add([]);
      }
    } catch (e) {
      // Simulator not available
      if (kDebugMode) {
        print('[HttpConnection] Error: $e');
      }
      _devicesController.add([]);
    }
  }

  @override
  Future<void> stopScan() async {
    // HTTP connection doesn't need to stop scanning
  }

  @override
  Future<void> connect(RaceboxDevice device) async {
    if (device.source != DeviceSource.simulator || device.simulatorId == null) {
      throw Exception('Invalid device for HTTP connection');
    }

    try {
      _connectionStateController.add(DeviceConnectionState.connecting);

      // Connect via REST API
      final response = await http
          .post(
            Uri.parse(
              '$simulatorUrl/api/devices/${device.simulatorId}/connect',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Failed to connect to simulator device');
      }

      _connectedDevice = device;

      // Small delay to ensure device starts generating data
      await Future.delayed(const Duration(milliseconds: 100));

      // Open WebSocket for data streaming
      final wsUri = Uri.parse(simulatorUrl.replaceFirst('http://', 'ws://'));
      final wsUrl =
          '${wsUri.scheme}://${wsUri.host}:${wsUri.port}/ws/${device.simulatorId}';
      if (kDebugMode) {
        print('[HttpConnection] Connecting to WebSocket: $wsUrl');
      }
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      if (kDebugMode) {
        print('[HttpConnection] WebSocket connection initiated');
      }

      // Listen to WebSocket data
      _wsSubscription = _wsChannel!.stream.listen(
        (message) {
          try {
            if (kDebugMode) {
              print('[HttpConnection] Received WebSocket message');
            }
            final json = jsonDecode(message as String) as Map<String, dynamic>;
            if (json['type'] == 'telemetry') {
              final packetBytes = base64Decode(json['data'] as String);
              if (kDebugMode) {
                print(
                  '[HttpConnection] Decoded packet: ${packetBytes.length} bytes',
                );
              }

              // Parse UBX packet structure first to extract payload
              final ubxPacket = UbxPacket.parse(packetBytes);
              if (ubxPacket != null) {
                if (kDebugMode) {
                  print(
                    '[HttpConnection] UBX packet parsed, payload: ${ubxPacket.payload.length} bytes',
                  );
                }

                // Now parse the payload as RaceboxData
                final data = PacketParser.parseDataMessage(ubxPacket.payload);
                if (data != null) {
                  if (kDebugMode) {
                    print(
                      '[HttpConnection] Parsed data successfully, emitting to stream',
                    );
                  }
                  _dataController.add(data);
                } else {
                  if (kDebugMode) {
                    print(
                      '[HttpConnection] Failed to parse RaceboxData from payload',
                    );
                  }
                }
              } else {
                if (kDebugMode) {
                  print('[HttpConnection] Failed to parse UBX packet');
                }
              }
            }
          } catch (e) {
            _errorController.add('Error parsing telemetry: $e');
            if (kDebugMode) {
              print('[HttpConnection] Error: $e');
            }
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print('[HttpConnection] WebSocket onError: $error');
          }
          _errorController.add('WebSocket error: $error');
          _connectionStateController.add(DeviceConnectionState.disconnected);
        },
        onDone: () {
          if (kDebugMode) {
            print('[HttpConnection] WebSocket onDone');
          }
          _connectionStateController.add(DeviceConnectionState.disconnected);
          _connectedDevice = null;
        },
      );

      if (kDebugMode) {
        print('[HttpConnection] Setting connection state to connected');
      }
      _connectionStateController.add(DeviceConnectionState.connected);
    } catch (e) {
      _errorController.add('Failed to connect: $e');
      _connectionStateController.add(DeviceConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_connectedDevice == null) return;

    try {
      await http
          .post(
            Uri.parse(
              '$simulatorUrl/api/devices/${_connectedDevice!.simulatorId}/disconnect',
            ),
          )
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      // Ignore errors during disconnect
    }

    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _wsChannel?.sink.close();
    _wsChannel = null;

    _connectedDevice = null;
    _connectionStateController.add(DeviceConnectionState.disconnected);
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _devicesController.close();
    _connectionStateController.close();
    _dataController.close();
    _errorController.close();
  }

  RaceboxDeviceType _parseDeviceType(String type) {
    switch (type.toLowerCase()) {
      case 'minis':
        return RaceboxDeviceType.miniS;
      case 'micro':
        return RaceboxDeviceType.micro;
      default:
        return RaceboxDeviceType.mini;
    }
  }
}
