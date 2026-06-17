import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';

import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import 'app_state.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            const Text('本地视频', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('播放、分享、删除或导出到 iOS 文件 App', style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 20),
            if (state.files.isEmpty)
              const GlassCard(
                child: EmptyState(title: '还没有本地视频', message: '完成下载后，视频会自动出现在这里。', icon: LucideIcons.folderOpen),
              )
            else
              for (final file in state.files)
                _FileCard(file: file, onDelete: () => state.deleteFile(file))
                    .animate()
                    .fadeIn(duration: 220.ms)
                    .slideY(begin: 0.05, end: 0),
          ],
        );
      },
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, required this.onDelete});

  final LocalVideo file;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 92,
              height: 70,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: file.thumbnail,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: AppTheme.panelStrong),
                    errorWidget: (context, url, error) => Container(
                      decoration: const BoxDecoration(gradient: AppTheme.accentGradient),
                      child: const Icon(LucideIcons.video),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.18)),
                    child: const Center(child: Icon(LucideIcons.playCircle, color: Colors.white, size: 30)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('${file.duration} · ${file.size}', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniAction(icon: LucideIcons.play, label: '播放', onTap: () {}),
                    _MiniAction(icon: LucideIcons.share2, label: '分享', onTap: () {}),
                    _MiniAction(icon: LucideIcons.upload, label: '导出', onTap: () {}),
                  ],
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 38,
            onPressed: onDelete,
            child: const Icon(LucideIcons.trash2, color: Color(0xffff6b7a), size: 20),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        minSize: 0,
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
