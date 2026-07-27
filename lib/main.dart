import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'services/ui_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VideoDownloaderApp());
}

class VideoDownloaderApp extends StatefulWidget {
  const VideoDownloaderApp({super.key});

  @override
  State<VideoDownloaderApp> createState() => _VideoDownloaderAppState();
}

class _VideoDownloaderAppState extends State<VideoDownloaderApp> {
  late final UiState state;

  @override
  void initState() {
    super.initState();
    state = UiState();
  }

  @override
  Widget build(BuildContext context) {
    return UiStateScope(
      state: state,
      child: MaterialApp(
        title: '视频解析下载',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        scrollBehavior: const _AppleScrollBehavior(),
        home: const AppShell(),
      ),
    );
  }
}

class _AppleScrollBehavior extends CupertinoScrollBehavior {
  const _AppleScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}
