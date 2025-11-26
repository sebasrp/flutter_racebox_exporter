// ignore_for_file: avoid_print

import 'dart:io';
import 'package:args/args.dart';
import 'package:racebox_simulator/server/http_server.dart';
import 'package:racebox_simulator/simulator/simulator_config.dart';
import 'package:racebox_simulator/simulator/simulator_device.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8090', help: 'HTTP server port')
    ..addOption(
      'mode',
      abbr: 'm',
      defaultsTo: 'static',
      help: 'Simulator mode: static or moving',
    )
    ..addOption(
      'name',
      abbr: 'n',
      defaultsTo: 'RaceBox Mini (Simulator)',
      help: 'Device name',
    )
    ..addOption(
      'type',
      defaultsTo: 'mini',
      help: 'Device type: mini, miniS, or micro',
    )
    ..addOption('lat', defaultsTo: '42.3601', help: 'Starting latitude')
    ..addOption('lon', defaultsTo: '-71.0589', help: 'Starting longitude')
    ..addOption('speed', defaultsTo: '50', help: 'Speed in km/h (moving mode)')
    ..addOption(
      'route',
      defaultsTo: 'circular',
      help: 'Route type: circular or straight',
    )
    ..addOption('battery', defaultsTo: '100', help: 'Battery level (0-100)')
    ..addOption(
      'satellites',
      defaultsTo: '10',
      help: 'Number of satellites (4-20)',
    )
    ..addOption('altitude', defaultsTo: '50.0', help: 'Altitude in meters')
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message',
    );

  try {
    final results = parser.parse(args);

    if (results['help'] as bool) {
      _printHelp(parser);
      exit(0);
    }

    final config = SimulatorConfig.fromArgs(results);
    final device = SimulatorDevice(config: config);
    final server = SimulatorHttpServer(port: config.port, devices: [device]);

    _printBanner(config);

    // Handle graceful shutdown
    ProcessSignal.sigint.watch().listen((signal) async {
      print('\n[!] Shutting down...');
      device.disconnect();
      await server.stop();
      exit(0);
    });

    await server.start();
    print('[✓] Simulator ready. Waiting for connections...');
    print('');
    print('Press Ctrl+C to stop.');
    print('');
  } catch (e) {
    print('Error: $e');
    print('');
    _printHelp(parser);
    exit(1);
  }
}

void _printBanner(SimulatorConfig config) {
  print('═══════════════════════════════════════════════════════');
  print('  Racebox Simulator v1.0.0');
  print('═══════════════════════════════════════════════════════');
  print('');
  print('Configuration:');
  print('  Server:     http://localhost:${config.port}');
  print('  Device:     ${config.deviceName}');
  print('  Type:       ${config.deviceTypeString}');
  print('  Mode:       ${config.mode.name}');

  if (config.mode == SimulatorMode.moving) {
    print('  Speed:      ${config.speed} km/h');
    print('  Route:      ${config.route.name}');
  }

  print(
    '  Location:   ${config.startLat.toStringAsFixed(4)}, ${config.startLon.toStringAsFixed(4)}',
  );
  print('  Altitude:   ${config.altitude.toStringAsFixed(1)} m');
  print('  Battery:    ${config.batteryLevel}%');
  print('  Satellites: ${config.satelliteCount}');
  print('');
}

void _printHelp(ArgParser parser) {
  print('Racebox Device Simulator');
  print('');
  print('Usage: dart run simulator/bin/racebox_simulator.dart [options]');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Examples:');
  print('  # Start with default settings (static mode)');
  print('  dart run simulator/bin/racebox_simulator.dart');
  print('');
  print('  # Moving vehicle at 80 km/h');
  print(
    '  dart run simulator/bin/racebox_simulator.dart --mode moving --speed 80',
  );
  print('');
  print('  # Specific location');
  print(
    '  dart run simulator/bin/racebox_simulator.dart --lat 37.7749 --lon -122.4194',
  );
  print('');
  print('  # Custom device name and type');
  print(
    '  dart run simulator/bin/racebox_simulator.dart --name "My RaceBox" --type miniS',
  );
  print('');
}
