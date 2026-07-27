import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GradientButton extends StatelessWidget {
  const GradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.expanded = true,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.blue,
        disabledBackgroundColor:
            Theme.of(context).disabledColor.withValues(alpha: 0.16),
        shadowColor: Colors.transparent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
