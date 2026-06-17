import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({required this.child, this.darkMode = true, super.key});

  final Widget child;
  final bool darkMode;

  @override
  Widget build(BuildContext context) {
    final baseColor = darkMode ? AppTheme.midnight : const Color(0xfff5f7fb);
    final glowOpacity = darkMode ? 1.0 : 0.34;

    return Stack(
      children: [
        ColoredBox(color: baseColor),
        Positioned(
          top: -120,
          right: -90,
          child: _Glow(size: 310, opacity: glowOpacity, colors: const [AppTheme.electricBlue, AppTheme.violet]),
        ),
        Positioned(
          left: -120,
          bottom: 120,
          child: _Glow(size: 280, opacity: glowOpacity, colors: const [AppTheme.violet, AppTheme.pink]),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
            child: const SizedBox.expand(),
          ),
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.colors, required this.opacity});

  final double size;
  final double opacity;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            colors.first.withOpacity(0.42 * opacity),
            colors.last.withOpacity(0.24 * opacity),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
