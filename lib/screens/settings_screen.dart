import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/racebox_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _isTestingConnection = false;
  bool? _connectionTestResult;

  @override
  void initState() {
    super.initState();
    _loadCurrentUrl();
  }

  Future<void> _loadCurrentUrl() async {
    try {
      final provider = context.read<RaceboxProvider>();
      final url = provider.syncService.baseUrl;
      if (mounted) {
        setState(() {
          _urlController.text = url;
        });
      }
    } catch (e) {
      // If there's an error loading the URL, use the default
      if (mounted) {
        setState(() {
          _urlController.text = 'http://localhost:8080';
        });
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = null;
    });

    final provider = context.read<RaceboxProvider>();
    final result = await provider.syncService.testConnection();

    setState(() {
      _isTestingConnection = false;
      _connectionTestResult = result;
    });
  }

  Future<void> _saveUrl() async {
    final provider = context.read<RaceboxProvider>();
    await provider.syncService.updateApiUrl(_urlController.text);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AVT service URL updated')));
    }
  }

  Future<void> _triggerSync() async {
    final provider = context.read<RaceboxProvider>();
    await provider.syncService.syncNow();
  }

  Future<void> _cleanupOldRecords() async {
    final provider = context.read<RaceboxProvider>();
    final deletedCount = await provider.syncService.cleanupOldRecords();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $deletedCount old records')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: true),
      body: Consumer<RaceboxProvider>(
        builder: (context, provider, child) {
          final syncService = provider.syncService;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // AVT Service Configuration
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AVT Service Configuration',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Service URL',
                          hintText: 'http://localhost:8080',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed:
                                _isTestingConnection ? null : _testConnection,
                            icon: _isTestingConnection
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.network_check),
                            label: const Text('Test Connection'),
                          ),
                          const SizedBox(width: 8),
                          if (_connectionTestResult != null)
                            Icon(
                              _connectionTestResult!
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: _connectionTestResult!
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _saveUrl,
                            icon: const Icon(Icons.save),
                            label: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Sync Status
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync Status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Pending Records',
                        '${syncService.pendingCount}',
                        icon: Icons.pending_actions,
                      ),
                      _buildInfoRow(
                        'Last Sync Attempt',
                        syncService.lastSyncAttempt != null
                            ? _formatDateTime(syncService.lastSyncAttempt!)
                            : 'Never',
                        icon: Icons.access_time,
                      ),
                      _buildInfoRow(
                        'Last Successful Sync',
                        syncService.lastSuccessfulSync != null
                            ? _formatDateTime(syncService.lastSuccessfulSync!)
                            : 'Never',
                        icon: Icons.check_circle_outline,
                      ),
                      if (syncService.lastSyncError != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  syncService.lastSyncError!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed:
                                syncService.isSyncing ? null : _triggerSync,
                            icon: syncService.isSyncing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.sync),
                            label: Text(
                              syncService.isSyncing ? 'Syncing...' : 'Sync Now',
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _cleanupOldRecords,
                            icon: const Icon(Icons.delete_sweep),
                            label: const Text('Cleanup Old Data'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Session Info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session Information',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        'Device ID',
                        syncService.deviceId ?? 'Not connected',
                        icon: Icons.bluetooth,
                      ),
                      _buildInfoRow(
                        'Session ID',
                        syncService.currentSessionId != null
                            ? '${syncService.currentSessionId!.substring(0, 8)}...'
                            : 'Not started',
                        icon: Icons.tag,
                      ),
                      if (provider.isRecording)
                        _buildInfoRow(
                          'Recorded Points',
                          '${provider.recordedCount}',
                          icon: Icons.fiber_manual_record,
                          iconColor: Colors.red,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    required IconData icon,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? Colors.grey),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
}
