import 'package:flutter/material.dart';

import '../native.dart';

/// Shows which phone permissions are granted, with buttons to fix the missing ones.
class PermissionsCard extends StatefulWidget {
  const PermissionsCard({super.key});

  @override
  State<PermissionsCard> createState() => PermissionsCardState();
}

class PermissionsCardState extends State<PermissionsCard> {
  Map<String, bool> _p = {};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final p = await NativeApp.permissionStatus();
      if (mounted) setState(() => _p = p);
    } catch (_) {}
  }

  Widget _row(String key, String title, String why, Future<void> Function() fix) {
    final ok = _p[key] ?? false;
    return ListTile(
      leading: Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red),
      title: Text(title),
      subtitle: Text(why),
      trailing: ok ? null : TextButton(onPressed: fix, child: const Text('Grant')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Phone permissions'),
            trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: refresh),
          ),
          _row(
            'notifications',
            'Notifications',
            'Needed for the alarm and the monitoring notice',
            NativeApp.requestNotifications,
          ),
          _row(
            'dndAccess',
            'Do Not Disturb access',
            'Lets the alarm break through DND / total silence',
            NativeApp.openDndAccess,
          ),
          _row(
            'batteryExempt',
            'Ignore battery optimization',
            'Keeps background checks running',
            NativeApp.requestBatteryExemption,
          ),
          _row(
            'fullScreenIntent',
            'Full-screen alarms',
            'Shows the alarm over the lock screen (Android 14+)',
            NativeApp.openFullScreenIntentSettings,
          ),
        ],
      ),
    );
  }
}
