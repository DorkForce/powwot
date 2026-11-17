import 'package:flutter_test/flutter_test.dart';
import 'package:powwot/src/config.dart';

void main() {
  group('resolveRampSeconds', () {
    test('new installs get the 5-minute default', () {
      expect(resolveRampSeconds(), defaultRampSeconds);
      expect(resolveRampSeconds(stored: null), 300);
    });
    test('migrates the old 100 s default when it was never explicitly set', () {
      expect(resolveRampSeconds(stored: 100), 300);
      expect(resolveRampSeconds(stored: legacyDefaultRampSeconds, explicit: false), 300);
    });
    test('keeps an explicit user choice of 100 s', () {
      expect(resolveRampSeconds(stored: 100, explicit: true), 100);
    });
    test('keeps other stored values, explicit or not', () {
      expect(resolveRampSeconds(stored: 30), 30);
      expect(resolveRampSeconds(stored: 60, explicit: false), 60);
      expect(resolveRampSeconds(stored: 600, explicit: true), 600);
      expect(resolveRampSeconds(stored: 0, explicit: true), 0);
      expect(resolveRampSeconds(stored: 300), 300);
    });
  });
}
