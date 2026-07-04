import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/local_video.dart';
import '../services/ui_state.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import 'player_screen.dart';

enum _LibrarySort { newest, size, duration, name }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final searchController = TextEditingController();
  _LibrarySort sort = _LibrarySort.newest;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地视频库'),
        actions: [
          PopupMenuButton<_LibrarySort>(
            initialValue: sort,
            onSelected: (value) => setState(() => sort = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _LibrarySort.newest, child: Text('最新')),
              PopupMenuItem(value: _LibrarySort.size, child: Text('大小')),
              PopupMenuItem(value: _LibrarySort.duration, child: Text('时长')),
              PopupMenuItem(value: _LibrarySort.name, child: Text('文件名')),
            ],
            icon: const Icon(Icons.sort_rounded),
          ),
          IconButton(
            onPressed: state.refreshLibrary,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final videos = _filteredVideos(state.videos);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                child: TextField(
                  controller: searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: '搜索标题或文件名',
                  ),
                ),
              ),
              Expanded(
                child: videos.isEmpty
                    ? const EmptyState(
                        icon: Icons.video_library_outlined,
                        title: '还没有本地视频',
                        message: '下载完成的视频会显示在这里，并自动生成真实封面。',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                        itemBuilder: (context, index) =>
                            _VideoCard(video: videos[index]),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: videos.length,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<LocalVideo> _filteredVideos(List<LocalVideo> values) {
    final query = searchController.text.trim().toLowerCase();
    final filtered = values.where((video) {
      if (query.isEmpty) return true;
      return video.title.toLowerCase().contains(query) ||
          video.name.toLowerCase().contains(query);
    }).toList();
    switch (sort) {
      case _LibrarySort.newest:
        filtered.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      case _LibrarySort.size:
        filtered.sort((a, b) => b.size.compareTo(a.size));
      case _LibrarySort.duration:
        filtered.sort((a, b) => b.duration.compareTo(a.duration));
      case _LibrarySort.name:
        filtered.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return filtered;
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
          _Thumbnail(video: video),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        video.title.isEmpty ? video.name : video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: video.isFavorite ? '取消收藏' : '收藏',
                      onPressed: () => state.toggleFavorite(video),
                      icon: Icon(
                        video.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color:
                            video.isFavorite ? const Color(0xffffb703) : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${video.resolutionLabel} · ${_formatDuration(video.duration)} · ${_formatBytes(video.size)}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                if (video.resumePosition > Duration.zero) ...[
                  const SizedBox(height: 4),
                  Text(
                    '继续观看 ${_formatDuration(video.resumePosition)}',
                    style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ],
                const Spacer(),
                Row(
                  children: [
                    IconButton.filled(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlayerScreen(
                            title:
                                video.title.isEmpty ? video.name : video.title,
                            filePath: video.path,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => Share.shareXFiles([
                        XFile(video.path),
                      ], text: video.title.isEmpty ? video.name : video.title),
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

  String _subtitle() {
    final parts = <String>[
      _formatDate(video.modifiedAt),
      if (video.codec.isNotEmpty) video.codec,
      if (video.sourceSite.isNotEmpty) video.sourceSite,
    ];
    return parts.join(' · ');
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.video});

  final LocalVideo video;

  @override
  Widget build(BuildContext context) {
    final file = video.thumbnailPath.isEmpty ? null : File(video.thumbnailPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 138,
        height: 92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file != null && file.existsSync())
              Image.file(file, fit: BoxFit.cover)
            else
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.movie_creation_outlined)),
              ),
            Positioned(
              right: 6,
              top: 6,
              child: _OverlayPill(text: video.resolutionLabel),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: _OverlayPill(text: _formatDuration(video.duration)),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _formatBytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

String _formatDuration(Duration value) {
  if (value == Duration.zero) return '--:--';
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _formatDate(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
