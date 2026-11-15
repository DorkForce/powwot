/// Background poller. Runs in the headless Flutter engine owned by MonitorService.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'config.dart';
import 'imap_checker.dart';
import 'processor.dart';
import 'status_store.dart';

class Poller {
  final MethodChannel _svc = const MethodChannel('powwot/service');
  Completer<void> _wake = Completer<void>();
  bool _busy = false;
  int _failures = 0;

  Future<void> run() async {
    _svc.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pollNow':
        case 'reload':
          _kick();
        case 'alarmStopped':
          await StatusStore.log('Alarm dismissed');
      }
      return null;
    });
    final cfg = await AppConfig.load();
    await _svc.invokeMethod('setKeepCpuAwake', {'value': cfg.keepCpuAwake});
    await StatusStore.log('Monitoring started');
    while (true) {
      final interval = await _checkOnce();
      await Future.any([Future<void>.delayed(interval), _wake.future]);
      if (_wake.isCompleted) _wake = Completer<void>();
    }
  }

  void _kick() {
    if (!_wake.isCompleted) _wake.complete();
  }

  /// Returns how long to wait before the next check.
  Future<Duration> _checkOnce() async {
    if (_busy) return const Duration(seconds: 5);
    _busy = true;
    AppConfig cfg = AppConfig();
    String? password;
    try {
      cfg = await AppConfig.load();
      final interval = Duration(seconds: cfg.pollSeconds.clamp(15, 3600));
      password = await readPassword();
      if (!cfg.hasServer || password == null || password.isEmpty) {
        await StatusStore.markCheck(ok: false, error: 'Not configured: set IMAP host, username and password');
        await _status('Not configured - open powwot settings');
        return interval;
      }
      await _check(cfg, password);
      _failures = 0;
      await StatusStore.markCheck(ok: true);
      await _status('Last check ${_hhmm(DateTime.now())} - OK');
      return interval;
    } catch (e) {
      _failures++;
      final msg = describeError(e, secret: password);
      await StatusStore.markCheck(ok: false, error: msg);
      if (_failures == 1 || _failures % 10 == 0) {
        await StatusStore.log('Check failed ($_failures in a row): $msg', isError: true);
      }
      await _status('Check failed ${_hhmm(DateTime.now())} - retrying');
      // Back off a little on repeated failures, but never beyond 5 minutes.
      final base = cfg.pollSeconds.clamp(15, 3600);
      final secs = (_failures > 3 ? base * 2 : base).clamp(15, 300);
      return Duration(seconds: secs);
    } finally {
      _busy = false;
    }
  }

  Future<void> _check(AppConfig cfg, String password) async {
    final session = await ImapSession.open(cfg, password);
    try {
      final snap = await session.select(cfg.mailbox);
      var state = await StatusStore.readMailState(cfg.serverKey);

      final base = baselineIfNeeded(state, snap.uidValidity, snap.highestUid);
      if (base != null) {
        state = base.state;
        await StatusStore.writeMailState(cfg.serverKey, state);
        for (final e in base.events) {
          await StatusStore.log('$e (${snap.messageCount} messages in ${cfg.mailbox})');
        }
        return;
      }
      if (snap.highestUid <= state.lastUid) return; // nothing new

      final uids = newUids(state, await session.uidsAfter(state.lastUid));
      final msgs = await session.fetchSubjects(uids);
      final result = processMessages(
        state,
        msgs,
        now: DateTime.now(),
        autoStopWindow: Duration(minutes: cfg.autoStopMinutes),
      );
      // Mark UIDs that the fetch did not return (e.g. deleted meanwhile) as seen too.
      final s = result.state;
      for (final u in uids) {
        if (u > s.lastUid) s.lastUid = u;
      }
      await StatusStore.writeMailState(cfg.serverKey, s);
      for (final e in result.events) {
        await StatusStore.log(e, isError: e.startsWith('POWER OFF'));
      }
      switch (result.decision) {
        case AlarmDecision.start:
          await _svc.invokeMethod('startAlarm', {
            'reason': 'MySpool POWER OFF Alert',
            'toneUri': cfg.toneUri,
            'rampSeconds': cfg.rampSeconds,
            'maxStream': cfg.maxAlarmStream,
          });
        case AlarmDecision.restored:
          await _svc.invokeMethod('stopAlarm', {
            'reason': 'restored',
            'message': 'Power restored (${_hhmm(DateTime.now())})',
          });
        case AlarmDecision.none:
          break;
      }
    } finally {
      await session.close();
    }
  }

  Future<void> _status(String text) async {
    try {
      await _svc.invokeMethod('setStatus', {'text': text});
    } catch (_) {}
  }
}

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
