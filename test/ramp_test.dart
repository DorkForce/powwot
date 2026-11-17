import 'package:flutter_test/flutter_test.dart';
import 'package:powwot/src/config.dart';
import 'package:powwot/src/ramp.dart';

void main() {
  group('rampVolume', () {
    test('0 at start, 100% at end of a 100 s ramp', () {
      expect(rampVolume(Duration.zero, 100), 0.0);
      expect(rampVolume(const Duration(seconds: 100), 100), 1.0);
    });
    test('linear in between', () {
      expect(rampVolume(const Duration(seconds: 25), 100), closeTo(0.25, 1e-9));
      expect(rampVolume(const Duration(seconds: 50), 100), closeTo(0.5, 1e-9));
      expect(rampVolume(const Duration(milliseconds: 99900), 100), closeTo(0.999, 1e-9));
    });
    test('clamped after the ramp and before start', () {
      expect(rampVolume(const Duration(minutes: 30), 100), 1.0);
      expect(rampVolume(const Duration(seconds: -3), 100), 0.0);
    });
    test('configurable ramp length', () {
      expect(rampVolume(const Duration(seconds: 15), 30), closeTo(0.5, 1e-9));
      expect(rampVolume(const Duration(seconds: 150), 300), closeTo(0.5, 1e-9));
    });
    test('zero ramp means full volume immediately', () {
      expect(rampVolume(Duration.zero, 0), 1.0);
      expect(rampVolume(Duration.zero, -5), 1.0);
    });
  });
  test('timeToVolume inverts the ramp', () {
    expect(timeToVolume(0.5, 100), const Duration(seconds: 50));
    expect(timeToVolume(1.0, 100), const Duration(seconds: 100));
    expect(timeToVolume(2.0, 100), const Duration(seconds: 100));
    expect(timeToVolume(0.5, 0), Duration.zero);
  });

  group('five-minute default ramp', () {
    const ramp = defaultRampSeconds;
    test('starts silent and reaches max at 5:00', () {
      expect(ramp, 300);
      expect(rampVolume(Duration.zero, ramp), 0.0);
      expect(rampVolume(const Duration(minutes: 5), ramp), 1.0);
    });
    test('linear through the five minutes', () {
      expect(rampVolume(const Duration(seconds: 75), ramp), closeTo(0.25, 1e-9));
      expect(rampVolume(const Duration(minutes: 2, seconds: 30), ramp), closeTo(0.5, 1e-9));
      expect(rampVolume(const Duration(milliseconds: 299000), ramp), closeTo(299 / 300, 1e-9));
    });
    test('timeToVolume hits 5:00 at full volume', () {
      expect(timeToVolume(0.0, ramp), Duration.zero);
      expect(timeToVolume(0.5, ramp), const Duration(minutes: 2, seconds: 30));
      expect(timeToVolume(1.0, ramp), const Duration(minutes: 5));
    });
  });
}
