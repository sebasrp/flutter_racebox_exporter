import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/racebox_provider.dart';

/// Motion data section widget
class MotionSection extends StatelessWidget {
  const MotionSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RaceboxProvider>(
      builder: (context, provider, child) {
        final data = provider.latestData;
        if (data == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Waiting for motion data...')),
            ),
          );
        }

        final motion = data.motion;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.vibration,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Motion Data',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // G-Force section
                Text('G-Force', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMotionBar(
                        context,
                        'X (F/B)',
                        motion.gForceX,
                        Colors.red,
                        -3,
                        3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMotionBar(
                        context,
                        'Y (L/R)',
                        motion.gForceY,
                        Colors.green,
                        -3,
                        3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMotionBar(
                        context,
                        'Z (U/D)',
                        motion.gForceZ,
                        Colors.blue,
                        -3,
                        3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Rotation section
                Text(
                  'Rotation Rate (deg/s)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMotionBar(
                        context,
                        'Roll',
                        motion.rotationX,
                        Colors.orange,
                        -180,
                        180,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMotionBar(
                        context,
                        'Pitch',
                        motion.rotationY,
                        Colors.purple,
                        -180,
                        180,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMotionBar(
                        context,
                        'Yaw',
                        motion.rotationZ,
                        Colors.teal,
                        -180,
                        180,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMotionBar(
    BuildContext context,
    String label,
    double value,
    Color color,
    double min,
    double max,
  ) {
    final normalized = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              value.toStringAsFixed(2),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 20,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              // Center line
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(width: 2, color: Colors.grey[400]),
                ),
              ),
              // Value bar
              FractionallySizedBox(
                widthFactor: normalized,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
