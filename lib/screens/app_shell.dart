import 'package:flutter/material.dart';

import '../services/ui_state.dart';
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
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 18,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: NavigationBar(
            selectedIndex: state.selectedTab,
            onDestinationSelected: state.selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.language_outlined),
                selectedIcon: Icon(Icons.language_rounded),
                label: '浏览器',
              ),
              NavigationDestination(
                icon: Icon(Icons.arrow_circle_down_outlined),
                selectedIcon: Icon(Icons.arrow_circle_down_rounded),
                label: '下载中',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: '已下载',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
