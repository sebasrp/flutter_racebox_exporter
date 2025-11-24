// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:racebox_simulator/simulator/simulator_device.dart';

class SimulatorHttpServer {
  final int port;
  final List<SimulatorDevice> devices;
  HttpServer? _server;

  SimulatorHttpServer({
    required this.port,
    required this.devices,
  });

  Future<void> start() async {
    final router = Router();

    // REST API endpoints
    router.get('/api/devices', _handleGetDevices);
    router.post('/api/devices/<id>/connect', _handleConnect);
    router.post('/api/devices/<id>/disconnect', _handleDisconnect);
    router.get('/api/devices/<id>/status', _handleStatus);

    // WebSocket endpoint for data streaming
    router.get('/ws/<id>', (Request request, String id) async {
      return await _handleWebSocket(request, id);
    });

    // Add CORS headers
    final handler = Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(logRequests())
        .addHandler(router.call);

    // Bind to 0.0.0.0 to allow connections from Android emulator (10.0.2.2)
    // and other network interfaces, not just localhost
    _server = await shelf_io.serve(handler, '0.0.0.0', port);
    print('[✓] HTTP server listening on http://0.0.0.0:$port');
    print('[i] Accessible from:');
    print('    - localhost: http://localhost:$port');
    print('    - Android emulator: http://10.0.2.2:$port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    print('[✓] HTTP server stopped');
  }

  Response _handleGetDevices(Request request) {
    final deviceList = devices.map((d) => d.toJson()).toList();
    return Response.ok(
      jsonEncode({'devices': deviceList}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleConnect(Request request, String id) {
    final device = devices.firstWhere(
      (d) => d.id == id,
      orElse: () => throw Exception('Device not found'),
    );

    device.connect();
    print('[${_timestamp()}] Device connected: ${device.name}');

    return Response.ok(
      jsonEncode({'status': 'connected', 'device': device.toJson()}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleDisconnect(Request request, String id) {
    final device = devices.firstWhere(
      (d) => d.id == id,
      orElse: () => throw Exception('Device not found'),
    );

    device.disconnect();
    print('[${_timestamp()}] Device disconnected: ${device.name}');

    return Response.ok(
      jsonEncode({'status': 'disconnected'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _handleStatus(Request request, String id) {
    final device = devices.firstWhere(
      (d) => d.id == id,
      orElse: () => throw Exception('Device not found'),
    );

    return Response.ok(
      jsonEncode(device.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _handleWebSocket(Request request, String id) async {
    final device = devices.firstWhere(
      (d) => d.id == id,
      orElse: () => throw Exception('Device not found'),
    );

    final handler = webSocketHandler((WebSocketChannel webSocket) {
      print('[${_timestamp()}] WebSocket connected for device: ${device.name}');

      // Stream data to WebSocket
      final subscription = device.createDataStream().listen(
        (packet) {
          final message = jsonEncode({
            'type': 'telemetry',
            'data': base64Encode(packet),
          });
          webSocket.sink.add(message);
        },
        onError: (error) {
          print('[${_timestamp()}] WebSocket stream error: $error');
        },
      );

      // Handle WebSocket closure
      webSocket.stream.listen(
        null,
        onDone: () {
          subscription.cancel();
          print('[${_timestamp()}] WebSocket disconnected');
        },
        onError: (error) {
          subscription.cancel();
          print('[${_timestamp()}] WebSocket error: $error');
        },
      );
    });

    return await handler(request);
  }

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders());
        }

        final response = await handler(request);
        return response.change(headers: _corsHeaders());
      };
    };
  }

  Map<String, String> _corsHeaders() {
    return {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }
}
