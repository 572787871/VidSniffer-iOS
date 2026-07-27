import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载中'),
        actions: [
          IconButton(
            tooltip: '历史下载记录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadHistoryScreen(),
              ),
            ),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        // Listen to the task source directly so inserting a new task archives
        // the previously completed card immediately, even while this tab is
        // already mounted in the shell's IndexedStack.
        animation: state.downloadManager,
        builder: (context, _) {
          final tasks = state.downloadManager.tasks
              .where(
                (task) => _showInCurrentDownloads(
                  task,
                  state.downloadManager.tasks,
                ),
              )
              .toList(growable: false);
          if (tasks.isEmpty) {
            return const EmptyState(
              icon: Icons.downloading_rounded,
              title: '暂无下载中任务',
              message: '智能解析或网页检测到视频后，即可选择清晰度开始下载。',
            );
          }
          return Column(
            children: [
              _DownloadSummaryBar(tasks: tasks),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                  itemBuilder: (context, index) => _SwipeToDelete(
                    task: tasks[index],
                    child: _DownloadCard(task: tasks[index]),
                  ),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: tasks.length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DownloadSummaryBar extends StatelessWidget {
  const _DownloadSummaryBar({required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    final manager = UiStateScope.of(context).downloadManager;
    final active = tasks.where((task) => task.isActive).toList(growable: false);
    final paused =
        tasks.where((task) => task.status == DownloadStatus.paused).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.bolt_fill,
                  size: 18,
                  color: AppTheme.blue,
                ),
                const SizedBox(width: 5),
                Text(
                  active.isNotEmpty
                      ? '同时下载 ${active.length} 个任务'
                      : '已暂停 $paused 个任务',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: active.isEmpty
                ? null
                : () async {
                    for (final task in active) {
                      await manager.pause(task);
                    }
                  },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('全部暂停'),
          ),
        ],
      ),
    );
  }
}

class DownloadHistoryScreen extends StatelessWidget {
  const DownloadHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('历史下载记录')),
      body: AnimatedBuilder(
        animation: state.downloadManager,
        builder: (context, _) {
          final tasks = state.downloadManager.tasks
              .where(
                (task) => !_showInCurrentDownloads(
                  task,
                  state.downloadManager.tasks,
                ),
              )
              .toList(growable: false);
          if (tasks.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: '暂无历史下载记录',
              message: '完成、失败或缺失的下载任务会显示在这里。',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            itemBuilder: (context, index) => _SwipeToDelete(
              task: tasks[index],
              child: _HistoryCard(task: tasks[index]),
            ),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: tasks.length,
          );
        },
      ),
    );
  }
}

class _SwipeToDelete extends StatefulWidget {
  const _SwipeToDelete({required this.task, required this.child});

  final DownloadTask task;
  final Widget child;

  @override
  State<_SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<_SwipeToDelete> {
  static const actionWidth = 72.0;
  double offset = 0;
  bool dragging = false;

  @override
  Widget build(BuildContext context) {
    final manager = UiStateScope.of(context).downloadManager;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: actionWidth,
                child: Material(
                  color: AppTheme.red,
                  child: InkWell(
                    onTap: () async {
                      final confirmed = await showCupertinoDialog<bool>(
                        context: context,
                        builder: (dialogContext) => CupertinoAlertDialog(
                          title: const Text('删除下载任务？'),
                          content: const Text('\n任务记录和未完成的临时文件将被删除。'),
                          actions: [
                            CupertinoDialogAction(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('取消'),
                            ),
                            CupertinoDialogAction(
                              isDestructiveAction: true,
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await manager.removeTask(widget.task);
                      }
                      if (mounted) setState(() => offset = 0);
                    },
                    child: Semantics(
                      button: true,
                      label: '删除下载任务',
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.delete,
                            color: Colors.white,
                          ),
                          SizedBox(height: 4),
                          Text(
                            '删除',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: dragging || reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(offset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: offset < 0
                  ? () => setState(() => offset = 0)
                  : null,
              onHorizontalDragStart: (_) => setState(() => dragging = true),
              onHorizontalDragUpdate: (details) {
                setState(
                  () => offset =
                      (offset + details.delta.dx)
                          .clamp(-actionWidth, 0)
                          .toDouble(),
                );
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  dragging = false;
                  offset = offset <= -actionWidth * 0.38 ? -actionWidth : 0;
                });
              },
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final manager = UiStateScope.of(context).downloadManager;
    final scheme = Theme.of(context).colorScheme;
    final completed = task.status == DownloadStatus.completed;
    final progress =
        task.isIndeterminate ? null : task.progress.clamp(0, 1).toDouble();
    final percent = progress == null ? '--' : '${(progress * 100).round()}%';
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaskArtwork(task: task, width: 88, height: 132),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.resource.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _MetadataTag(
                      label: _qualityLabel(task),
                      color: scheme.primary,
                    ),
                    _MetadataTag(
                      label: task.resource.displayFormat,
                      color: scheme.onSurfaceVariant,
                    ),
                    if (task.status == DownloadStatus.merging)
                      const _MetadataTag(
                        label: '合并中',
                        color: Color(0xff7c4dff),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  '${_formatBytes(task.receivedBytes)} / ${task.totalBytes > 0 ? _formatBytes(task.totalBytes) : '大小未知'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 34,
                      child: Text(
                        percent,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.speed == '--' ? _statusLabel(task) : task.speed,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Text(
                      _remaining(task),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (task.tempPath.isNotEmpty)
                      FutureBuilder<bool>(
                        future: manager.canPreviewPartial(task),
                        builder: (context, snapshot) => IconButton.outlined(
                          tooltip: '边下边播',
                          onPressed: snapshot.data == true
                              ? () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PlayerScreen(
                                        title: task.resource.title,
                                        filePath: manager.previewPathFor(task),
                                        allowPartial: true,
                                        downloadTask: task,
                                        downloadManager: manager,
                                      ),
                                    ),
                                  )
                              : null,
                          icon: const Icon(
                            Icons.play_circle_outline_rounded,
                            size: 21,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (task.isActive)
                      IconButton.filledTonal(
                        tooltip: '暂停',
                        onPressed: () => manager.pause(task),
                        icon: const Icon(Icons.pause_rounded, size: 21),
                      )
                    else if (task.status == DownloadStatus.paused)
                      IconButton.filledTonal(
                        tooltip: '继续',
                        onPressed: () => manager.retry(task),
                        icon: const Icon(Icons.play_arrow_rounded, size: 21),
                      )
                    else if (completed && task.localPath.isNotEmpty)
                      IconButton.filled(
                        tooltip: '播放',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PlayerScreen(
                              title: task.resource.title,
                              filePath: task.localPath,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 21),
                      ),
                    if (!completed) ...[
                      const SizedBox(width: 5),
                      IconButton(
                        tooltip: '取消',
                        onPressed: () => manager.cancel(task),
                        icon: const Icon(Icons.close_rounded, size: 21),
                      ),
                    ],
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

class _TaskArtwork extends StatelessWidget {
  const _TaskArtwork({
    required this.task,
    this.width = 72,
    this.height = 72,
  });

  final DownloadTask task;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbnailFile =
        task.thumbnailPath.isEmpty ? null : File(task.thumbnailPath);
    final headers = <String, String>{
      if (task.resource.referer.isNotEmpty)
        'Referer': task.resource.referer,
      if (task.resource.userAgent.isNotEmpty)
        'User-Agent': task.resource.userAgent,
      if (task.resource.cookie.isNotEmpty) 'Cookie': task.resource.cookie,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailFile != null && thumbnailFile.existsSync())
              Image.file(thumbnailFile, fit: BoxFit.cover)
            else if (task.resource.thumbnailUrl.isNotEmpty)
              Image.network(
                task.resource.thumbnailUrl,
                headers: headers,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _ArtworkPlaceholder(color: scheme.primary),
              )
            else
              _ArtworkPlaceholder(color: scheme.primary),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.32),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  task.status == DownloadStatus.completed
                      ? Icons.check_rounded
                      : Icons.arrow_downward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color.withValues(alpha: 0.1),
      child: Icon(
        Icons.movie_creation_outlined,
        color: color.withValues(alpha: 0.72),
        size: 28,
      ),
    );
  }
}

class _MetadataTag extends StatelessWidget {
  const _MetadataTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final manager = UiStateScope.of(context).downloadManager;
    final scheme = Theme.of(context).colorScheme;
    final completed = task.status == DownloadStatus.completed;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _TaskArtwork(task: task),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.resource.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${_historyStatus(task.status)} · ${_formatBytes(task.receivedBytes)}',
                  style: TextStyle(
                    color: completed
                        ? scheme.onSurfaceVariant
                        : scheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (completed && task.localPath.isNotEmpty)
            IconButton(
              tooltip: '播放',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerScreen(
                    title: task.resource.title,
                    filePath: task.localPath,
                  ),
                ),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
            )
          else
            IconButton(
              tooltip: '重新下载',
              onPressed: task.canRetry ? () => manager.retry(task) : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }
}

String _qualityLabel(DownloadTask task) {
  final quality = task.resource.quality.trim();
  if (quality.isEmpty || quality == '未知') return '自动';
  return quality;
}

String _statusLabel(DownloadTask task) {
  switch (task.status) {
    case DownloadStatus.preparing:
      return '准备中';
    case DownloadStatus.downloading:
      return '下载中';
    case DownloadStatus.paused:
      return '已暂停';
    case DownloadStatus.merging:
      return '正在合并';
    case DownloadStatus.completed:
      return '已完成';
    case DownloadStatus.failed:
      return '下载失败';
    case DownloadStatus.canceled:
      return '已取消';
    case DownloadStatus.missing:
      return '文件缺失';
    case DownloadStatus.idle:
      return '等待中';
  }
}

String _remaining(DownloadTask task) {
  if (task.remaining.isEmpty || task.remaining == '剩余时间未知') {
    return '剩余时间未知';
  }
  return '剩余 ${task.remaining}';
}

bool _showInCurrentDownloads(
  DownloadTask task,
  List<DownloadTask> allTasks,
) {
  if (task.isActive ||
      task.status == DownloadStatus.paused ||
      task.status == DownloadStatus.idle) {
    return true;
  }
  if (task.status != DownloadStatus.completed ||
      task.completedAt == null) {
    return false;
  }
  return !allTasks.any(
    (item) =>
        item.id != task.id && item.createdAt.isAfter(task.completedAt!),
  );
}

String _historyStatus(DownloadStatus status) {
  switch (status) {
    case DownloadStatus.completed:
      return '已完成';
    case DownloadStatus.failed:
      return '失败';
    case DownloadStatus.canceled:
      return '已取消';
    case DownloadStatus.missing:
      return '文件缺失';
    case DownloadStatus.paused:
      return '已暂停';
    case DownloadStatus.idle:
      return '等待中';
    case DownloadStatus.preparing:
    case DownloadStatus.downloading:
    case DownloadStatus.merging:
      return '下载中';
  }
}

String _formatBytes(int value) {
  if (value <= 0) return '0 B';
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
