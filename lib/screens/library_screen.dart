import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../models/download_task.dart';
import '../models/local_video.dart';
import '../services/ui_state.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import 'player_screen.dart';
import 'resource_preview_screen.dart';

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
          final activeTasks = state.downloadManager.tasks
              .where((task) =>
                  task.isActive || task.status == DownloadStatus.paused)
              .toList();
          final entries = _filteredEntries(state.videos);
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
                child: entries.isEmpty && activeTasks.isEmpty
                    ? const EmptyState(
                        icon: Icons.video_library_outlined,
                        title: '还没有本地视频',
                        message: '下载中和下载完成的视频都会显示在这里。',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                        itemBuilder: (context, index) {
                          if (index < activeTasks.length) {
                            return _DownloadPreviewCard(
                                task: activeTasks[index]);
                          }
                          final entry = entries[index - activeTasks.length];
                          if (entry.videos.length == 1) {
                            return _VideoCard(video: entry.videos.first);
                          }
                          return _CollectionCard(entry: entry);
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: activeTasks.length + entries.length,
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

  List<_LibraryEntry> _filteredEntries(List<LocalVideo> values) {
    final videos = _filteredVideos(values);
    final groups = <String, List<LocalVideo>>{};
    for (final video in videos) {
      groups.putIfAbsent(p.dirname(video.path), () => []).add(video);
    }
    final entries = groups.entries
        .map(
            (entry) => _LibraryEntry(directory: entry.key, videos: entry.value))
        .toList();
    switch (sort) {
      case _LibrarySort.newest:
        entries.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      case _LibrarySort.size:
        entries.sort((a, b) => b.size.compareTo(a.size));
      case _LibrarySort.duration:
        entries.sort((a, b) => b.duration.compareTo(a.duration));
      case _LibrarySort.name:
        entries.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return entries;
  }
}

class _LibraryEntry {
  const _LibraryEntry({required this.directory, required this.videos});

  final String directory;
  final List<LocalVideo> videos;

  String get title => p.basename(directory);
  int get size => videos.fold(0, (sum, video) => sum + video.size);
  Duration get duration => videos.fold(
        Duration.zero,
        (sum, video) => sum + video.duration,
      );
  DateTime get modifiedAt => videos
      .map((video) => video.modifiedAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

class _DownloadPreviewCard extends StatelessWidget {
  const _DownloadPreviewCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final percent = task.isIndeterminate
        ? '--'
        : '${(task.progress.clamp(0, 1) * 100).round()}%';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.downloading_rounded, color: scheme.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.resource.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_phaseLabel(task)} · $percent · ${_formatBytes(task.receivedBytes)} / ${task.totalBytes > 0 ? _formatBytes(task.totalBytes) : '未知'}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: task.isIndeterminate
                ? null
                : task.progress.clamp(0, 1).toDouble(),
            minHeight: 7,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 10),
          FutureBuilder<bool>(
            future: state.downloadManager.canPreviewPartial(task),
            builder: (context, snapshot) {
              final canPreview = snapshot.data == true;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: canPreview
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ResourcePreviewScreen.file(
                                  filePath: state.downloadManager
                                      .previewPathFor(task),
                                  title: task.resource.title,
                                  subtitle: '${_phaseLabel(task)} · $percent',
                                ),
                              ),
                            )
                        : null,
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('预览已下载部分'),
                  ),
                  if (!canPreview)
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('当前片段暂不可预览')),
                        );
                      },
                      child: const Text('暂不可预览'),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _phaseLabel(DownloadTask task) {
    switch (task.phase) {
      case DownloadPhase.preparing:
        return '准备中';
      case DownloadPhase.fetchingPlaylist:
        return '获取播放列表';
      case DownloadPhase.downloadingSegments:
        return task.totalSegments > 0
            ? '分片 ${task.downloadedSegments}/${task.totalSegments}'
            : '下载分片';
      case DownloadPhase.downloadingFile:
        return '下载中';
      case DownloadPhase.merging:
        return '合并中';
      case DownloadPhase.completed:
        return '已完成';
      case DownloadPhase.failed:
        return '失败';
      case DownloadPhase.canceled:
        return '已取消';
    }
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.entry});

  final _LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return AppCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: true,
        leading: const Icon(Icons.folder_rounded),
        title: Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle:
            Text('${entry.videos.length} 个视频 · ${_formatBytes(entry.size)}'),
        trailing: IconButton(
          tooltip: '删除合集',
          onPressed: () => state.deleteCollection(entry.directory),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
        children: [
          for (final video in entry.videos)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _VideoInlineRow(video: video),
            ),
        ],
      ),
    );
  }
}

class _VideoInlineRow extends StatelessWidget {
  const _VideoInlineRow({required this.video});

  final LocalVideo video;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _Thumbnail(video: video),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title.isEmpty ? video.name : video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  '${video.resolutionLabel} · ${_formatDuration(video.duration)} · ${_formatBytes(video.size)}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
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
