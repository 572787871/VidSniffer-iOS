import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'screens/app_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VidSnifferProApp());
}

class VidSnifferProApp extends StatefulWidget {
  const VidSnifferProApp({super.key});

  @override
  State<VidSnifferProApp> createState() => _VidSnifferProAppState();
}

class _VidSnifferProAppState extends State<VidSnifferProApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return MaterialApp(
          title: 'VidSniffer Pro',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          builder: (context, child) {
            return CupertinoTheme(
              data: CupertinoThemeData(
                brightness: MediaQuery.platformBrightnessOf(context),
                primaryColor: AppTheme.electricBlue,
                scaffoldBackgroundColor: MediaQuery.platformBrightnessOf(context) == Brightness.dark ? AppTheme.midnight : const Color(0xfff5f7fb),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: AppShell(state: _state),
        );
      },
    );
  }
}
