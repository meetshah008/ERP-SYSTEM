import 'dart:math' as math;
import 'package:flutter/material.dart';

class ChartSegment {
  final String label;
  final double value; // Percentage weight e.g. 25
  final Color color;

  const ChartSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

class AnimatedDonutChart extends StatefulWidget {
  final List<ChartSegment> segments;
  final String centerTitle;
  final String centerSubtitle;
  final double size;
  final double strokeWidth;

  const AnimatedDonutChart({
    super.key,
    required this.segments,
    this.centerTitle = '94.8%',
    this.centerSubtitle = 'Appraisal Index',
    this.size = 220,
    this.strokeWidth = 32,
  });

  @override
  State<AnimatedDonutChart> createState() => _AnimatedDonutChartState();
}

class _AnimatedDonutChartState extends State<AnimatedDonutChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Animated Circular Donut Ring with Center Metric
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _animation,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: _DonutChartPainter(
                      segments: widget.segments,
                      progress: _animation.value,
                      strokeWidth: widget.strokeWidth,
                    ),
                  );
                },
              ),
              // Center Label
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.centerTitle,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.centerSubtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 2. Legend Items (Matching reference photo)
        Wrap(
          spacing: 14,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: widget.segments.map((s) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: s.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  s.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<ChartSegment> segments;
  final double progress;
  final double strokeWidth;

  _DonutChartPainter({
    required this.segments,
    required this.progress,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final totalValue = segments.fold<double>(0, (sum, s) => sum + s.value);

    if (totalValue <= 0) return;

    // Start from top (-90 degrees)
    double currentAngle = -math.pi / 2;
    const gapAngle = 0.05; // Gap between segments like the reference photo

    for (final seg in segments) {
      final sweepAngle = (seg.value / totalValue) * 2 * math.pi * progress;
      final effectiveSweep = math.max(0.0, sweepAngle - gapAngle);

      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      if (effectiveSweep > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          currentAngle + (gapAngle / 2),
          effectiveSweep,
          false,
          paint,
        );
      }

      currentAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
