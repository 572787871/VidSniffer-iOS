import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/ui_state.dart';
import 'browser_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';

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
      extendBody: true,
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => IndexedStack(
          index: state.selectedTab.clamp(0, 3),
          children: [
            BrowserScreen(active: state.selectedTab == 0),
            const DownloadsScreen(),
            const LibraryScreen(),
            const SettingsScreen(embedded: true),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: state,
        builder: (context, _) => _FloatingPillTabBar(
          index: state.selectedTab.clamp(0, 3),
          onChanged: state.selectTab,
        ),
      ),
    );
  }
}

class _FloatingPillTabBar extends StatelessWidget {
  const _FloatingPillTabBar({
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const items = [
    (CupertinoIcons.search, '搜索'),
    (CupertinoIcons.arrow_down_to_line, '下载'),
    (CupertinoIcons.folder, '文件'),
    (CupertinoIcons.gear_alt, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceTransparency =
        MediaQuery.highContrastOf(context);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: reduceTransparency ? 0 : 24,
            sigmaY: reduceTransparency ? 0 : 24,
          ),
          child: Container(
            height: 72,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(
                alpha: reduceTransparency ? 1 : 0.82,
              ),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var itemIndex = 0;
                    itemIndex < items.length;
                    itemIndex++)
                  Expanded(
                    child: _PillTabItem(
                      icon: items[itemIndex].$1,
                      label: items[itemIndex].$2,
                      selected: itemIndex == index,
                      onTap: () => onChanged(itemIndex),
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

class _PillTabItem extends StatefulWidget {
  const _PillTabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PillTabItem> createState() => _PillTabItemState();
}

class _PillTabItemState extends State<_PillTabItem> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => pressed = true),
      onTapCancel: () => setState(() => pressed = false),
      onTapUp: (_) => setState(() => pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: pressed ? 0.96 : 1,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.selected
                ? scheme.onSurface.withValues(alpha: 0.065)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(29),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 25, color: scheme.onSurface),
              const SizedBox(height: 3),
              Text(
                widget.label,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 11,
                  height: 1,
                  fontWeight:
                      widget.selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
