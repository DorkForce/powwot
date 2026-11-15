package com.dorkforce.powwot

import org.junit.Assert.assertEquals
import org.junit.Test

class RampMathTest {
    @Test fun startsSilent() = assertEquals(0f, RampMath.volumeAt(0, 100), 0f)
    @Test fun halfway() = assertEquals(0.5f, RampMath.volumeAt(50_000, 100), 1e-6f)
    @Test fun fullAtEnd() = assertEquals(1f, RampMath.volumeAt(100_000, 100), 0f)
    @Test fun clampsAfterEnd() = assertEquals(1f, RampMath.volumeAt(500_000, 100), 0f)
    @Test fun zeroRampIsFull() = assertEquals(1f, RampMath.volumeAt(0, 0), 0f)
    @Test fun negativeElapsedIsSilent() = assertEquals(0f, RampMath.volumeAt(-5, 100), 0f)
    @Test fun customRamp() = assertEquals(0.25f, RampMath.volumeAt(7_500, 30), 1e-6f)
}
