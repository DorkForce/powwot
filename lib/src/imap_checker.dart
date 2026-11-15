/// IMAP access via enough_mail. Read-only: uses SELECT + UID SEARCH + UID FETCH
/// (ENVELOPE), which never marks messages as read.
library;

import 'package:enough_mail/enough_mail.dart';

import 'config.dart';
import 'processor.dart';

class MailboxSnapshot {
  MailboxSnapshot(this.uidValidity, this.highestUid, this.messageCount);
  final int uidValidity;
  final int highestUid;
  final int messageCount;
}

class ImapSession {
  ImapSession._(this._client);
  final ImapClient _client;

  static const _timeout = Duration(seconds: 30);

  static Future<ImapSession> open(AppConfig cfg, String password) async {
    final client = ImapClient(isLogEnabled: false, defaultResponseTimeout: _timeout);
    await client.connectToServer(cfg.host.trim(), cfg.port, isSecure: cfg.useSsl, timeout: _timeout);
    if (!cfg.useSsl) {
      // Never send the password in clear text: require STARTTLS when SSL is off.
      await client.startTls();
    }
    await client.login(cfg.username.trim(), password);
    return ImapSession._(client);
  }

  Future<MailboxSnapshot> select(String mailbox) async {
    final box = mailbox.trim().isEmpty || mailbox.trim().toUpperCase() == 'INBOX'
        ? await _client.selectInbox()
        : await _client.selectMailboxByPath(mailbox.trim());
    final validity = box.uidValidity ?? 0;
    int highest;
    if (box.uidNext != null) {
      highest = box.uidNext! - 1;
    } else if (box.messagesExists == 0) {
      highest = 0;
    } else {
      final r = await _client.uidSearchMessages(searchCriteria: 'ALL');
      final ids = r.matchingSequence?.toList() ?? const <int>[];
      highest = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
    }
    return MailboxSnapshot(validity, highest, box.messagesExists);
  }

  /// UIDs strictly greater than [lastUid]. (IMAP "n:*" always returns the newest
  /// message even when its UID is lower, so callers must filter - see newUids().)
  Future<List<int>> uidsAfter(int lastUid) async {
    final r = await _client.uidSearchMessages(searchCriteria: 'UID ${lastUid + 1}:*');
    return r.matchingSequence?.toList() ?? const <int>[];
  }

  Future<List<IncomingMessage>> fetchSubjects(List<int> uids) async {
    if (uids.isEmpty) return const [];
    final r = await _client.uidFetchMessages(MessageSequence.fromIds(uids, isUid: true), '(UID ENVELOPE)');
    return [
      for (final m in r.messages)
        if (m.uid != null) IncomingMessage(m.uid!, m.envelope?.subject ?? m.decodeSubject()),
    ];
  }

  Future<void> close() async {
    try {
      await _client.logout();
    } catch (_) {}
    try {
      await _client.disconnect();
    } catch (_) {}
  }
}

/// Human-readable error that never includes the password.
String describeError(Object e, {String? secret}) {
  var s = e.toString();
  if (secret != null && secret.isNotEmpty) s = s.replaceAll(secret, '***');
  if (s.length > 300) s = '${s.substring(0, 300)}...';
  return s;
}
