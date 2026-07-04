import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/local_video.dart';
import '../services/ui_state.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import 'player_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地视频库'),
        actions: [
          IconButton(
            onPressed: state.refreshLibrary,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          if (state.videos.isEmpty) {
            return const EmptyState(
              icon: Icons.video_library_outlined,
              title: '还没有本地视频',
              message: '下载完成的视频会显示在这里，并能在 iOS 文件 App 中查看。',
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisExtent: 172,
              mainAxisSpacing: 14,
            ),
            itemCount: state.videos.length,
            itemBuilder: (context, index) =>
                _VideoCard(video: state.videos[index]),
          );
        },
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video});

  final LocalVideo video;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 116,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff2563eb), Color(0xff7c3aed)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatBytes(video.size)} · ${_formatDate(video.modifiedAt)}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                Row(
                  children: [
                    IconButton.filled(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlayerScreen(
                            title: video.name,
                            filePath: video.path,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => Share.shareXFiles([
                        XFile(video.path),
                      ], text: video.name),
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                    IconButton.outlined(
                      onPressed: () => state.deleteVideo(video),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}
