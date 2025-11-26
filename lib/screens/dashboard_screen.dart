import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/racebox_provider.dart';
import '../racebox_ble/connection/device_connection_interface.dart';
import '../widgets/connection_section.dart';
import '../widgets/gps_section.dart';
import '../widgets/motion_section.dart';
import '../widgets/status_section.dart';
import 'settings_screen.dart';

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
        actions: [
          // Sync status indicator
          Consumer<RaceboxProvider>(
            builder: (context, provider, child) {
              final syncService = provider.syncService;

              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      syncService.isSyncing ? Icons.sync : Icons.cloud_upload,
                      color: syncService.pendingCount > 0
                          ? Colors.orange
                          : Colors.green,
                    ),
                    onPressed: () {
                      if (!syncService.isSyncing) {
                        syncService.syncNow();
                      }
                    },
                    tooltip: 'Sync: ${syncService.pendingCount} pending',
                  ),
                  if (syncService.pendingCount > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          syncService.pendingCount > 99
                              ? '99+'
                              : syncService.pendingCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  if (syncService.isSyncing)
                    const Positioned(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                ],
              );
            },
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
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
                  // Sync status banner
                  if (provider.syncService.isSyncing ||
                      provider.syncService.pendingCount > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: provider.syncService.isSyncing
                            ? Colors.blue.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: provider.syncService.isSyncing
                              ? Colors.blue
                              : Colors.orange,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (provider.syncService.isSyncing)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(
                              Icons.cloud_upload,
                              size: 16,
                              color: Colors.orange,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              provider.syncService.isSyncing
                                  ? 'Syncing data to server...'
                                  : '${provider.syncService.pendingCount} records waiting to sync',
                              style: TextStyle(
                                color: provider.syncService.isSyncing
                                    ? Colors.blue[700]
                                    : Colors.orange[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (!provider.syncService.isSyncing)
                            TextButton(
                              onPressed: () => provider.syncService.syncNow(),
                              child: const Text('Sync Now'),
                            ),
                        ],
                      ),
                    ),

                  // Connection section
                  const ConnectionSection(),
                  const SizedBox(height: 16),

                  // Show data sections only if connected
                  if (provider.connectionState ==
                      DeviceConnectionState.connected) ...[
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
      floatingActionButton: Consumer<RaceboxProvider>(
        builder: (context, provider, child) {
          // Only show FAB when connected
          if (provider.connectionState != DeviceConnectionState.connected) {
            return const SizedBox.shrink();
          }

          return FloatingActionButton.extended(
            onPressed: () {
              if (provider.isRecording) {
                provider.stopRecording();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Recording stopped. ${provider.recordedCount} points saved.',
                    ),
                  ),
                );
              } else {
                provider.startRecording();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recording started')),
                );
              }
            },
            icon: Icon(
              provider.isRecording ? Icons.stop : Icons.fiber_manual_record,
            ),
            label: Text(
              provider.isRecording
                  ? 'Stop (${provider.recordedCount})'
                  : 'Record',
            ),
            backgroundColor: provider.isRecording ? Colors.red : Colors.green,
          );
        },
      ),
    );
  }
}
