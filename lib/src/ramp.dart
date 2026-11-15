/// Alarm volume ramp. Mirrors android/.../RampMath.kt (the native side applies it).
library;

/// Volume in 0.0..1.0 after [elapsed], ramping linearly over [rampSeconds].
/// A ramp of 0 (or less) means full volume immediately.
double rampVolume(Duration elapsed, int rampSeconds) {
  if (rampSeconds <= 0) return 1.0;
  if (elapsed <= Duration.zero) return 0.0;
  final f = elapsed.inMilliseconds / (rampSeconds * 1000.0);
  return f.clamp(0.0, 1.0).toDouble();
}

/// Time until the ramp reaches [volume] (0..1).
Duration timeToVolume(double volume, int rampSeconds) {
  if (rampSeconds <= 0) return Duration.zero;
  final v = volume.clamp(0.0, 1.0);
  return Duration(milliseconds: (v * rampSeconds * 1000).round());
}
