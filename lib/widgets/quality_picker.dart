import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';

import '../screens/app_state.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

Future<VideoQualityOption?> showQualityPicker(
  BuildContext context, {
  required AppState state,
  required VideoResource resource,
}) {
  final options = state.qualityOptionsFor(resource);
  return showCupertinoModalPopup<VideoQualityOption>(
    context: context,
    builder: (context) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(gradient: AppTheme.accentGradient, borderRadius: BorderRadius.circular(15)),
                      child: const Icon(LucideIcons.download, color: Colors.white, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('选择下载画质', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text(resource.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (final option in options)
                  _QualityOptionTile(
                    option: option,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withOpacity(0.08),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _QualityOptionTile extends StatefulWidget {
  const _QualityOptionTile({required this.option, required this.onTap});

  final VideoQualityOption option;
  final VoidCallback onTap;

  @override
  State<_QualityOptionTile> createState() => _QualityOptionTileState();
}

class _QualityOptionTileState extends State<_QualityOptionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 0.985 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_pressed ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.video, color: AppTheme.electricBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.option.label, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              Text('${widget.option.format.toUpperCase()} · ${widget.option.size}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
