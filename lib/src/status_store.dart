/// Shared status (last check, errors, recent events) written by the background
/// poller and read by the UI. Never store secrets here.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'processor.dart';

const int maxEvents = 100;

class StatusEvent {
  StatusEvent(this.time, this.message, {this.isError = false});
  final DateTime time;
  final String message;
  final bool isError;

  Map<String, dynamic> toMap() => {'t': time.toIso8601String(), 'm': message, 'e': isError};
  static StatusEvent fromMap(Map<String, dynamic> m) =>
      StatusEvent(DateTime.parse(m['t'] as String), m['m'] as String, isError: (m['e'] as bool?) ?? false);
}

class StatusSnapshot {
  StatusSnapshot({this.lastCheck, this.lastOk, this.lastError, this.events = const []});
  final DateTime? lastCheck;
  final DateTime? lastOk;
  final String? lastError;
  final List<StatusEvent> events;
}

class StatusStore {
  static final SharedPreferencesAsync _p = SharedPreferencesAsync();

  static Future<StatusSnapshot> read() async {
    final lc = await _p.getString('status.lastCheck');
    final lo = await _p.getString('status.lastOk');
    final err = await _p.getString('status.lastError');
    return StatusSnapshot(
      lastCheck: lc == null ? null : DateTime.tryParse(lc),
      lastOk: lo == null ? null : DateTime.tryParse(lo),
      lastError: (err == null || err.isEmpty) ? null : err,
      events: await _events(),
    );
  }

  static Future<List<StatusEvent>> _events() async {
    final raw = await _p.getString('status.events');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => StatusEvent.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> log(String message, {bool isError = false}) async {
    final list = await _events();
    list.insert(0, StatusEvent(DateTime.now(), message, isError: isError));
    if (list.length > maxEvents) list.removeRange(maxEvents, list.length);
    await _p.setString('status.events', jsonEncode(list.map((e) => e.toMap()).toList()));
  }

  static Future<void> clearEvents() => _p.remove('status.events');

  static Future<void> markCheck({required bool ok, String? error}) async {
    final now = DateTime.now().toIso8601String();
    await _p.setString('status.lastCheck', now);
    if (ok) {
      await _p.setString('status.lastOk', now);
      await _p.remove('status.lastError');
    } else {
      await _p.setString('status.lastError', error ?? 'Unknown error');
    }
  }

  static Future<MailState> readMailState(String serverKey) async {
    if (await _p.getString('mail.serverKey') != serverKey) return MailState();
    return MailState.fromJson(await _p.getString('mail.state'));
  }

  static Future<void> writeMailState(String serverKey, MailState s) async {
    await _p.setString('mail.serverKey', serverKey);
    await _p.setString('mail.state', s.toJson());
  }
}
