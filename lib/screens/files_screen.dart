import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
            onTap: () => _showPreview(context, file),
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
                    _MiniAction(icon: LucideIcons.play, label: '播放', onTap: () => _showPreview(context, file)),
                    _MiniAction(icon: LucideIcons.folderOpen, label: '打开', onTap: () => _showOpenDetails(context, file)),
                    _MiniAction(icon: LucideIcons.share2, label: '分享', onTap: () => _shareFile(context, file)),
                    _MiniAction(icon: LucideIcons.upload, label: '导出', onTap: () => _showExportNotice(context, file)),
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

  void _showPreview(BuildContext context, LocalVideo file) {
    final hasSource = file.sourceUrl.trim().isNotEmpty;
    final controller = hasSource
        ? (WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..loadRequest(
            Uri.dataFromString(
              '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;height:100%;background:#000}video{width:100%;height:100%;object-fit:contain}</style></head><body><video controls autoplay playsinline src="${file.sourceUrl}"></video></body></html>''',
              mimeType: 'text/html',
            ),
          ))
        : null;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: hasSource && controller != null
                        ? WebViewWidget(controller: controller)
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              CachedNetworkImage(imageUrl: file.thumbnail, fit: BoxFit.cover),
                              Container(color: Colors.black.withOpacity(0.28)),
                              const Center(child: Icon(LucideIcons.playCircle, color: Colors.white, size: 62)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(file.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text('${file.duration} · ${file.size}', style: const TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    borderRadius: BorderRadius.circular(999),
                    color: AppTheme.electricBlue,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭预览', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOpenDetails(BuildContext context, LocalVideo file) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('文件已打开'),
        content: Text('${file.title}\n${file.size}\n存储位置：$directory${file.sourceUrl.isEmpty ? '' : '\n源地址：${file.sourceUrl}'}'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(), child: const Text('完成')),
        ],
      ),
    );
  }

  Future<void> _shareFile(BuildContext context, LocalVideo file) async {
    await Clipboard.setData(ClipboardData(text: '${file.title} · ${file.size}${file.sourceUrl.isEmpty ? '' : ' · ${file.sourceUrl}'}'));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('视频信息已复制，可粘贴到聊天或分享应用'), behavior: SnackBarBehavior.floating),
    );
  }

  void _showExportNotice(BuildContext context, LocalVideo file) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已准备导出：${file.title}'), behavior: SnackBarBehavior.floating),
    );
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
