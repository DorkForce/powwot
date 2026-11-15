/// UI-side bridge to the Android code (MainActivity "powwot/app" channel).
library;

import 'package:flutter/services.dart';

class NativeApp {
  static const _ch = MethodChannel('powwot/app');

  static Future<void> startMonitoring() => _ch.invokeMethod('startMonitoring');
  static Future<void> stopMonitoring() => _ch.invokeMethod('stopMonitoring');
  static Future<void> pollNow() => _ch.invokeMethod('pollNow');
  static Future<void> reloadConfig() => _ch.invokeMethod('reloadConfig');
  static Future<bool> isMonitoring() async => await _ch.invokeMethod<bool>('isMonitoring') ?? false;
  static Future<bool> isAlarmActive() async => await _ch.invokeMethod<bool>('isAlarmActive') ?? false;
  static Future<void> dismissAlarm() => _ch.invokeMethod('dismissAlarm');
  static Future<void> setKeepCpuAwake(bool v) => _ch.invokeMethod('setKeepCpuAwake', {'value': v});

  static Future<void> testAlarm({required String toneUri, required int rampSeconds, required bool maxStream}) =>
      _ch.invokeMethod('testAlarm', {'toneUri': toneUri, 'rampSeconds': rampSeconds, 'maxStream': maxStream});

  static Future<Map<String, bool>> permissionStatus() async {
    final m = await _ch.invokeMapMethod<String, bool>('permissionStatus');
    return m ?? {};
  }

  static Future<void> requestNotifications() => _ch.invokeMethod('requestNotifications');
  static Future<void> openDndAccess() => _ch.invokeMethod('openDndAccess');
  static Future<void> requestBatteryExemption() => _ch.invokeMethod('requestBatteryExemption');
  static Future<void> openFullScreenIntentSettings() => _ch.invokeMethod('openFullScreenIntentSettings');

  /// Returns {uri, title} or null if cancelled.
  static Future<Map<String, String>?> pickAlarmTone(String current) =>
      _ch.invokeMapMethod<String, String>('pickAlarmTone', {'current': current});
}
