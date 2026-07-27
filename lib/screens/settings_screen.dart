import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: Navigator.of(context).pop,
          child: const Icon(CupertinoIcons.back),
        ),
        title: const Text('设置'),
      ),
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            const AppleSectionHeader(title: '下载'),
            AppleListGroup(
              footer: '下载的视频可在“文件”App 的本 App 文件夹中找到。',
              children: [
                const AppleListTile(
                  title: '默认保存位置',
                  subtitle: 'Documents / videos',
                  icon: CupertinoIcons.folder_fill,
                  iconColor: AppTheme.blue,
                ),
                ListTile(
                  leading: const AppleIconTile(
                    icon: CupertinoIcons.wifi,
                    color: AppTheme.green,
                  ),
                  title: const Text('仅 Wi-Fi 下载'),
                  subtitle: const Text('避免使用移动数据下载大文件'),
                  trailing: CupertinoSwitch(
                    value: state.onlyWifi,
                    activeTrackColor: AppTheme.green,
                    onChanged: state.toggleWifi,
                  ),
                  onTap: () => state.toggleWifi(!state.onlyWifi),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const AppleSectionHeader(title: '存储'),
            AppleListGroup(
              children: [
                AppleListTile(
                  title: '清理缓存',
                  subtitle: '移除网页与临时解析文件',
                  icon: CupertinoIcons.trash_fill,
                  iconColor: AppTheme.orange,
                  onTap: () => _showCacheNotice(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const AppleSectionHeader(title: '关于'),
            AppleListGroup(
              children: [
                const AppleListTile(
                  title: '网页视频下载器',
                  subtitle: '版本 1.0.0',
                  icon: CupertinoIcons.info_circle_fill,
                  iconColor: AppTheme.blue,
                ),
                AppleListTile(
                  title: '使用与版权说明',
                  icon: CupertinoIcons.checkmark_shield_fill,
                  iconColor: AppTheme.green,
                  onTap: () => _showCompliance(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static void _showCacheNotice(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清理缓存'),
        content: const Text('\n当前没有需要清理的临时缓存。已下载视频不会被删除。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: Navigator.of(context).pop,
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  static void _showCompliance(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('使用与版权说明'),
        content: const Text(
          '\n请仅下载自己有权访问和保存的视频。本 App 不绕过 DRM、付费墙或加密版权保护。',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: Navigator.of(context).pop,
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }
}
