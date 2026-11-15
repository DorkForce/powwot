package com.dorkforce.powwot

/**
 * Alarm volume ramp. Mirrors lib/src/ramp.dart (both are unit tested).
 * Linear from 0.0 to 1.0 over [rampSeconds]; a ramp of 0 means full volume at once.
 */
object RampMath {
    fun volumeAt(elapsedMs: Long, rampSeconds: Int): Float {
        if (rampSeconds <= 0) return 1f
        if (elapsedMs <= 0L) return 0f
        val f = elapsedMs.toDouble() / (rampSeconds * 1000.0)
        return f.coerceIn(0.0, 1.0).toFloat()
    }
}
