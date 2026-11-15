import 'dart:ui';

import 'package:flutter/material.dart';

import 'src/poller.dart';
import 'src/ui/status_screen.dart';

void main() {
  runApp(const PowwotApp());
}

/// Entry point for the headless engine started by MonitorService (Android).
@pragma('vm:entry-point')
Future<void> pollerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Poller().run();
}

class PowwotApp extends StatelessWidget {
  const PowwotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'powwot',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.deepOrange, brightness: Brightness.dark, useMaterial3: true),
      home: const StatusScreen(),
    );
  }
}
