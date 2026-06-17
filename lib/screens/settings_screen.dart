import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            const Text('设置', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('下载、缓存与应用信息', style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 20),
            _SettingTile(
              icon: LucideIcons.moon,
              title: '外观',
              subtitle: '跟随系统设置',
              trailingIcon: LucideIcons.checkCircle,
              onTap: () => _showAppearance(context),
            ),
            _SettingTile(
              icon: LucideIcons.folderInput,
              title: '下载路径',
              subtitle: state.downloadDirectory,
              trailingIcon: LucideIcons.folderOpen,
              onTap: () => _showDownloadPath(context, state),
            ),
            _SettingTile(
              icon: LucideIcons.sparkles,
              title: '清理缓存',
              subtitle: '当前缓存 ${state.cacheSize}',
              trailingIcon: LucideIcons.chevronRight,
              onTap: () => _clearCache(context, state),
            ),
            _SettingTile(
              icon: LucideIcons.info,
              title: '关于应用',
              subtitle: 'VidSniffer Pro 1.0.0',
              trailingIcon: LucideIcons.chevronRight,
              onTap: () => _showAbout(context),
            ),
          ],
        );
      },
    );
  }

  void _showAppearance(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('外观'),
        content: const Text('应用现在跟随 iOS 系统深色/浅色外观。请在系统设置里切换。'),
        actions: [CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(), child: const Text('完成'))],
      ),
    );
  }

  void _showDownloadPath(BuildContext context, AppState state) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('下载路径'),
        content: Text('${state.downloadDirectory}\n\n已启用 iOS 文件共享，安装后可在“文件”App 的“我的 iPhone / VidSniffer Pro / videos”查看视频。'),
        actions: [CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(), child: const Text('完成'))],
      ),
    );
  }

  void _clearCache(BuildContext context, AppState state) {
    state.clearCache();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('缓存已清理'), behavior: SnackBarBehavior.floating),
    );
  }

  void _showAbout(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('VidSniffer Pro'),
        content: const Text('版本 1.0.0\n网页视频嗅探、解析与本地下载工具。'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(), child: const Text('完成')),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailingIcon,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(17)),
            child: Icon(icon, color: AppTheme.electricBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              ],
            ),
          ),
          Icon(trailingIcon, color: AppTheme.muted, size: 20),
        ],
      ),
    );
  }
}
