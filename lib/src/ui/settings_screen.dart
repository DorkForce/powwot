import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../imap_checker.dart';
import '../native.dart';
import '../status_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  AppConfig? _cfg;
  bool _hasSavedPassword = false;
  bool _showPassword = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _mailbox = TextEditingController();
  final _poll = TextEditingController();
  final _ramp = TextEditingController();
  final _window = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _pass, _mailbox, _poll, _ramp, _window]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final c = await AppConfig.load();
    final has = await hasPassword();
    setState(() {
      _cfg = c;
      _hasSavedPassword = has;
      _host.text = c.host;
      _port.text = '${c.port}';
      _user.text = c.username;
      _mailbox.text = c.mailbox;
      _poll.text = '${c.pollSeconds}';
      _ramp.text = '${c.rampSeconds}';
      _window.text = '${c.autoStopMinutes}';
    });
  }

  /// Copies form fields into a config (without saving).
  AppConfig _fromForm() {
    final c = _cfg!;
    return AppConfig(
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? (c.useSsl ? 993 : 143),
      useSsl: c.useSsl,
      username: _user.text.trim(),
      mailbox: _mailbox.text.trim().isEmpty ? 'INBOX' : _mailbox.text.trim(),
      pollSeconds: int.tryParse(_poll.text) ?? 60,
      rampSeconds: int.tryParse(_ramp.text) ?? 100,
      autoStopMinutes: int.tryParse(_window.text) ?? 60,
      toneUri: c.toneUri,
      toneName: c.toneName,
      maxAlarmStream: c.maxAlarmStream,
      keepCpuAwake: c.keepCpuAwake,
    );
  }

  Future<String?> _effectivePassword() async => _pass.text.isNotEmpty ? _pass.text : await readPassword();

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final c = _fromForm();
    await c.save();
    if (_pass.text.isNotEmpty) {
      await writePassword(_pass.text);
      _pass.clear();
    }
    await NativeApp.setKeepCpuAwake(c.keepCpuAwake);
    await NativeApp.reloadConfig();
    await StatusStore.log('Settings saved');
    if (!mounted) return;
    final has = await hasPassword();
    if (!mounted) return;
    setState(() {
      _cfg = c;
      _hasSavedPassword = has;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _testConnection() async {
    final c = _fromForm();
    final pw = await _effectivePassword();
    if (!c.hasServer || pw == null || pw.isEmpty) {
      setState(() {
        _testOk = false;
        _testResult = 'Enter host, username and password first.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final s = await ImapSession.open(c, pw);
      try {
        final snap = await s.select(c.mailbox);
        _testOk = true;
        _testResult = 'Connected. ${c.mailbox}: ${snap.messageCount} messages (highest UID ${snap.highestUid}).';
      } finally {
        await s.close();
      }
    } catch (e) {
      _testOk = false;
      _testResult = 'Failed: ${describeError(e, secret: pw)}';
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _testAlarm() async {
    final c = _fromForm();
    await NativeApp.testAlarm(toneUri: c.toneUri, rampSeconds: c.rampSeconds, maxStream: c.maxAlarmStream);
    await StatusStore.log('Test alarm started (ramp ${c.rampSeconds}s)');
  }

  Future<void> _pickTone() async {
    final r = await NativeApp.pickAlarmTone(_cfg!.toneUri);
    if (r == null) return;
    setState(() {
      _cfg!
        ..toneUri = r['uri'] ?? ''
        ..toneName = r['title'] ?? 'System tone';
    });
  }

  String? _intIn(String? v, int min, int max) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < min || n > max) return 'Enter $min-$max';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = _cfg;
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [TextButton(onPressed: _save, child: const Text('SAVE'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('IMAP mailbox', style: Theme.of(context).textTheme.titleMedium),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'IMAP host'),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _port,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    validator: (v) => _intIn(v, 1, 65535),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('SSL/TLS'),
                    subtitle: Text(c.useSsl ? 'Implicit TLS' : 'STARTTLS'),
                    value: c.useSsl,
                    onChanged: (v) => setState(() {
                      c.useSsl = v;
                      if (v && _port.text == '143') _port.text = '993';
                      if (!v && _port.text == '993') _port.text = '143';
                    }),
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'Username'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _pass,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _hasSavedPassword
                    ? 'A password is saved (encrypted on this phone). Leave blank to keep it.'
                    : 'Stored only on this phone, encrypted with the Android Keystore.',
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) => (!_hasSavedPassword && (v == null || v.isEmpty)) ? 'Required' : null,
            ),
            TextFormField(
              controller: _mailbox,
              decoration: const InputDecoration(labelText: 'Folder', hintText: 'INBOX'),
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test connection'),
                ),
              ],
            ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _testResult!,
                  style: TextStyle(color: _testOk ? Colors.green : Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(height: 32),
            Text('Checking & alarm', style: Theme.of(context).textTheme.titleMedium),
            TextFormField(
              controller: _poll,
              decoration: const InputDecoration(
                labelText: 'Poll interval (seconds)',
                helperText: '15-3600, default 60',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              validator: (v) => _intIn(v, 15, 3600),
            ),
            TextFormField(
              controller: _ramp,
              decoration: const InputDecoration(
                labelText: 'Volume ramp (seconds, 0 to 100%)',
                helperText: '0-3600, default 100; 0 = full volume at once',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              validator: (v) => _intIn(v, 0, 3600),
            ),
            TextFormField(
              controller: _window,
              decoration: const InputDecoration(
                labelText: 'Auto-stop window (minutes)',
                helperText: 'A POWER ON email within this time after POWER OFF stops the alarm. Default 60',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              validator: (v) => _intIn(v, 1, 10080),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alarm sound'),
              subtitle: Text(c.toneUri.isEmpty ? 'powwot default (bundled)' : c.toneName),
              trailing: Wrap(
                spacing: 4,
                children: [
                  if (c.toneUri.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        c.toneUri = '';
                        c.toneName = '';
                      }),
                      child: const Text('Default'),
                    ),
                  TextButton(onPressed: _pickTone, child: const Text('Pick system tone')),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Raise alarm volume to max while ringing'),
              subtitle: const Text('Restored afterwards. The ramp then goes from silent to the loudest level.'),
              value: c.maxAlarmStream,
              onChanged: (v) => setState(() => c.maxAlarmStream = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep CPU awake while monitoring'),
              subtitle: const Text('Most reliable timing; uses some extra battery.'),
              value: c.keepCpuAwake,
              onChanged: (v) => setState(() => c.keepCpuAwake = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _testAlarm,
                  icon: const Icon(Icons.alarm),
                  label: const Text('Test alarm'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save settings')),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
