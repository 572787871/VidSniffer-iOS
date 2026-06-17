import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PillButton extends StatefulWidget {
  const PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        scale: enabled && _pressed ? 0.96 : 1,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 110),
          opacity: enabled ? 1 : 0.55,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: enabled ? AppTheme.accentGradient : null,
              color: enabled ? null : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AppTheme.electricBlue.withOpacity(_pressed ? 0.36 : 0.25),
                        blurRadius: _pressed ? 10 : 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 18, vertical: widget.compact ? 10 : 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: Colors.white),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
