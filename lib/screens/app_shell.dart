import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:vidsniffer_pro/theme/app_icons.dart';

import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import 'app_state.dart';
import 'browser_screen.dart';
import 'downloads_screen.dart';
import 'files_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final AppState _state = AppState();
  int _index = 0;

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenTab: _setIndex),
      const BrowserScreen(),
      const DownloadsScreen(),
      const FilesScreen(),
      const SettingsScreen(),
    ];

    return AppStateScope(
      notifier: _state,
      child: AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: 280.ms,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.025, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
            ),
          ),
          bottomNavigationBar: _GlassTabBar(currentIndex: _index, onChanged: _setIndex),
        ),
      ),
    );
  }

  void _setIndex(int value) => setState(() => _index = value);
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar({required this.currentIndex, required this.onChanged});

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      _TabItem('首页', LucideIcons.home),
      _TabItem('浏览器', LucideIcons.globe2),
      _TabItem('下载', LucideIcons.downloadCloud),
      _TabItem('文件', LucideIcons.folderOpen),
      _TabItem('设置', LucideIcons.settings),
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.panel.withOpacity(0.78),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.12))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => onChanged(i),
                      child: AnimatedContainer(
                        duration: 220.ms,
                        curve: Curves.easeOutCubic,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: i == currentIndex ? Colors.white.withOpacity(0.12) : Colors.transparent,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              items[i].icon,
                              size: 21,
                              color: i == currentIndex ? AppTheme.electricBlue : AppTheme.muted,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              items[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: i == currentIndex ? Colors.white : AppTheme.muted,
                                fontSize: 11,
                                fontWeight: i == currentIndex ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem(this.label, this.icon);

  final String label;
  final IconData icon;
}
