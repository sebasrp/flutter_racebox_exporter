# Racebox Device Simulator

A standalone HTTP/WebSocket server that simulates Racebox BLE devices for testing and development without requiring physical hardware.

## Features

- **HTTP REST API** for device discovery and control
- **WebSocket streaming** for real-time telemetry data at 25Hz
- **Two simulation modes**: static (stationary) and moving
- **Multiple route types**: circular and straight
- **Realistic data generation**: GPS coordinates, speed, heading, motion sensors
- **Configurable parameters**: location, speed, battery level, satellites, etc.
- **No Bluetooth required**: Perfect for CI/CD and emulators

## Installation

```bash
# Navigate to simulator directory
cd simulator

# Install dependencies
dart pub get
```

## Usage

### Basic Usage

```bash
# Start with default settings (static mode)
dart run bin/racebox_simulator.dart

# Moving vehicle at 80 km/h in circular route
dart run bin/racebox_simulator.dart --mode moving --speed 80

# Specific location
dart run bin/racebox_simulator.dart --lat 37.7749 --lon -122.4194

# Custom device name and type
dart run bin/racebox_simulator.dart --name "My RaceBox" --type miniS
```

### Command-Line Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--port` | `-p` | `8090` | HTTP server port |
| `--mode` | `-m` | `static` | Simulator mode: static or moving |
| `--name` | `-n` | `RaceBox Mini (Simulator)` | Device name |
| `--type` | | `mini` | Device type: mini, miniS, or micro |
| `--lat` | | `42.3601` | Starting latitude |
| `--lon` | | `-71.0589` | Starting longitude |
| `--speed` | | `50` | Speed in km/h (moving mode) |
| `--route` | | `circular` | Route type: circular or straight |
| `--battery` | | `100` | Battery level (0-100) |
| `--satellites` | | `10` | Number of satellites (4-20) |
| `--altitude` | | `50.0` | Altitude in meters |
| `--help` | `-h` | | Show help message |

### Examples

```bash
# Stationary device in Boston
dart run bin/racebox_simulator.dart \
  --lat 42.3601 \
  --lon -71.0589

# Fast moving vehicle (120 km/h) in circular pattern
dart run bin/racebox_simulator.dart \
  --mode moving \
  --speed 120 \
  --route circular

# Racing scenario with low battery
dart run bin/racebox_simulator.dart \
  --mode moving \
  --speed 200 \
  --battery 25 \
  --name "RaceBox Mini S (Track)"

# Straight line movement
dart run bin/racebox_simulator.dart \
  --mode moving \
  --speed 60 \
  --route straight
```

## API Reference

### REST Endpoints

#### Get Devices
```http
GET /api/devices
```

Returns list of available simulator devices.

**Response:**
```json
{
  "devices": [
    {
      "id": "1234567890",
      "name": "RaceBox Mini (Simulator)",
      "type": "mini",
      "rssi": -45,
      "connected": false
    }
  ]
}
```

#### Connect to Device
```http
POST /api/devices/:id/connect
```

**Response:**
```json
{
  "status": "connected",
  "device": { ... }
}
```

#### Disconnect from Device
```http
POST /api/devices/:id/disconnect
```

**Response:**
```json
{
  "status": "disconnected"
}
```

#### Get Device Status
```http
GET /api/devices/:id/status
```

### WebSocket Endpoint

```
ws://localhost:8090/ws/:id
```

Streams telemetry data at 25Hz (every 40ms).

**Message format:**
```json
{
  "type": "telemetry",
  "data": "<base64-encoded UBX packet>"
}
```

## Using with Flutter App

1. Start the simulator:
```bash
dart run simulator/bin/racebox_simulator.dart --mode moving --speed 80
```

2. Run the Flutter app in debug mode:
```bash
flutter run
```

3. In the app:
   - Tap "Scan for Devices"
   - You'll see both Bluetooth devices (if any) and simulator devices
   - Simulator devices show a computer icon (🖥️)
   - Connect to the simulator device

## Multiple Simulators

You can run multiple simulators on different ports:

```bash
# Terminal 1: Device 1
dart run bin/racebox_simulator.dart --port 8090 --name "Device 1" --speed 60

# Terminal 2: Device 2
dart run bin/racebox_simulator.dart --port 8081 --name "Device 2" --speed 100
```

Update the Flutter app's `HttpConnection` to scan multiple ports.

## CI/CD Integration

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Dart
        uses: dart-lang/setup-dart@v1
      
      - name: Start simulator
        run: |
          cd simulator
          dart pub get
          dart run bin/racebox_simulator.dart &
          sleep 2
      
      - name: Run integration tests
        run: flutter test integration_test/
```

## Data Generation

The simulator generates realistic data based on the protocol specification:

- **GPS Data**: Coordinates, speed, heading, satellites, accuracy
- **Motion Data**: Accelerometer (G-forces) and gyroscope (rotation rates)
- **Time Data**: UTC time with validity flags
- **Battery**: Configurable level and charging status

### Movement Simulation

**Static Mode:**
- Fixed coordinates with GPS noise (±5 meters)
- Speed = 0 km/h
- 1g downward on Z-axis (stationary)

**Moving Mode (Circular):**
- Movement in ~1km radius circle
- Calculates lateral G-forces based on speed
- Realistic heading changes
- Rotation based on angular velocity

**Moving Mode (Straight):**
- Movement northward at constant speed
- Heading = 0° (north)
- Minimal lateral forces

## Troubleshooting

### Simulator not detected in app

- Check simulator is running: `curl http://localhost:8090/api/devices`
- Ensure port 8090 is not blocked
- Verify Flutter app is in debug mode

### No data received

- Check WebSocket connection in simulator logs
- Verify device is "connected" state
- Check for errors in Flutter app error stream

### Port already in use

```bash
# Use different port
dart run bin/racebox_simulator.dart --port 8081
```

## Development

### Project Structure

```
simulator/
├── bin/
│   └── racebox_simulator.dart      # CLI entry point
├── lib/
│   ├── server/
│   │   └── http_server.dart        # HTTP/WebSocket server
│   └── simulator/
│       ├── simulator_config.dart   # Configuration
│       ├── simulator_device.dart   # Device management
│       ├── data_generator.dart     # Telemetry generation
│       └── movement_simulator.dart # GPS movement
└── pubspec.yaml
```

### Adding New Features

1. **Custom routes**: Extend `MovementSimulator` with new route types
2. **Fault injection**: Add random GPS loss, connection drops
3. **Recorded playback**: Load GPX files and replay routes
4. **Multiple devices**: Extend `SimulatorHttpServer` to manage multiple devices

## License

See LICENSE file in main project.

