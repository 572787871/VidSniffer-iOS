import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/download_task.dart';
import '../models/library_folder.dart';
import '../models/local_video.dart';
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
        title: const Text('下载 / 库'),
        actions: [
          IconButton(
            tooltip: '新建文件夹',
            onPressed: () => _createFolder(context),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: '排序',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('排序会按下载时间和文件夹更新时间自动整理')),
              );
            },
            icon: const Icon(Icons.sort_rounded),
          ),
          IconButton(
            tooltip: '清理记录',
            onPressed: () => state.downloadManager.clearHistory(),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final tasks = state.downloadManager.tasks;
          final activeTasks = tasks
              .where((task) =>
                  task.status != DownloadStatus.completed &&
                  task.status != DownloadStatus.canceled)
              .toList(growable: false);
          final completedTasks = tasks
              .where((task) => task.status == DownloadStatus.completed)
              .toList(growable: false);
          if (tasks.isEmpty && state.videos.isEmpty && state.folders.isEmpty) {
            return const EmptyState(
              icon: Icons.downloading_rounded,
              title: '暂无下载内容',
              message: '下载任务、已完成视频和文件夹会统一显示在这里。',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 96),
            children: [
              const _DownloadSegmentBar(),
              const SizedBox(height: 18),
              _SectionTitle(title: '下载中 (${activeTasks.length})'),
              const SizedBox(height: 10),
              if (activeTasks.isEmpty)
                const _InlineHint(text: '暂无正在下载的任务')
              else
                for (final task in activeTasks) ...[
                  _DownloadCard(task: task),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 14),
              _SectionTitle(title: '已完成 (${completedTasks.length})'),
              const SizedBox(height: 10),
              if (completedTasks.isEmpty)
                const _InlineHint(text: '完成后会保留在这里，重启 App 也不会丢失')
              else
                for (final task in completedTasks) ...[
                  _DownloadCard(task: task),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 14),
              _SectionTitle(
                title: '文件库',
                actionLabel: '+ 新建文件夹',
                onAction: () => _createFolder(context),
              ),
              const SizedBox(height: 10),
              _DownloadLibrarySection(
                videos: state.videos,
                folders: state.folders,
                onOpenLibrary: () => state.selectTab(3),
                onDeleteFolder: state.deleteFolder,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createFolder(BuildContext context) async {
    final state = UiStateScope.of(context);
    final name = await _askText(context, title: '新建文件夹', hint: '文件夹名称');
    if (name == null || name.trim().isEmpty) return;
    await state.createFolder(name.trim());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已创建文件夹：${name.trim()}')),
    );
  }

  Future<String?> _askText(
    BuildContext context, {
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

class _DownloadSegmentBar extends StatelessWidget {
  const _DownloadSegmentBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: const [
          Expanded(child: _SegmentPill(label: '下载中', selected: true)),
          Expanded(child: _SegmentPill(label: '已完成')),
          Expanded(child: _SegmentPill(label: '文件库')),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        if (actionLabel != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }
}

class _DownloadLibrarySection extends StatelessWidget {
  const _DownloadLibrarySection({
    required this.videos,
    required this.folders,
    required this.onOpenLibrary,
    required this.onDeleteFolder,
  });

  final List<LocalVideo> videos;
  final List<LibraryFolder> folders;
  final VoidCallback onOpenLibrary;
  final Future<void> Function(LibraryFolder folder) onDeleteFolder;

  @override
  Widget build(BuildContext context) {
    final rows = <_FolderSummary>[
      _FolderSummary(
        name: '全部视频',
        count: videos.length,
        size: videos.fold<int>(0, (sum, item) => sum + item.size),
        updatedAt: _latest(videos),
      ),
      _FolderSummary(
        name: '最近添加',
        count: videos.take(10).length,
        size: videos.take(10).fold<int>(0, (sum, item) => sum + item.size),
        updatedAt: _latest(videos.take(10).toList()),
      ),
      for (final folder in folders)
        _FolderSummary(
          name: folder.name,
          count: videos
              .where((video) => video.folderIds.contains(folder.folderId))
              .length,
          size: videos
              .where((video) => video.folderIds.contains(folder.folderId))
              .fold<int>(0, (sum, item) => sum + item.size),
          updatedAt: folder.updatedAt,
          folder: folder,
        ),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            _FolderRow(
              summary: rows[index],
              onTap: onOpenLibrary,
              onDelete: rows[index].folder == null
                  ? null
                  : () => _confirmDeleteFolder(context, rows[index].folder!),
            ),
            if (index != rows.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  DateTime _latest(List<LocalVideo> values) {
    if (values.isEmpty) return DateTime.now();
    return values
        .map((video) => video.modifiedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  Future<void> _confirmDeleteFolder(
    BuildContext context,
    LibraryFolder folder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${folder.name}”？'),
        content: const Text('这里只删除分类映射，不会删除视频文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onDeleteFolder(folder);
    }
  }
}

class _FolderSummary {
  const _FolderSummary({
    required this.name,
    required this.count,
    required this.size,
    required this.updatedAt,
    this.folder,
  });

  final String name;
  final int count;
  final int size;
  final DateTime updatedAt;
  final LibraryFolder? folder;
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.summary,
    required this.onTap,
    required this.onDelete,
  });

  final _FolderSummary summary;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xff60a5fa), Color(0xff818cf8)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.folder_rounded, color: Colors.white),
      ),
      title: Text(
        summary.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text('${summary.count} 个视频 · ${_dateLabel(summary.updatedAt)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatBytes(summary.size),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('打开')),
              if (onDelete != null)
                const PopupMenuItem(value: 'delete', child: Text('删除文件夹')),
            ],
            onSelected: (value) {
              if (value == 'delete') {
                onDelete?.call();
              } else {
                onTap();
              }
            },
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  String _dateLabel(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${value.month}/${value.day}';
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isCompleted = task.status == DownloadStatus.completed;
    final isFailed = task.status == DownloadStatus.failed;
    final isMissing = task.status == DownloadStatus.missing;
    if (isCompleted) {
      return _CompletedDownloadCard(task: task);
    }
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
                  color: isCompleted
                      ? scheme.primaryContainer
                      : (isFailed || isMissing
                          ? scheme.errorContainer
                          : scheme.secondaryContainer),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isCompleted
                      ? Icons.check_rounded
                      : (isFailed || isMissing
                          ? Icons.error_outline_rounded
                          : Icons.downloading_rounded),
                  color: isCompleted
                      ? scheme.primary
                      : (isFailed || isMissing
                          ? scheme.error
                          : scheme.secondary),
                ),
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
                      '${task.resource.label} · ${_phaseLabel(task)} · ${_percent(task)} · ${task.speed} · ${_remainingLabel(task)}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
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
          Text(
            task.errorMessage.isNotEmpty ? task.errorMessage : task.message,
            style: TextStyle(
              color: isFailed ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
          if (task.resource.isMergeRequired && task.totalSegments > 0) ...[
            const SizedBox(height: 6),
            Text(
              '分片 ${task.downloadedSegments}/${task.totalSegments} · ffmpeg ${task.ffmpegTime} / ${_durationLabel(task.playlistDuration)} · speed ${task.ffmpegSpeed}x · 已用 ${_durationLabel(task.elapsed)}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.preparing ||
                  task.status == DownloadStatus.merging)
                FilledButton.tonalIcon(
                  onPressed: () => state.downloadManager.pause(task),
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('暂停'),
                ),
              if (task.status == DownloadStatus.paused ||
                  task.status == DownloadStatus.failed ||
                  task.status == DownloadStatus.canceled)
                FilledButton.tonalIcon(
                  onPressed: () => state.downloadManager.retry(task),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    task.status == DownloadStatus.failed ? '重试' : '继续',
                  ),
                ),
              if (!isCompleted && !isMissing)
                OutlinedButton.icon(
                  onPressed: () => state.downloadManager.cancel(task),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('取消'),
                ),
              if (isCompleted)
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
                ),
              if (isCompleted && task.localPath.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => Share.shareXFiles([
                    XFile(task.localPath),
                  ], text: task.resource.title),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('分享'),
                ),
              if (task.ffmpegLog.isNotEmpty || task.errorDetails.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _showDetails(context, task),
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('查看详情'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.preparing:
        return '准备中';
      case DownloadStatus.idle:
        return '等待中';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.merging:
        return '合并中';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '失败';
      case DownloadStatus.canceled:
        return '已取消';
      case DownloadStatus.missing:
        return '文件缺失';
    }
  }

  String _phaseLabel(DownloadTask task) {
    switch (task.phase) {
      case DownloadPhase.preparing:
        return '准备中';
      case DownloadPhase.fetchingPlaylist:
        return '获取播放列表';
      case DownloadPhase.downloadingSegments:
        return '下载分片';
      case DownloadPhase.downloadingFile:
        return _statusLabel(task.status);
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

  String _percent(DownloadTask task) {
    if (task.isIndeterminate) return '未知';
    return '${(task.progress.clamp(0, 1) * 100).round()}%';
  }

  String _remainingLabel(DownloadTask task) {
    if (task.status == DownloadStatus.completed) return '剩余 00:00';
    if (task.remaining.trim().isEmpty || task.remaining == '剩余时间未知') {
      return '剩余时间未知';
    }
    return '剩余 ${task.remaining}';
  }

  String _durationLabel(Duration value) {
    if (value == Duration.zero) return '未知';
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _showDetails(BuildContext context, DownloadTask task) {
    final details =
        task.errorDetails.isNotEmpty ? task.errorDetails : task.ffmpegLog;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('任务详情'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(details)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: details));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已复制详情日志')));
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _CompletedDownloadCard extends StatelessWidget {
  const _CompletedDownloadCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.check_rounded, color: scheme.primary),
          ),
          title: Text(
            task.resource.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${task.resource.label} · 已完成 · ${_formatBytes(task.receivedBytes)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
                ),
                if (task.localPath.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => Share.shareXFiles([
                      XFile(task.localPath),
                    ], text: task.resource.title),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('分享'),
                  ),
                if (task.ffmpegLog.isNotEmpty || task.errorDetails.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _showTaskDetails(context, task),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('查看详情'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _showTaskDetails(BuildContext context, DownloadTask task) {
  final details =
      task.errorDetails.isNotEmpty ? task.errorDetails : task.ffmpegLog;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('任务详情'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: SelectableText(details)),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: details));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已复制详情日志')));
          },
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

String _formatBytes(int value) {
  if (value <= 0) return '未知大小';
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}
