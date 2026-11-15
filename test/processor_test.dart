import 'package:flutter_test/flutter_test.dart';
import 'package:powwot/src/processor.dart';

const off = 'MySpool POWER OFF Alert';
const on = 'MySpool POWER ON Alert';
final t0 = DateTime(2026, 11, 15, 3, 0);
const window = Duration(minutes: 60);

MailState baselined({int lastUid = 100}) => MailState(uidValidity: 7, lastUid: lastUid);

void main() {
  group('baseline', () {
    test('first connect marks all existing mail as baseline', () {
      final r = baselineIfNeeded(MailState(), 7, 523)!;
      expect(r.state.uidValidity, 7);
      expect(r.state.lastUid, 523);
      expect(r.decision, AlarmDecision.none);
      expect(r.events.single, contains('First connect'));
    });
    test('no rebaseline when UIDVALIDITY unchanged', () {
      expect(baselineIfNeeded(baselined(), 7, 900), isNull);
    });
    test('UIDVALIDITY change rebaselines and clears processed', () {
      final s = baselined()..processed = [99, 100];
      final r = baselineIfNeeded(s, 8, 12)!;
      expect(r.state.lastUid, 12);
      expect(r.state.processed, isEmpty);
      expect(r.events.single, contains('UIDVALIDITY changed'));
    });
    test('old POWER OFF mail present at baseline never triggers', () {
      final b = baselineIfNeeded(MailState(), 7, 50)!.state;
      final r = processMessages(
        b,
        [const IncomingMessage(40, off), const IncomingMessage(50, off)],
        now: t0,
        autoStopWindow: window,
      );
      expect(r.decision, AlarmDecision.none);
      expect(r.state.lastUid, 50);
    });
  });

  group('UID dedupe', () {
    test('newUids filters <= lastUid, processed, duplicates, and sorts', () {
      final s = baselined()..processed = [103];
      // IMAP "101:*" may return the newest message (here 100) even if lower.
      expect(newUids(s, [100, 105, 101, 103, 101, 102]), [101, 102, 105]);
    });
    test('same message processed twice only alarms once', () {
      final r1 = processMessages(baselined(), [const IncomingMessage(101, off)], now: t0, autoStopWindow: window);
      expect(r1.decision, AlarmDecision.start);
      expect(r1.state.lastUid, 101);
      final r2 = processMessages(
        r1.state,
        [const IncomingMessage(101, off)],
        now: t0.add(const Duration(minutes: 1)),
        autoStopWindow: window,
      );
      expect(r2.decision, AlarmDecision.none);
      expect(r2.events, isEmpty);
    });
    test('processed list is bounded', () {
      var s = baselined(lastUid: 0);
      final msgs = [for (var i = 1; i <= maxProcessedUids + 50; i++) IncomingMessage(i, 'hello $i')];
      s = processMessages(s, msgs, now: t0, autoStopWindow: window).state;
      expect(s.processed.length, maxProcessedUids);
      expect(s.processed.last, maxProcessedUids + 50);
      expect(s.lastUid, maxProcessedUids + 50);
    });
    test('state survives JSON round trip', () {
      final s = MailState(uidValidity: 9, lastUid: 42, processed: [40, 41, 42], lastOffAt: t0);
      final back = MailState.fromJson(s.toJson());
      expect(back.uidValidity, 9);
      expect(back.lastUid, 42);
      expect(back.processed, [40, 41, 42]);
      expect(back.lastOffAt, t0);
      expect(MailState.fromJson('garbage').isBaselined, isFalse);
    });
  });

  group('alarm decisions', () {
    test('unrelated mail does nothing but advances lastUid', () {
      final r = processMessages(
        baselined(),
        [const IncomingMessage(101, 'Newsletter')],
        now: t0,
        autoStopWindow: window,
      );
      expect(r.decision, AlarmDecision.none);
      expect(r.state.lastUid, 101);
    });
    test('POWER ON within window restores', () {
      final r1 = processMessages(baselined(), [const IncomingMessage(101, off)], now: t0, autoStopWindow: window);
      final r2 = processMessages(
        r1.state,
        [const IncomingMessage(102, on)],
        now: t0.add(const Duration(minutes: 59)),
        autoStopWindow: window,
      );
      expect(r2.decision, AlarmDecision.restored);
      expect(r2.events.single, contains('Power restored'));
      expect(r2.state.lastOffAt, isNull);
    });
    test('POWER ON after window is only logged', () {
      final r1 = processMessages(baselined(), [const IncomingMessage(101, off)], now: t0, autoStopWindow: window);
      final r2 = processMessages(
        r1.state,
        [const IncomingMessage(102, on)],
        now: t0.add(const Duration(minutes: 61)),
        autoStopWindow: window,
      );
      expect(r2.decision, AlarmDecision.none);
      expect(r2.events.single, contains('outside'));
    });
    test('POWER ON with no prior OFF is only logged', () {
      final r = processMessages(baselined(), [const IncomingMessage(101, on)], now: t0, autoStopWindow: window);
      expect(r.decision, AlarmDecision.none);
    });
    test('OFF then ON in the same batch (out of order input) restores', () {
      final r = processMessages(
        baselined(),
        [const IncomingMessage(102, on), const IncomingMessage(101, off)],
        now: t0,
        autoStopWindow: window,
      );
      expect(r.decision, AlarmDecision.restored);
    });
    test('ON then a new OFF in the same batch alarms', () {
      final r = processMessages(
        baselined(),
        [const IncomingMessage(101, on), const IncomingMessage(102, off)],
        now: t0,
        autoStopWindow: window,
      );
      expect(r.decision, AlarmDecision.start);
    });
  });
}
