/// App settings. Non-secret values live in SharedPreferences; the IMAP password
/// lives ONLY in flutter_secure_storage (Android Keystore-backed) on the phone.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _passwordKey = 'imap_password';

/// Default volume ramp: silent at 0:00, full volume at 5:00.
const int defaultRampSeconds = 300;

/// Previous default (100 s). Migrated to [defaultRampSeconds] unless the user
/// explicitly chose a value.
const int legacyDefaultRampSeconds = 100;

const String _rampSecondsKey = 'rampSeconds';
const String _rampSecondsExplicitKey = 'rampSecondsExplicit';

const FlutterSecureStorage secureStorage = FlutterSecureStorage();

/// Picks the ramp length from stored prefs.
///
/// A stored value of [legacyDefaultRampSeconds] is treated as the old unset
/// default and migrated to [defaultRampSeconds], unless [explicit] is true
/// (the user saved a ramp setting themselves). Other stored values are kept.
int resolveRampSeconds({int? stored, bool explicit = false}) {
  if (stored == null) return defaultRampSeconds;
  if (!explicit && stored == legacyDefaultRampSeconds) return defaultRampSeconds;
  return stored;
}

class AppConfig {
  AppConfig({
    this.host = '',
    this.port = 993,
    this.useSsl = true,
    this.username = '',
    this.mailbox = 'INBOX',
    this.pollSeconds = 60,
    this.rampSeconds = defaultRampSeconds,
    this.autoStopMinutes = 60,
    this.toneUri = '',
    this.toneName = '',
    this.maxAlarmStream = true,
    this.keepCpuAwake = true,
  });

  String host;
  int port;
  bool useSsl;
  String username;
  String mailbox;
  int pollSeconds;
  int rampSeconds;
  int autoStopMinutes;

  /// Empty = bundled default tone.
  String toneUri;
  String toneName;
  bool maxAlarmStream;
  bool keepCpuAwake;

  bool get hasServer => host.trim().isNotEmpty && username.trim().isNotEmpty;

  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static Future<AppConfig> load() async {
    final p = _prefs;
    final d = AppConfig();
    final storedRamp = await p.getInt(_rampSecondsKey);
    final explicitRamp = await p.getBool(_rampSecondsExplicitKey) ?? false;
    final ramp = resolveRampSeconds(stored: storedRamp, explicit: explicitRamp);
    if (storedRamp != null && storedRamp != ramp) {
      // Persist the migrated default so settings and later loads stay consistent.
      // Do not set the explicit flag — this was not a user choice.
      await p.setInt(_rampSecondsKey, ramp);
    }
    return AppConfig(
      host: await p.getString('host') ?? d.host,
      port: await p.getInt('port') ?? d.port,
      useSsl: await p.getBool('useSsl') ?? d.useSsl,
      username: await p.getString('username') ?? d.username,
      mailbox: await p.getString('mailbox') ?? d.mailbox,
      pollSeconds: await p.getInt('pollSeconds') ?? d.pollSeconds,
      rampSeconds: ramp,
      autoStopMinutes: await p.getInt('autoStopMinutes') ?? d.autoStopMinutes,
      toneUri: await p.getString('toneUri') ?? d.toneUri,
      toneName: await p.getString('toneName') ?? d.toneName,
      maxAlarmStream: await p.getBool('maxAlarmStream') ?? d.maxAlarmStream,
      keepCpuAwake: await p.getBool('keepCpuAwake') ?? d.keepCpuAwake,
    );
  }

  Future<void> save() async {
    final p = _prefs;
    await p.setString('host', host.trim());
    await p.setInt('port', port);
    await p.setBool('useSsl', useSsl);
    await p.setString('username', username.trim());
    await p.setString('mailbox', mailbox.trim().isEmpty ? 'INBOX' : mailbox.trim());
    await p.setInt('pollSeconds', pollSeconds);
    await p.setInt(_rampSecondsKey, rampSeconds);
    await p.setBool(_rampSecondsExplicitKey, true);
    await p.setInt('autoStopMinutes', autoStopMinutes);
    await p.setString('toneUri', toneUri);
    await p.setString('toneName', toneName);
    await p.setBool('maxAlarmStream', maxAlarmStream);
    await p.setBool('keepCpuAwake', keepCpuAwake);
  }

  /// Server identity; when it changes the mailbox state must be re-baselined.
  String get serverKey => '${host.trim().toLowerCase()}|$port|${username.trim().toLowerCase()}|${mailbox.trim()}';
}

Future<String?> readPassword() => secureStorage.read(key: _passwordKey);

Future<void> writePassword(String value) => secureStorage.write(key: _passwordKey, value: value);

Future<bool> hasPassword() async => (await readPassword())?.isNotEmpty ?? false;
