import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VidSnifferProApp());
}

class VidSnifferProApp extends StatelessWidget {
  const VidSnifferProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VidSniffer Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        return CupertinoTheme(
          data: const CupertinoThemeData(
            brightness: Brightness.dark,
            primaryColor: AppTheme.electricBlue,
            scaffoldBackgroundColor: AppTheme.midnight,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AppShell(),
    );
  }
}
