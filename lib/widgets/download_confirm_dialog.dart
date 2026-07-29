import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/library_folder.dart';
import '../models/video_resource.dart';
import '../services/file_utils.dart';
import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import 'apple_ui.dart';

enum DownloadSaveTarget { library, newFolder }

Future<VideoResource?> showDownloadConfirmDialog(
  BuildContext context,
  VideoResource resource,
) async {
  final state = UiStateScope.of(context);
  DownloadSaveTarget target = DownloadSaveTarget.library;
  LibraryFolder? selectedFolder;
  return showModalBottomSheet<VideoResource>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> finish() async {
            final folder =
                target == DownloadSaveTarget.newFolder ? selectedFolder : null;
            if (target == DownloadSaveTarget.newFolder && folder == null) return;
            if (!sheetContext.mounted) return;
            Navigator.pop(
              sheetContext,
              resource.copyWith(
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
                    title: '保存资料库',
                    subtitle: '显示在“全部视频”中',
                    selected: target == DownloadSaveTarget.library,
                    onTap: () => setState(
                      () => target = DownloadSaveTarget.library,
                    ),
                  ),
                  _FolderChoice(
                    title: '新建文件夹',
                    subtitle: selectedFolder?.name ??
                        '默认使用当前视频名称，可直接修改',
                    selected: target == DownloadSaveTarget.newFolder,
                    onTap: () async {
                      final name = await _askFolderName(
                        sheetContext,
                        initialValue: resource.title,
                      );
                      if (name == null || name.trim().isEmpty) return;
                      final folder = await state.createFolder(name);
                      setState(() {
                        target = DownloadSaveTarget.newFolder;
                        selectedFolder = folder;
                      });
                    },
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

Future<String?> _askFolderName(
  BuildContext context, {
  String initialValue = '',
}) async {
  final controller = TextEditingController(
    text: FileUtils.safeFileName(initialValue, fallback: '新建文件夹'),
  );
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
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
