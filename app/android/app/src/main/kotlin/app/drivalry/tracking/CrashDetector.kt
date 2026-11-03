package app.drivalry.tracking

import java.util.ArrayDeque

/**
 * docs/08-tracking-channel.md §4 `crashCandidate`, as a pure rule with no Android types, so it
 * can be unit-tested and mirrors the Swift and Dart copies line for line.
 *
 * Three things must hold inside one window: a linear-acceleration peak of at least
 * [peakThresholdMps2] (about 4 g); GPS speed of at least [speedBeforeMinMps] somewhere in the
 * [beforeWindowMs] before the peak (a dropped phone at a standstill or a speed bump at parking
 * speed never counts); and every GPS fix in the [afterWindowMs] after the peak below
 * [speedAfterMaxMps] (a fix without a speed counts as stopped), with at least [minAfterSamples]
 * such fixes. Fires at most once per trip.
 *
 * Thread-safe: accelerometer samples arrive on the sensor thread, speeds on the main thread.
 */
class CrashDetector(
    private val peakThresholdMps2: Double = 40.0,
    private val speedBeforeMinMps: Double = 8.0,
    private val speedAfterMaxMps: Double = 1.0,
    private val beforeWindowMs: Long = 3_000L,
    private val afterWindowMs: Long = 5_000L,
    private val giveUpMs: Long = 8_000L,
    private val historyMs: Long = 10_000L,
    private val minAfterSamples: Int = 2,
) {
    data class Candidate(val t: Long, val peakMps2: Double, val speedBeforeMps: Double)

    private class Pending(var t: Long, var peak: Double, val speedBefore: Double) {
        var afterSamples = 0
    }

    private val lock = Any()
    private val speeds = ArrayDeque<Pair<Long, Double>>()
    private var pending: Pending? = null

    @Volatile
    var fired: Boolean = false
        private set

    val isPending: Boolean
        get() = synchronized(lock) { pending != null }

    /** Call at every trip start and end. */
    fun reset() = synchronized(lock) {
        speeds.clear()
        pending = null
        fired = false
    }

    /**
     * One linear-acceleration sample. Returns true when this sample opened a new candidate: the
     * caller may then ask the location provider to flush its batch so the confirmation (or the
     * all-clear) arrives without the usual 15 s delivery delay.
     */
    fun onAccel(t: Long, magnitudeMps2: Double): Boolean = synchronized(lock) {
        if (fired || magnitudeMps2 < peakThresholdMps2) return false
        trim(t)
        val before = maxSpeedBetween(t - beforeWindowMs, t) ?: return false
        if (before < speedBeforeMinMps) return false
        val p = pending
        if (p != null) {
            if (magnitudeMps2 > p.peak) {
                p.peak = magnitudeMps2
                p.t = t
            }
            return false
        }
        pending = Pending(t, magnitudeMps2, before)
        true
    }

    /** One GPS speed sample (null when the OS has no speed). Returns the confirmed candidate. */
    fun onSpeed(t: Long, speedMps: Double?): Candidate? = synchronized(lock) {
        if (speedMps != null) {
            speeds.addLast(t to speedMps)
            trim(t)
        }
        val p = pending ?: return null
        if (fired) return null
        if (t <= p.t) return null // a fix from before the impact, delivered late
        if (t > p.t + giveUpMs) {
            pending = null // never confirmed: still moving, or no fixes at all
            return null
        }
        // No speed is what the OS reports at a standstill: counts as stopped evidence here
        // (the before-window above still only trusts fixes that carry a speed).
        val v = speedMps ?: 0.0
        if (v >= speedAfterMaxMps) {
            pending = null // moving again: a pothole, not a crash
            return null
        }
        p.afterSamples++
        if (t >= p.t + afterWindowMs && p.afterSamples >= minAfterSamples) {
            fired = true
            pending = null
            return Candidate(p.t, p.peak, p.speedBefore)
        }
        null
    }

    private fun maxSpeedBetween(from: Long, to: Long): Double? {
        var best: Double? = null
        for ((t, v) in speeds) {
            if (t < from || t > to) continue
            if (best == null || v > best) best = v
        }
        return best
    }

    private fun trim(now: Long) {
        while (speeds.isNotEmpty() && speeds.first().first < now - historyMs) speeds.removeFirst()
    }
}
