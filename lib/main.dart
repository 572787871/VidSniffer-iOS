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
          theme: _state.darkMode ? AppTheme.darkTheme : AppTheme.lightTheme,
          builder: (context, child) {
            return CupertinoTheme(
              data: CupertinoThemeData(
                brightness: _state.darkMode ? Brightness.dark : Brightness.light,
                primaryColor: AppTheme.electricBlue,
                scaffoldBackgroundColor: _state.darkMode ? AppTheme.midnight : const Color(0xfff5f7fb),
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
