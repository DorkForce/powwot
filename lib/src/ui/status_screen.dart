import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../native.dart';
import '../status_store.dart';
import 'permissions_card.dart';
import 'settings_screen.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> with WidgetsBindingObserver {
  StatusSnapshot _snap = StatusSnapshot();
  bool _monitoring = false;
  bool _alarm = false;
  bool _configured = false;
  Timer? _timer;
  final _permKey = GlobalKey<PermissionsCardState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _permKey.currentState?.refresh();
    }
  }

  Future<void> _refresh() async {
    final snap = await StatusStore.read();
    final cfg = await AppConfig.load();
    final configured = cfg.hasServer && await hasPassword();
    bool mon = false, alarm = false;
    try {
      mon = await NativeApp.isMonitoring();
      alarm = await NativeApp.isAlarmActive();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _monitoring = mon;
      _alarm = alarm;
      _configured = configured;
    });
  }

  Future<void> _toggle(bool on) async {
    if (on) {
      await NativeApp.startMonitoring();
    } else {
      await NativeApp.stopMonitoring();
      await StatusStore.log('Monitoring stopped');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _refresh();
  }

  String _fmt(DateTime? t) {
    if (t == null) return 'never';
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('powwot'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
              await _refresh();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_alarm)
              Card(
                color: Colors.red.shade700,
                child: ListTile(
                  leading: const Icon(Icons.warning, color: Colors.white),
                  title: const Text(
                    'ALARM RINGING',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red),
                    onPressed: () async {
                      await NativeApp.dismissAlarm();
                      await _refresh();
                    },
                    child: const Text('Dismiss'),
                  ),
                ),
              ),
            Card(
              child: SwitchListTile(
                title: const Text('Monitor mailbox'),
                subtitle: Text(
                  _monitoring
                      ? 'Running in the background (survives reboot)'
                      : _configured
                      ? 'Stopped'
                      : 'Set up the IMAP account in Settings first',
                ),
                value: _monitoring,
                onChanged: (_configured || _monitoring) ? _toggle : null,
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Last check: ${_fmt(_snap.lastCheck)}'),
                    Text('Last successful check: ${_fmt(_snap.lastOk)}'),
                    if (_snap.lastError != null) ...[
                      const SizedBox(height: 6),
                      Text('Connection error: ${_snap.lastError}', style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _monitoring
                              ? () async {
                                  await NativeApp.pollNow();
                                  await Future<void>.delayed(const Duration(seconds: 2));
                                  await _refresh();
                                }
                              : null,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Check now'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            PermissionsCard(key: _permKey),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    title: const Text('Recent events'),
                    trailing: TextButton(
                      onPressed: () async {
                        await StatusStore.clearEvents();
                        await _refresh();
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                  if (_snap.events.isEmpty)
                    const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('No events yet.')),
                  for (final e in _snap.events.take(50))
                    ListTile(
                      dense: true,
                      leading: Icon(
                        e.isError ? Icons.error_outline : Icons.info_outline,
                        color: e.isError ? scheme.error : null,
                      ),
                      title: Text(e.message),
                      subtitle: Text(_fmt(e.time)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
