import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../theme/app_theme.dart';

class ProgressRing extends StatelessWidget {
  const ProgressRing({required this.percent, this.size = 58, super.key});

  final double percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final safePercent = percent.clamp(0.0, 1.0).toDouble();
    return CircularPercentIndicator(
      radius: size / 2,
      lineWidth: 6,
      animation: true,
      animationDuration: 500,
      percent: safePercent,
      circularStrokeCap: CircularStrokeCap.round,
      backgroundColor: Colors.white.withOpacity(0.12),
      linearGradient: AppTheme.accentGradient,
      center: Text(
        '${(safePercent * 100).round()}%',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
