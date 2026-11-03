package app.drivalry.tracking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors `app/test/crash_detector_test.dart`; the two detectors must agree. */
class CrashDetectorTest {
    private fun drive(
        d: CrashDetector,
        cruise: Double = 15.0,
        peak: Double = 45.0,
        after: Double = 0.0,
        t0: Long = 1_000_000L,
    ): CrashDetector.Candidate? {
        var t = t0
        repeat(10) {
            d.onSpeed(t, cruise)
            t += 1000
        }
        d.onAccel(t - 500, peak)
        var fired: CrashDetector.Candidate? = null
        repeat(8) {
            if (fired == null) fired = d.onSpeed(t, after)
            t += 1000
        }
        return fired
    }

    @Test
    fun hardImpactAtSpeedThenDeadStopFiresOnce() {
        val d = CrashDetector()
        val c = drive(d)
        assertNotNull(c)
        assertEquals(45.0, c!!.peakMps2, 0.0)
        assertEquals(15.0, c.speedBeforeMps, 0.0)
        assertTrue(d.fired)
        assertNull(drive(d, t0 = 2_000_000L))
        d.reset()
        assertNotNull(drive(d, t0 = 3_000_000L))
    }

    @Test
    fun speedBumpAtParkingSpeedNeverCounts() {
        assertNull(drive(CrashDetector(), cruise = 3.0, peak = 60.0))
    }

    @Test
    fun droppedPhoneAtStandstillNeverCounts() {
        val d = CrashDetector()
        assertNull(drive(d, cruise = 0.0, peak = 80.0))
        assertFalse(d.isPending)
    }

    @Test
    fun potholeIsCancelledWhenMovementResumes() {
        assertNull(drive(CrashDetector(), after = 6.0))
    }

    @Test
    fun peakUnderThresholdIsIgnored() {
        assertNull(drive(CrashDetector(), peak = 30.0))
    }

    @Test
    fun confirmationNeedsFullWindowAndTwoStoppedSamples() {
        val d = CrashDetector()
        var t = 0L
        repeat(5) {
            d.onSpeed(t, 20.0)
            t += 1000
        }
        assertTrue(d.onAccel(t - 500, 50.0))
        assertNull(d.onSpeed(t, 0.2))
        assertNull(d.onSpeed(t + 3000, 0.0))
        val c = d.onSpeed(t + 5000, 0.0)
        assertNotNull(c)
        assertEquals(t - 500, c!!.t)
    }

    @Test
    fun fixesWithoutSpeedAfterImpactCountAsStopped() {
        val d = CrashDetector()
        var t = 1_000_000L
        repeat(5) {
            d.onSpeed(t, 15.0)
            t += 1000
        }
        assertTrue(d.onAccel(t, 50.0))
        assertNull(d.onSpeed(t + 1000, null))
        val c = d.onSpeed(t + 5000, null)
        assertNotNull(c)
        assertEquals(15.0, c!!.speedBeforeMps, 0.0)
        assertTrue(d.fired)
    }

    @Test
    fun noFixesAfterImpactGivesUp() {
        val d = CrashDetector()
        var t = 0L
        repeat(5) {
            d.onSpeed(t, 20.0)
            t += 1000
        }
        d.onAccel(t, 50.0)
        assertNull(d.onSpeed(t + 2000, null))
        assertNull(d.onSpeed(t + 9000, null))
        assertFalse(d.isPending)
        assertFalse(d.fired)
    }
}
