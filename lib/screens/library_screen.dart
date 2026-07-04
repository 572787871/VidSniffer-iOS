import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/mock_models.dart';
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
      appBar: AppBar(title: const Text('本地视频库')),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          if (state.videos.isEmpty) {
            return const EmptyState(icon: Icons.video_library_outlined, title: '还没有本地视频', message: '下载完成的视频会显示在这里，并能在 iOS 文件 App 中查看。');
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisExtent: 172,
              mainAxisSpacing: 14,
            ),
            itemCount: state.videos.length,
            itemBuilder: (context, index) => _VideoCard(video: state.videos[index]),
          );
        },
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video});

  final MockLocalVideo video;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 116,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xff2563eb), Color(0xff7c3aed)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('${video.size} · ${video.date}', style: TextStyle(color: scheme.onSurfaceVariant)),
                const Spacer(),
                Row(
                  children: [
                    IconButton.filled(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(title: video.title))), icon: const Icon(Icons.play_arrow_rounded)),
                    IconButton.filledTonal(onPressed: () => Share.share('分享视频文件：${video.title}'), icon: const Icon(Icons.ios_share_rounded)),
                    IconButton.outlined(onPressed: () {}, icon: const Icon(Icons.delete_outline_rounded)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
