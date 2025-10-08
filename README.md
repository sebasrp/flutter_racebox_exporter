# Flutter Racebox Exporter

A Flutter application that connects to Racebox devices (Mini, Mini S, and Micro) via Bluetooth Low Energy (BLE) to display real-time telemetry data including GPS, accelerometer, and gyroscope information.

## Features

- **BLE Device Discovery**: Automatically scan and detect nearby Racebox devices
- **Real-time Telemetry**: Display live data at up to 25Hz update rate
- **GPS Data**:
  - Speed (km/h)
  - Coordinates (latitude/longitude)
  - Altitude (MSL and WGS)
  - Heading with compass visualization
  - Satellite count and fix status
  - Position accuracy metrics
- **Motion Data**:
  - 3-axis G-Force (accelerometer)
  - 3-axis Rotation rates (gyroscope)
  - Visual bar indicators for all axes
- **Device Status**:
  - Battery level monitoring
  - Charging status
  - Time synchronization status
  - Data validity indicators

## Architecture

The application is structured into several layers:

### Library Structure (`lib/racebox_ble/`)

```
racebox_ble/
├── models/              # Data models
│   ├── racebox_data.dart
│   ├── gps_data.dart
│   └── motion_data.dart
├── protocol/            # UBX protocol implementation
│   ├── ubx_packet.dart
│   ├── packet_parser.dart
│   └── checksum.dart
├── connection/          # BLE connection management
│   ├── racebox_device.dart
│   └── ble_manager.dart
└── racebox_service.dart # Main service API
```

### Protocol Implementation

The app implements the Racebox BLE protocol based on U-Blox UBX binary format:

- **Packet Structure**: Header (0xB5 0x62) + Class/ID + Length + Payload + Checksum
- **Data Message**: Class 0xFF, ID 0x01, 80-byte payload
- **Encoding**: Little-Endian integers with scaling factors
- **Checksum**: Fletcher-8 algorithm for data validation

### UI Components

The dashboard is organized into four main sections:

1. **Connection Section**: Device scanning, selection, and connection status
2. **GPS Section**: Speed display, compass, coordinates, and accuracy metrics
3. **Motion Section**: G-Force and rotation rate visualizations
4. **Status Section**: Battery, time, and validity indicators

## Dependencies

- `flutter_blue_plus`: ^1.32.0 - BLE communication
- `provider`: ^6.1.2 - State management
- `permission_handler`: ^11.3.1 - Runtime permissions

## Setup

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Platform Configuration

#### Android

Bluetooth permissions are already configured in `android/app/src/main/AndroidManifest.xml`:
- BLUETOOTH_SCAN
- BLUETOOTH_CONNECT
- ACCESS_FINE_LOCATION (for BLE scanning)

#### iOS

Bluetooth usage descriptions are configured in `ios/Runner/Info.plist`:
- NSBluetoothAlwaysUsageDescription
- NSBluetoothPeripheralUsageDescription
- NSLocationWhenInUseUsageDescription

### 3. Run the App

```bash
flutter run
```

## Usage

1. **Launch the app** - The dashboard screen will appear
2. **Grant permissions** - Allow Bluetooth and location access when prompted
3. **Scan for devices** - Tap "Scan for Devices" button
4. **Connect** - Select your Racebox device from the list
5. **View telemetry** - Real-time data will appear in the GPS, Motion, and Status sections
6. **Disconnect** - Tap "Disconnect" when finished

## Data Conversions

The protocol uses scaled integer values that are converted for display:

- **Coordinates**: Factor of 10^7 → degrees
- **Speed**: mm/s → km/h (÷1000 × 3.6)
- **Heading**: Factor of 10^5 → degrees
- **Altitude**: millimeters → meters (÷1000)
- **G-Force**: milli-g → g (÷1000)
- **Rotation**: centi-degrees/s → degrees/s (÷100)

## Protocol Reference

The implementation follows the **RaceBox BLE Protocol Documentation Revision 8**.

Key UUIDs:
- **UART Service**: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- **TX Characteristic**: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
- **RX Characteristic**: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E`

See `docs/RaceBox BLE Protocol Description rev 8.md` for full protocol details.

## Troubleshooting

### Connection Issues

- Ensure Bluetooth is enabled on your device
- Check that location services are enabled (required for BLE scanning on Android)
- Make sure the Racebox device is powered on and not connected to another app
- Try disconnecting and reconnecting

### No Data Received

- Verify the device has GPS fix (satellite count > 0)
- Check that you're outdoors or near a window for GPS signal
- Ensure the device battery is not depleted

### Permission Errors

- Go to app settings and manually grant Bluetooth and location permissions
- On Android 12+, ensure "Nearby devices" permission is granted

## Future Enhancements

Potential features for future development:

- [ ] Data recording and export to CSV/GPX
- [ ] Backend API integration for cloud storage
- [ ] Historical data playback
- [ ] Custom dashboard layouts
- [ ] Lap timing functionality
- [ ] Multiple device support
- [ ] Data filtering and smoothing options

## License

See LICENSE file for details.

## Acknowledgments

- Racebox LLC for the device and protocol documentation
