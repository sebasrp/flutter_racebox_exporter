import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/racebox_provider.dart';
import '../racebox_ble/connection/ble_manager.dart';
import '../racebox_ble/connection/racebox_device.dart';

/// Connection section widget
class ConnectionSection extends StatelessWidget {
  const ConnectionSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RaceboxProvider>(
      builder: (context, provider, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bluetooth,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Connection',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    _buildStatusIndicator(context, provider.connectionState),
                  ],
                ),
                const SizedBox(height: 16),

                // Connected device info or scan button
                if (provider.isConnected) ...[
                  _buildConnectedDevice(context, provider),
                ] else ...[
                  _buildScanSection(context, provider),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator(BuildContext context, BleConnectionState state) {
    Color color;
    String text;

    switch (state) {
      case BleConnectionState.disconnected:
        color = Colors.grey;
        text = 'Disconnected';
        break;
      case BleConnectionState.connecting:
        color = Colors.orange;
        text = 'Connecting...';
        break;
      case BleConnectionState.connected:
        color = Colors.green;
        text = 'Connected';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _buildConnectedDevice(BuildContext context, RaceboxProvider provider) {
    final device = provider.connectedDevice!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.device_hub, size: 40),
          title: Text(device.name),
          subtitle: Text(device.type.name.toUpperCase()),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => provider.disconnect(),
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _buildScanSection(BuildContext context, RaceboxProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: provider.isScanning ? null : () => provider.startScan(),
          icon: provider.isScanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: Text(provider.isScanning ? 'Scanning...' : 'Scan for Devices'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (provider.devices.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Available Devices:'),
          const SizedBox(height: 8),
          ...provider.devices.map(
            (device) => _buildDeviceTile(
              context,
              device,
              () => provider.connect(device),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDeviceTile(
    BuildContext context,
    RaceboxDevice device,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.device_hub),
        title: Text(device.name),
        subtitle: Text('${device.type.name} • RSSI: ${device.rssi}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
