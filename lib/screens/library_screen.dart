import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../models/download_task.dart';
import '../models/library_folder.dart';
import '../models/local_video.dart';
import '../services/ui_state.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import 'player_screen.dart';

enum _LibrarySort { newest, size, duration, name }

enum _LibraryView { all, recent, folders, sites, favorites }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final searchController = TextEditingController();
  final searchFocus = FocusNode();
  _LibrarySort sort = _LibrarySort.newest;
  _LibraryView view = _LibraryView.folders;

  @override
  void dispose() {
    searchController.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('已下载'),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: searchFocus.requestFocus,
            icon: const Icon(Icons.search_rounded),
          ),
          PopupMenuButton<_LibrarySort>(
            initialValue: sort,
            onSelected: (value) => setState(() => sort = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _LibrarySort.newest, child: Text('最新')),
              PopupMenuItem(value: _LibrarySort.size, child: Text('大小')),
              PopupMenuItem(value: _LibrarySort.duration, child: Text('时长')),
              PopupMenuItem(value: _LibrarySort.name, child: Text('文件名')),
            ],
            icon: const Icon(Icons.sort_by_alpha_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: state.refreshLibrary,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建文件夹',
        onPressed: () => _createFolder(context),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          // “已下载”只展示已经落盘并被媒体库扫描到的视频。
          const activeTasks = <DownloadTask>[];
          final videos = _filteredVideos(state.videos);
          final entries = _filteredEntries(state.videos);
          final folderEntries = _folderEntries(state, videos);
          final siteEntries = _siteEntries(videos);
          final visibleVideos = view == _LibraryView.favorites
              ? videos.where((item) => item.isFavorite).toList()
              : videos;
          return Column(
            children: [
              SizedBox(
                height: 46,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ViewChip(
                      label: '全部 ${state.videos.length}',
                      selected: view == _LibraryView.all,
                      onSelected: () => setState(() => view = _LibraryView.all),
                    ),
                    _ViewChip(
                      label: '最近下载',
                      selected: view == _LibraryView.recent,
                      onSelected: () =>
                          setState(() => view = _LibraryView.recent),
                    ),
                    _ViewChip(
                      label: '文件夹 ${folderEntries.length}',
                      selected: view == _LibraryView.folders,
                      onSelected: () =>
                          setState(() => view = _LibraryView.folders),
                    ),
                    _ViewChip(
                      label: '来源网站 ${siteEntries.length}',
                      selected: view == _LibraryView.sites,
                      onSelected: () =>
                          setState(() => view = _LibraryView.sites),
                    ),
                    _ViewChip(
                      label: '收藏 ${state.videos.where((item) => item.isFavorite).length}',
                      selected: view == _LibraryView.favorites,
                      onSelected: () =>
                          setState(() => view = _LibraryView.favorites),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                child: TextField(
                  controller: searchController,
                  focusNode: searchFocus,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: '搜索标题或文件名',
                  ),
                ),
              ),
              Expanded(
                child: _isEmptyForView(
                  activeTasks: activeTasks,
                  entries: entries,
                  videos: visibleVideos,
                  folders: folderEntries,
                  sites: siteEntries,
                )
                    ? const EmptyState(
                        icon: Icons.folder_outlined,
                        title: '还没有已下载视频',
                        message: '下载完成的视频会在这里显示和播放。',
                      )
                    : _buildListForView(
                        activeTasks,
                        entries,
                        visibleVideos,
                        folderEntries,
                        siteEntries,
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

  bool _isEmptyForView({
    required List<DownloadTask> activeTasks,
    required List<_LibraryEntry> entries,
    required List<LocalVideo> videos,
    required List<_FolderEntry> folders,
    required List<_FolderEntry> sites,
  }) {
    switch (view) {
      case _LibraryView.all:
        return entries.isEmpty && activeTasks.isEmpty;
      case _LibraryView.recent:
      case _LibraryView.favorites:
        return videos.isEmpty && activeTasks.isEmpty;
      case _LibraryView.folders:
        return folders.isEmpty && videos.isEmpty;
      case _LibraryView.sites:
        return sites.isEmpty;
    }
  }

  Widget _buildListForView(
    List<DownloadTask> activeTasks,
    List<_LibraryEntry> entries,
    List<LocalVideo> videos,
    List<_FolderEntry> folders,
    List<_FolderEntry> sites,
  ) {
    switch (view) {
      case _LibraryView.all:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
          itemBuilder: (context, index) {
            if (index < activeTasks.length) {
              return _DownloadPreviewCard(task: activeTasks[index]);
            }
            final entry = entries[index - activeTasks.length];
            if (entry.videos.length == 1) {
              return _VideoCard(video: entry.videos.first);
            }
            return _CollectionCard(entry: entry);
          },
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: activeTasks.length + entries.length,
        );
      case _LibraryView.recent:
      case _LibraryView.favorites:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
          itemBuilder: (context, index) {
            if (index < activeTasks.length && view == _LibraryView.recent) {
              return _DownloadPreviewCard(task: activeTasks[index]);
            }
            final offset = view == _LibraryView.recent ? activeTasks.length : 0;
            return _VideoCard(video: videos[index - offset]);
          },
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: (view == _LibraryView.recent ? activeTasks.length : 0) +
              videos.length,
        );
      case _LibraryView.folders:
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
          children: [
            _AllVideosCard(
              videos: videos,
              onTap: () => setState(() => view = _LibraryView.all),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '文件夹',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _createFolder(context),
                  icon: const Icon(Icons.create_new_folder_rounded, size: 19),
                  label: const Text('新建'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.18,
              ),
              itemBuilder: (context, index) =>
                  _FolderGridCard(entry: folders[index]),
              itemCount: folders.length,
            ),
          ],
        );
      case _LibraryView.sites:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
          itemBuilder: (context, index) => _FolderCard(entry: sites[index]),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: sites.length,
        );
    }
  }

  List<_FolderEntry> _folderEntries(UiState state, List<LocalVideo> videos) {
    final entries = state.folders.map((folder) {
      final folderVideos = videos
          .where((video) => video.folderIds.contains(folder.folderId))
          .toList();
      return _FolderEntry(folder: folder, videos: folderVideos);
    }).toList();
    final byDirectory = <String, List<LocalVideo>>{};
    for (final video in videos) {
      if (video.folderIds.isNotEmpty) continue;
      byDirectory.putIfAbsent(p.dirname(video.path), () => []).add(video);
    }
    final now = DateTime.now();
    for (final entry in byDirectory.entries) {
      final first = entry.value.first;
      final pageKey = first.pageUrlHash.isNotEmpty
          ? first.pageUrlHash
          : p.basename(entry.key);
      entries.add(
        _FolderEntry(
          folder: LibraryFolder(
            folderId: 'page:$pageKey',
            name: p.basename(entry.key),
            type: LibraryFolderType.page,
            createdAt: now,
            updatedAt: now,
          ),
          videos: entry.value,
        ),
      );
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  List<_FolderEntry> _siteEntries(List<LocalVideo> videos) {
    final groups = <String, List<LocalVideo>>{};
    for (final video in videos) {
      final site = video.sourceSite.trim();
      if (site.isEmpty) continue;
      groups.putIfAbsent(site, () => []).add(video);
    }
    final now = DateTime.now();
    final entries = groups.entries
        .map(
          (entry) => _FolderEntry(
            folder: LibraryFolder(
              folderId: 'site:${entry.key}',
              name: entry.key,
              type: LibraryFolderType.site,
              createdAt: now,
              updatedAt: now,
            ),
            videos: entry.value,
          ),
        )
        .toList();
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  Future<void> _createFolder(BuildContext context) async {
    final name = await _askText(context, title: '新建文件夹', label: '文件夹名称');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await UiStateScope.of(context).createFolder(name);
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

class _FolderEntry {
  const _FolderEntry({required this.folder, required this.videos});

  final LibraryFolder folder;
  final List<LocalVideo> videos;

  String get title => folder.name;
  int get size => videos.fold(0, (sum, video) => sum + video.size);
  DateTime get updatedAt {
    if (videos.isEmpty) return folder.updatedAt;
    return videos
        .map((video) => video.modifiedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _AllVideosCard extends StatelessWidget {
  const _AllVideosCard({required this.videos, required this.onTap});

  final List<LocalVideo> videos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final previews = videos.take(3).toList();
    return Material(
      color: const Color(0xff1769f6),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 150,
          child: Stack(
            children: [
              Positioned(
                right: -16,
                bottom: -20,
                child: Row(
                  children: [
                    for (var index = 0; index < previews.length; index++)
                      Transform.translate(
                        offset: Offset(index * -18, index.isEven ? 10 : -2),
                        child: Transform.rotate(
                          angle: (index - 1) * 0.07,
                          child: Container(
                            width: 84,
                            height: 112,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: _Thumbnail(
                                video: previews[index],
                                width: 78,
                                height: 106,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 20,
                top: 23,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '全部视频',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${videos.length} 个视频',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 18),
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0x33ffffff),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderGridCard extends StatelessWidget {
  const _FolderGridCard({required this.entry});

  final _FolderEntry entry;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    final previews = entry.videos.take(3).toList();
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _FolderDetailScreen(entry: entry),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_rounded,
                color: Color(0xffffb81c),
                size: 27,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (entry.folder.type == LibraryFolderType.manual)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  onSelected: (value) async {
                    if (value == 'rename') {
                      final name = await _askText(
                        context,
                        title: '重命名文件夹',
                        label: '文件夹名称',
                        initialValue: entry.folder.name,
                      );
                      if (name != null && context.mounted) {
                        await state.renameFolder(entry.folder, name);
                      }
                    } else if (value == 'delete') {
                      final ok = await _confirm(
                        context,
                        title: '删除文件夹',
                        message: '视频会保留在“全部视频”中。',
                      );
                      if (ok == true && context.mounted) {
                        await state.deleteFolder(entry.folder);
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除文件夹')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                for (var index = 0; index < 3; index++) ...[
                  Expanded(
                    child: index < previews.length
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _Thumbnail(
                              video: previews[index],
                              width: 60,
                              height: 58,
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: const Color(0xfff2f4f8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.video_library_outlined,
                              size: 18,
                              color: Color(0xffadb3bf),
                            ),
                          ),
                  ),
                  if (index < 2) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${entry.videos.length} 个视频',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.entry});

  final _FolderEntry entry;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _FolderDetailScreen(entry: entry),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xfffff5dc),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.folder_rounded,
              color: Color(0xffffbd2e),
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '${entry.videos.length} 个视频 · ${_formatBytes(entry.size)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '更新 ${_formatDate(entry.updatedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (entry.folder.type == LibraryFolderType.manual)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'rename') {
                  final name = await _askText(
                    context,
                    title: '重命名文件夹',
                    label: '文件夹名称',
                    initialValue: entry.folder.name,
                  );
                  if (name != null && context.mounted) {
                    await state.renameFolder(entry.folder, name);
                  }
                } else if (value == 'delete') {
                  if (!context.mounted) return;
                  final ok = await _confirm(
                    context,
                    title: '删除文件夹',
                    message: '只删除分类映射，不删除视频文件。',
                  );
                  if (ok == true && context.mounted) {
                    await state.deleteFolder(entry.folder);
                  }
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除文件夹')),
              ],
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class _FolderDetailScreen extends StatelessWidget {
  const _FolderDetailScreen({required this.entry});

  final _FolderEntry entry;

  @override
  Widget build(BuildContext context) {
    final videos = entry.videos.toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: videos.isEmpty
          ? const EmptyState(
              icon: Icons.folder_open_rounded,
              title: '文件夹为空',
              message: '可以在视频卡片里选择“移动到文件夹”。',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              itemBuilder: (context, index) => _VideoCard(video: videos[index]),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: videos.length,
            ),
    );
  }
}

Future<void> _showMoveToFolder(
  BuildContext context,
  LocalVideo video,
) async {
  final state = UiStateScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.create_new_folder_rounded),
            title: const Text('新建文件夹'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final name = await _askText(
                context,
                title: '新建文件夹',
                label: '文件夹名称',
              );
              if (name == null || name.trim().isEmpty || !context.mounted) {
                return;
              }
              final folder = await state.createFolder(name);
              await state.moveVideoToFolder(video, folder);
            },
          ),
          for (final folder in state.folders)
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(folder.name),
              trailing: video.folderIds.contains(folder.folderId)
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                await state.moveVideoToFolder(video, folder);
              },
            ),
          if (state.folders.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Text('还没有自定义文件夹。'),
            ),
        ],
      ),
    ),
  );
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
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
                                builder: (_) => PlayerScreen(
                                  filePath: state.downloadManager
                                      .previewPathFor(task),
                                  title: task.resource.title,
                                  allowPartial: true,
                                  downloadTask: task,
                                  downloadManager: state.downloadManager,
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          _Thumbnail(video: video, width: 88, height: 72),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title.isEmpty ? video.name : video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${video.resolutionLabel} · ${_formatDuration(video.duration)} · ${_formatBytes(video.size)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '播放',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlayerScreen(
                  title: video.title.isEmpty ? video.name : video.title,
                  filePath: video.path,
                ),
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'share') {
                await Share.shareXFiles(
                  [XFile(video.path)],
                  text: video.title.isEmpty ? video.name : video.title,
                );
              } else if (value == 'move' && context.mounted) {
                await _showMoveToFolder(context, video);
              } else if (value == 'delete' && context.mounted) {
                await _confirmDeleteVideo(context, state, video);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'share', child: Text('分享')),
              PopupMenuItem(value: 'move', child: Text('移动到文件夹')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
            icon: const Icon(Icons.more_vert_rounded),
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            title: video.title.isEmpty ? video.name : video.title,
            filePath: video.path,
          ),
        ),
      ),
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          _Thumbnail(video: video, width: 104, height: 94),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cleanDisplayTitle(
                    video.title.isEmpty ? video.name : video.title,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    _LibraryTag(
                      label: video.resolutionLabel,
                      highlighted: true,
                    ),
                    _LibraryTag(label: p.extension(video.name).isEmpty
                        ? '视频'
                        : p.extension(video.name).substring(1).toUpperCase()),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  '${_formatBytes(video.size)} · ${_formatDate(video.modifiedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
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
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) async {
              switch (value) {
                case 'play':
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        title: video.title.isEmpty ? video.name : video.title,
                        filePath: video.path,
                      ),
                    ),
                  );
                case 'favorite':
                  await state.toggleFavorite(video);
                case 'share':
                  await Share.shareXFiles(
                    [XFile(video.path)],
                    text: video.title.isEmpty ? video.name : video.title,
                  );
                case 'move':
                  if (context.mounted) {
                    await _showMoveToFolder(context, video);
                  }
                case 'delete':
                  if (context.mounted) {
                    await _confirmDeleteVideo(context, state, video);
                  }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'play', child: Text('播放')),
              PopupMenuItem(
                value: 'favorite',
                child: Text(video.isFavorite ? '取消收藏' : '收藏'),
              ),
              const PopupMenuItem(value: 'share', child: Text('分享')),
              const PopupMenuItem(value: 'move', child: Text('移动到文件夹')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
            icon: Icon(
              Icons.more_vert_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTag extends StatelessWidget {
  const _LibraryTag({required this.label, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primary.withValues(alpha: 0.09)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted ? scheme.primary : scheme.onSurfaceVariant,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _cleanDisplayTitle(String value) {
  return value
      .replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFE0E\uFE0F]'),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Future<void> _confirmDeleteVideo(
  BuildContext context,
  UiState state,
  LocalVideo video,
) async {
  final confirmed = await _confirm(
    context,
    title: '删除视频？',
    message: '视频文件和对应的下载任务记录都会被删除，此操作无法撤销。',
  );
  if (confirmed == true && context.mounted) {
    await state.deleteVideo(video);
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.video,
    this.width = 138,
    this.height = 92,
  });

  final LocalVideo video;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final file = video.thumbnailPath.isEmpty ? null : File(video.thumbnailPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: width,
        height: height,
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
