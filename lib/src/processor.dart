/// Pure mailbox-processing logic: UID dedupe, baseline, and alarm decisions.
library;

import 'dart:convert';

import 'matching.dart';

/// Max processed UIDs remembered (lastUid is the main guard; this is a second one).
const int maxProcessedUids = 500;

class MailState {
  MailState({this.uidValidity, this.lastUid = 0, List<int>? processed, this.lastOffAt})
    : processed = processed ?? <int>[];

  /// Null until the first successful connect (then the mailbox gets baselined).
  int? uidValidity;
  int lastUid;
  List<int> processed;
  DateTime? lastOffAt;

  bool get isBaselined => uidValidity != null;

  MailState copy() =>
      MailState(uidValidity: uidValidity, lastUid: lastUid, processed: List<int>.of(processed), lastOffAt: lastOffAt);

  String toJson() => jsonEncode({
    'uidValidity': uidValidity,
    'lastUid': lastUid,
    'processed': processed,
    'lastOffAt': lastOffAt?.toIso8601String(),
  });

  static MailState fromJson(String? s) {
    if (s == null || s.isEmpty) return MailState();
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return MailState(
        uidValidity: m['uidValidity'] as int?,
        lastUid: (m['lastUid'] as int?) ?? 0,
        processed: ((m['processed'] as List?) ?? const []).cast<int>().toList(),
        lastOffAt: m['lastOffAt'] == null ? null : DateTime.tryParse(m['lastOffAt'] as String),
      );
    } catch (_) {
      return MailState();
    }
  }
}

class IncomingMessage {
  const IncomingMessage(this.uid, this.subject);
  final int uid;
  final String? subject;
}

enum AlarmDecision {
  /// Nothing to do.
  none,

  /// A POWER OFF email arrived: start (or keep) the alarm.
  start,

  /// A POWER ON email arrived within the window: stop alarm, show "Power restored".
  restored,
}

class ProcessResult {
  ProcessResult(this.state, this.decision, this.events);
  final MailState state;
  final AlarmDecision decision;
  final List<String> events;
}

/// Called when we know the mailbox's UIDVALIDITY and highest existing UID.
/// Returns null when no (re)baseline is needed.
ProcessResult? baselineIfNeeded(MailState state, int uidValidity, int highestUid) {
  if (state.uidValidity == uidValidity) return null;
  final s = state.copy()
    ..uidValidity = uidValidity
    ..lastUid = highestUid
    ..processed = <int>[];
  final why = state.uidValidity == null ? 'First connect' : 'Mailbox UIDVALIDITY changed';
  return ProcessResult(s, AlarmDecision.none, [
    '$why: baseline set at UID $highestUid; existing mail will not trigger alarms',
  ]);
}

/// UIDs from a search result that still need to be looked at.
List<int> newUids(MailState state, Iterable<int> uids) {
  final seen = state.processed.toSet();
  final out = uids.where((u) => u > state.lastUid && !seen.contains(u)).toSet().toList()..sort();
  return out;
}

/// Processes newly fetched messages (any order) and decides what the alarm should do.
ProcessResult processMessages(
  MailState state,
  List<IncomingMessage> messages, {
  required DateTime now,
  required Duration autoStopWindow,
}) {
  final s = state.copy();
  final events = <String>[];
  var decision = AlarmDecision.none;
  var startedThisBatch = false;
  final seen = s.processed.toSet();
  final sorted = [...messages]..sort((a, b) => a.uid.compareTo(b.uid));

  for (final m in sorted) {
    if (m.uid <= state.lastUid || seen.contains(m.uid)) continue; // dedupe
    seen.add(m.uid);
    s.processed.add(m.uid);
    if (m.uid > s.lastUid) s.lastUid = m.uid;

    switch (classifySubject(m.subject)) {
      case AlertKind.powerOff:
        s.lastOffAt = now;
        startedThisBatch = true;
        decision = AlarmDecision.start;
        events.add('POWER OFF alert (UID ${m.uid}) - alarm triggered');
      case AlertKind.powerOn:
        final off = s.lastOffAt;
        final inWindow =
            startedThisBatch || (off != null && !now.isBefore(off) && now.difference(off) <= autoStopWindow);
        if (inWindow) {
          decision = AlarmDecision.restored;
          startedThisBatch = false;
          s.lastOffAt = null;
          events.add('POWER ON alert (UID ${m.uid}) - Power restored, alarm stopped');
        } else {
          events.add('POWER ON alert (UID ${m.uid}) outside the auto-stop window - logged only');
        }
      case AlertKind.other:
        break;
    }
  }

  if (s.processed.length > maxProcessedUids) {
    s.processed = s.processed.sublist(s.processed.length - maxProcessedUids);
  }
  return ProcessResult(s, decision, events);
}
