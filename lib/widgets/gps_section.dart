import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/racebox_provider.dart';
import 'dart:math' as math;

/// GPS data section widget
class GpsSection extends StatelessWidget {
  const GpsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RaceboxProvider>(
      builder: (context, provider, child) {
        final data = provider.latestData;
        if (data == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Waiting for GPS data...')),
            ),
          );
        }

        final gps = data.gps;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.satellite_alt,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'GPS Data',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    _buildFixIndicator(context, gps.isFixValid),
                  ],
                ),
                const SizedBox(height: 16),

                // Speed (large display)
                Center(
                  child: Column(
                    children: [
                      Text(
                        gps.speed.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const Text('km/h', style: TextStyle(fontSize: 20)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Heading compass
                Center(
                  child: Column(
                    children: [
                      CustomPaint(
                        size: const Size(100, 100),
                        painter: CompassPainter(gps.heading),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${gps.heading.toStringAsFixed(1)}°',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Grid of values
                Row(
                  children: [
                    Expanded(
                      child: _buildDataItem(
                        context,
                        'Latitude',
                        gps.latitude.toStringAsFixed(7),
                        Icons.place,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDataItem(
                        context,
                        'Longitude',
                        gps.longitude.toStringAsFixed(7),
                        Icons.place,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildDataItem(
                        context,
                        'Altitude',
                        '${gps.mslAltitude.toStringAsFixed(1)} m',
                        Icons.terrain,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDataItem(
                        context,
                        'Satellites',
                        '${gps.numSatellites}',
                        Icons.satellite,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildDataItem(
                        context,
                        'H. Accuracy',
                        '${gps.horizontalAccuracy.toStringAsFixed(1)} m',
                        Icons.gps_fixed,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDataItem(
                        context,
                        'PDOP',
                        gps.pdop.toStringAsFixed(1),
                        Icons.signal_cellular_alt,
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

  Widget _buildFixIndicator(BuildContext context, bool isValid) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.cancel,
          color: isValid ? Colors.green : Colors.red,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          isValid ? 'Fix Valid' : 'No Fix',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isValid ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildDataItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for compass display
class CompassPainter extends CustomPainter {
  final double heading;

  CompassPainter(this.heading);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw circle
    final circlePaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, circlePaint);

    // Draw cardinal directions
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final directions = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final x = center.dx + radius * 0.8 * math.sin(angle);
      final y = center.dy - radius * 0.8 * math.cos(angle);

      textPainter.text = TextSpan(
        text: directions[i],
        style: TextStyle(
          color: i == 0 ? Colors.red : Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }

    // Draw heading arrow
    final headingRad = heading * math.pi / 180;
    final arrowPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(
      center.dx + radius * 0.6 * math.sin(headingRad),
      center.dy - radius * 0.6 * math.cos(headingRad),
    );
    path.lineTo(
      center.dx + radius * 0.2 * math.sin(headingRad + math.pi * 0.9),
      center.dy - radius * 0.2 * math.cos(headingRad + math.pi * 0.9),
    );
    path.lineTo(center.dx, center.dy);
    path.lineTo(
      center.dx + radius * 0.2 * math.sin(headingRad - math.pi * 0.9),
      center.dy - radius * 0.2 * math.cos(headingRad - math.pi * 0.9),
    );
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(CompassPainter oldDelegate) {
    return oldDelegate.heading != heading;
  }
}
