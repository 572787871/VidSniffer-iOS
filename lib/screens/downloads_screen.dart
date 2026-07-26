import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../services/ui_state.dart';
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
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: state,
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
              message: '网页播放时检测到视频后，点击红色下载按钮即可开始下载。',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            itemBuilder: (context, index) => _SwipeToDelete(
              task: tasks[index],
              child: _DownloadCard(task: tasks[index]),
            ),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: tasks.length,
          );
        },
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
        animation: state,
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
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: actionWidth,
                child: Material(
                  color: scheme.errorContainer,
                  child: InkWell(
                    onTap: () => manager.removeTask(widget.task),
                    child: Semantics(
                      button: true,
                      label: '删除下载任务',
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline_rounded),
                          SizedBox(height: 4),
                          Text(
                            '删除',
                            style: TextStyle(fontWeight: FontWeight.w700),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: completed
                      ? scheme.primaryContainer
                      : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  completed
                      ? Icons.check_circle_rounded
                      : Icons.downloading_rounded,
                  color: completed ? scheme.primary : scheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.resource.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: task.isIndeterminate
                ? null
                : task.progress.clamp(0, 1).toDouble(),
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_formatBytes(task.receivedBytes)} / ${task.totalBytes > 0 ? _formatBytes(task.totalBytes) : '未知'}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                _remaining(task),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (task.isActive)
                FilledButton.tonalIcon(
                  onPressed: () => manager.pause(task),
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('暂停'),
                ),
              if (task.status == DownloadStatus.paused)
                FilledButton.tonalIcon(
                  onPressed: () => manager.retry(task),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('继续'),
                ),
              if (task.tempPath.isNotEmpty)
                FutureBuilder<bool>(
                  future: manager.canPreviewPartial(task),
                  builder: (context, snapshot) => OutlinedButton.icon(
                    onPressed: snapshot.data == true
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PlayerScreen(
                                  title: task.resource.title,
                                  filePath: task.resource.isMergeRequired
                                      ? null
                                      : manager.previewPathFor(task),
                                  networkUrl: task.resource.isMergeRequired
                                      ? task.resource.url
                                      : null,
                                  httpHeaders:
                                      manager.playbackHeadersFor(task),
                                  allowPartial: true,
                                ),
                              ),
                            )
                        : null,
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: Text(
                      task.resource.isMergeRequired
                          ? '边下边播'
                          : '播放已下载部分',
                    ),
                  ),
                ),
              if (completed && task.localPath.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        title: task.resource.title,
                        filePath: task.localPath,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => manager.cancel(task),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('取消'),
                ),
            ],
          ),
        ],
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
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: completed ? scheme.primary : scheme.error,
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
                  '${_historyStatus(task.status)} · ${_formatBytes(task.receivedBytes)}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
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
  if (task.isActive || task.status == DownloadStatus.paused) return true;
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
