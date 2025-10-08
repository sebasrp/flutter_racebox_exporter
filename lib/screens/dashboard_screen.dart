import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/racebox_provider.dart';
import '../racebox_ble/connection/ble_manager.dart';
import '../widgets/connection_section.dart';
import '../widgets/gps_section.dart';
import '../widgets/motion_section.dart';
import '../widgets/status_section.dart';

/// Main dashboard screen for displaying Racebox telemetry
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final provider = context.read<RaceboxProvider>();
    final granted = await provider.requestPermissions();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth permissions are required'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Racebox Dashboard'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<RaceboxProvider>(
        builder: (context, provider, child) {
          // Show error if present
          if (provider.error != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(provider.error!),
                  backgroundColor: Colors.red,
                  action: SnackBarAction(
                    label: 'Dismiss',
                    onPressed: () => provider.clearError(),
                  ),
                ),
              );
              provider.clearError();
            });
          }

          return RefreshIndicator(
            onRefresh: () async {
              if (!provider.isConnected) {
                await provider.startScan();
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Connection section
                  const ConnectionSection(),
                  const SizedBox(height: 16),

                  // Show data sections only if connected
                  if (provider.connectionState ==
                      BleConnectionState.connected) ...[
                    // GPS section
                    const GpsSection(),
                    const SizedBox(height: 16),

                    // Motion section
                    const MotionSection(),
                    const SizedBox(height: 16),

                    // Status section
                    const StatusSection(),
                  ] else
                    // Show message when not connected
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.bluetooth_disabled,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Not Connected',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Scan and connect to a Racebox device to view telemetry',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
