import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import '../widgets/apple_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({this.embedded = false, super.key});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 24,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
        automaticallyImplyLeading: !embedded,
        leading: embedded
            ? null
            : CupertinoButton(
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
                const ListTile(
                  title: Text('默认保存位置'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Documents / videos',
                        style: TextStyle(color: CupertinoColors.systemGrey),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_forward,
                        size: 17,
                        color: CupertinoColors.systemGrey,
                      ),
                    ],
                  ),
                ),
                ListTile(
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
                ListTile(
                  title: const Text('清理缓存'),
                  subtitle: const Text('移除网页与临时解析文件'),
                  trailing: const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 17,
                    color: CupertinoColors.systemGrey,
                  ),
                  onTap: () => _showCacheNotice(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const AppleSectionHeader(title: '关于'),
            AppleListGroup(
              children: [
                const ListTile(
                  title: Text('版本'),
                  trailing: Text(
                    '1.0.0',
                    style: TextStyle(color: CupertinoColors.systemGrey),
                  ),
                ),
                ListTile(
                  title: const Text('使用与版权说明'),
                  trailing: const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 17,
                    color: CupertinoColors.systemGrey,
                  ),
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
