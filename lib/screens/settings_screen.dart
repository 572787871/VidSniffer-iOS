import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: const [
        Text('设置', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        SizedBox(height: 8),
        Text('下载、缓存与应用信息', style: TextStyle(color: AppTheme.muted)),
        SizedBox(height: 20),
        _SettingTile(icon: LucideIcons.moon, title: '深色模式', subtitle: '默认开启', trailing: _AlwaysOnSwitch()),
        _SettingTile(icon: LucideIcons.folderInput, title: '下载路径', subtitle: 'VidSniffer Pro / Downloads', trailingIcon: LucideIcons.chevronRight),
        _SettingTile(icon: LucideIcons.sparkles, title: '清理缓存', subtitle: '释放临时分片与网页缓存', trailingIcon: LucideIcons.chevronRight),
        _SettingTile(icon: LucideIcons.info, title: '关于应用', subtitle: 'VidSniffer Pro 1.0.0', trailingIcon: LucideIcons.chevronRight),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingIcon,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
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
                Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              ],
            ),
          ),
          trailing ?? Icon(trailingIcon, color: AppTheme.muted, size: 20),
        ],
      ),
    );
  }
}

class _AlwaysOnSwitch extends StatelessWidget {
  const _AlwaysOnSwitch();

  @override
  Widget build(BuildContext context) {
    return CupertinoSwitch(value: true, onChanged: null, activeColor: AppTheme.electricBlue);
  }
}
