import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/racebox_provider.dart';

/// Status section widget
class StatusSection extends StatelessWidget {
  const StatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RaceboxProvider>(
      builder: (context, provider, child) {
        final data = provider.latestData;
        if (data == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Waiting for status data...')),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Device Status',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Battery status
                _buildStatusRow(
                  context,
                  'Battery',
                  '${data.battery.toStringAsFixed(0)}%',
                  Icons.battery_full,
                  _getBatteryColor(data.battery),
                ),
                if (data.isCharging)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.power, size: 16, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text(
                          'Charging',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.green[700]),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 24),

                // Time info
                _buildStatusRow(
                  context,
                  'Device Time',
                  _formatTime(data.timestamp),
                  Icons.access_time,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(
                  context,
                  'Time Accuracy',
                  '${(data.timeAccuracy / 1000).toStringAsFixed(1)} μs',
                  Icons.timer,
                ),
                const Divider(height: 24),

                // Data validity
                _buildStatusRow(
                  context,
                  'Date Valid',
                  data.isDateValid ? 'Yes' : 'No',
                  Icons.calendar_today,
                  data.isDateValid ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(
                  context,
                  'Time Valid',
                  data.isTimeValid ? 'Yes' : 'No',
                  Icons.schedule,
                  data.isTimeValid ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(
                  context,
                  'Time Resolved',
                  data.isTimeFullyResolved ? 'Yes' : 'No',
                  Icons.check_circle_outline,
                  data.isTimeFullyResolved ? Colors.green : Colors.orange,
                ),

                // Show hint if time not valid
                if (!data.isTimeValid || !data.isDateValid)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Time sync requires GPS fix. Take device outdoors and wait for satellites.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.orange[700]),
                            ),
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
    );
  }

  Widget _buildStatusRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, [
    Color? valueColor,
  ]) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Color _getBatteryColor(double level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')} UTC';
  }
}
