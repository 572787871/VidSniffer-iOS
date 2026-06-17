import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';

import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import 'app_state.dart';
import 'video_player_screen.dart';

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
                _FileCard(file: file, directory: state.downloadDirectory, onDelete: () => state.deleteFile(file))
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
  const _FileCard({required this.file, required this.directory, required this.onDelete});

  final LocalVideo file;
  final String directory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openPlayer(context, file),
            child: ClipRRect(
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniAction(icon: LucideIcons.play, label: '播放', onTap: () => _openPlayer(context, file)),
                    _MiniAction(icon: LucideIcons.folderOpen, label: '打开', onTap: () => _openPlayer(context, file)),
                    _MiniAction(icon: LucideIcons.share2, label: '分享', onTap: () => _shareFile(file)),
                    _MiniAction(icon: LucideIcons.upload, label: '导出', onTap: () => _shareFile(file)),
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

  void _openPlayer(BuildContext context, LocalVideo file) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => VideoPlayerScreen(file: file)),
    );
  }

  Future<void> _shareFile(LocalVideo file) async {
    if (file.localPath.isNotEmpty && await File(file.localPath).exists()) {
      await Share.shareXFiles([XFile(file.localPath)], text: file.title);
      return;
    }
    await Share.share('${file.title} · ${file.size}${file.sourceUrl.isEmpty ? '' : ' · ${file.sourceUrl}'}');
  }
}

class _MiniAction extends StatefulWidget {
  const _MiniAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MiniAction> createState() => _MiniActionState();
}

class _MiniActionState extends State<_MiniAction> {
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
        duration: const Duration(milliseconds: 110),
        scale: _pressed ? 0.94 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_pressed ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(widget.label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
