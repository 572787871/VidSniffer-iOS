import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ColoredBox(color: AppTheme.midnight),
        const Positioned(
          top: -120,
          right: -90,
          child: _Glow(size: 310, colors: [AppTheme.electricBlue, AppTheme.violet]),
        ),
        const Positioned(
          left: -120,
          bottom: 120,
          child: _Glow(size: 280, colors: [AppTheme.violet, AppTheme.pink]),
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
  const _Glow({required this.size, required this.colors});

  final double size;
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
            colors.first.withOpacity(0.42),
            colors.last.withOpacity(0.24),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
