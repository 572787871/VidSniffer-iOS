import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/ui_state.dart';
import '../theme/app_theme.dart';
import 'browser_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => IndexedStack(
          index: state.selectedTab,
          children: [
            BrowserScreen(active: state.selectedTab == 0),
            const DownloadsScreen(),
            const LibraryScreen(),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: state,
        builder: (context, _) => ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.86),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
              ),
              child: CupertinoTabBar(
                currentIndex: state.selectedTab,
                onTap: state.selectTab,
                activeColor: AppTheme.blue,
                inactiveColor: CupertinoColors.systemGrey,
                backgroundColor: Colors.transparent,
                border: null,
                height: 52,
                iconSize: 24,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.globe),
                    activeIcon: Icon(CupertinoIcons.globe),
                    label: '浏览器',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.arrow_down_circle),
                    activeIcon:
                        Icon(CupertinoIcons.arrow_down_circle_fill),
                    label: '下载中',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.folder),
                    activeIcon: Icon(CupertinoIcons.folder_fill),
                    label: '已下载',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
