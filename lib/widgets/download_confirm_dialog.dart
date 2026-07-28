import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/library_folder.dart';
import '../models/video_resource.dart';
import '../services/file_utils.dart';
import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import 'apple_ui.dart';

enum DownloadSaveTarget { recent, site, page, custom, create }

Future<VideoResource?> showDownloadConfirmDialog(
  BuildContext context,
  VideoResource resource,
) async {
  final state = UiStateScope.of(context);
  final nameController = TextEditingController(
    text: FileUtils.safeFileName(resource.title, fallback: 'video'),
  );
  DownloadSaveTarget target = DownloadSaveTarget.page;
  LibraryFolder? selectedFolder =
      state.folders.isEmpty ? null : state.folders.first;
  try {
    return await showModalBottomSheet<VideoResource>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) {
          final uri = Uri.tryParse(
            resource.pageUrl.isNotEmpty ? resource.pageUrl : resource.url,
          );
          final site = uri?.host ?? '未知来源';
          Future<void> finish() async {
            final folder = await _resolveFolder(
              sheetContext,
              state,
              resource,
              target,
              selectedFolder,
            );
            if (folder == null && target == DownloadSaveTarget.create) return;
            final name = FileUtils.safeFileName(
              nameController.text,
              fallback: resource.title,
            );
            if (!sheetContext.mounted) return;
            Navigator.pop(
              sheetContext,
              resource.copyWith(
                title: name,
                preferredFolderId: folder?.folderId ?? '',
                preferredFolderName: folder?.name ?? '',
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              0,
              18,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '保存到',
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '选择视频的保存位置',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FolderChoice(
                    title: '最近下载',
                    subtitle: '不加入文件夹',
                    selected: target == DownloadSaveTarget.recent,
                    onTap: () => setState(
                      () => target = DownloadSaveTarget.recent,
                    ),
                  ),
                  _FolderChoice(
                    title: '当前页面',
                    subtitle: resource.title,
                    selected: target == DownloadSaveTarget.page,
                    onTap: () =>
                        setState(() => target = DownloadSaveTarget.page),
                  ),
                  _FolderChoice(
                    title: site,
                    subtitle: '来源网站',
                    selected: target == DownloadSaveTarget.site,
                    onTap: () =>
                        setState(() => target = DownloadSaveTarget.site),
                  ),
                  for (final folder in state.folders)
                    _FolderChoice(
                      title: folder.name,
                      subtitle: '自定义文件夹',
                      selected: target == DownloadSaveTarget.custom &&
                          selectedFolder?.folderId == folder.folderId,
                      onTap: () => setState(() {
                        target = DownloadSaveTarget.custom;
                        selectedFolder = folder;
                      }),
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: const AppleIconTile(
                      icon: CupertinoIcons.folder_badge_plus,
                      color: AppTheme.blue,
                    ),
                    title: const Text(
                      '新建文件夹',
                      style: TextStyle(
                        color: AppTheme.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 17,
                      color: CupertinoColors.systemGrey,
                    ),
                    onTap: () async {
                      final name = await _askFolderName(sheetContext);
                      if (name == null || name.trim().isEmpty) return;
                      final folder = await state.createFolder(name);
                      setState(() {
                        target = DownloadSaveTarget.custom;
                        selectedFolder = folder;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '文件名',
                      prefixIcon: Icon(CupertinoIcons.film),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${resource.quality} · ${resource.displayFormat} · ${resource.size}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: finish,
                          icon:
                              const Icon(CupertinoIcons.arrow_down_to_line),
                          label: const Text('保存并下载'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  } finally {
    nameController.dispose();
  }
}

class _FolderChoice extends StatelessWidget {
  const _FolderChoice({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ApplePressable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.blue.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
          ),
          child: ListTile(
            leading: const AppleIconTile(
              icon: CupertinoIcons.folder_fill,
              color: AppTheme.orange,
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              color: selected ? AppTheme.blue : CupertinoColors.systemGrey,
            ),
          ),
        ),
      ),
    );
  }
}

Future<LibraryFolder?> _resolveFolder(
  BuildContext context,
  UiState state,
  VideoResource resource,
  DownloadSaveTarget target,
  LibraryFolder? selectedFolder,
) async {
  final pageUrl = resource.pageUrl.isNotEmpty ? resource.pageUrl : resource.url;
  final host = Uri.tryParse(pageUrl)?.host ?? '';
  switch (target) {
    case DownloadSaveTarget.recent:
      return null;
    case DownloadSaveTarget.site:
      if (host.isEmpty) return null;
      final now = DateTime.now();
      return LibraryFolder(
        folderId: 'site:$host',
        name: host,
        type: LibraryFolderType.site,
        createdAt: now,
        updatedAt: now,
      );
    case DownloadSaveTarget.page:
      final now = DateTime.now();
      return LibraryFolder(
        folderId: 'page:${FileUtils.stableKey(pageUrl)}',
        name: resource.title.trim().isEmpty ? '当前页面' : resource.title,
        type: LibraryFolderType.page,
        createdAt: now,
        updatedAt: now,
      );
    case DownloadSaveTarget.custom:
      return selectedFolder;
    case DownloadSaveTarget.create:
      final name = await _askFolderName(context);
      if (name == null || name.trim().isEmpty) return null;
      return state.createFolder(name);
  }
}

Future<String?> _askFolderName(BuildContext context) async {
  final controller = TextEditingController();
  try {
    return showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('新建文件夹'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: '文件夹名称',
            clearButtonMode: OverlayVisibilityMode.editing,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
