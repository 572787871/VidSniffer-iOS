import 'package:flutter/material.dart';

import '../services/ui_state.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final pages = const [
    HomeScreen(),
    DownloadsScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) =>
            IndexedStack(index: state.selectedTab, children: pages),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: state,
        builder: (context, _) => NavigationBar(
          selectedIndex: state.selectedTab,
          onDestinationSelected: state.selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.downloading_outlined),
              selectedIcon: Icon(Icons.downloading_rounded),
              label: '下载',
            ),
            NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              selectedIcon: Icon(Icons.video_library_rounded),
              label: '视频库',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}
