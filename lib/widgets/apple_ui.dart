import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Press feedback that begins on touch-down and remains interruptible.
class ApplePressable extends StatefulWidget {
  const ApplePressable({
    required this.child,
    required this.onPressed,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final BorderRadius borderRadius;
  final String? semanticLabel;

  @override
  State<ApplePressable> createState() => _ApplePressableState();
}

class _ApplePressableState extends State<ApplePressable> {
  bool pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed == null || pressed == value) return;
    setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final content = AnimatedScale(
      scale: pressed ? 0.975 : 1,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: pressed ? 0.72 : 1,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
    return Semantics(
      button: widget.onPressed != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onPressed,
        child: content,
      ),
    );
  }
}

class AppleSectionHeader extends StatelessWidget {
  const AppleSectionHeader({
    required this.title,
    this.action,
    this.onAction,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (action != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(36, 36),
              onPressed: onAction,
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class AppleListGroup extends StatelessWidget {
  const AppleListGroup({
    required this.children,
    this.footer,
    super.key,
  });

  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final separator = Theme.of(context).dividerColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index < children.length - 1)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 56,
                      color: separator,
                    ),
                ],
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
            child: Text(
              footer!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class AppleIconTile extends StatelessWidget {
  const AppleIconTile({
    required this.icon,
    required this.color,
    this.size = 30,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.62),
    );
  }
}

class AppleListTile extends StatelessWidget {
  const AppleListTile({
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = AppTheme.blue,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading:
          icon == null ? null : AppleIconTile(icon: icon!, color: iconColor),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ??
          (onTap == null
              ? null
              : const Icon(
                  CupertinoIcons.chevron_forward,
                  size: 17,
                  color: CupertinoColors.systemGrey,
                )),
    );
  }
}
