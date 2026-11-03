package app.drivalry.tracking

import android.location.Location
import android.os.Handler
import android.os.Looper
import java.util.UUID

/**
 * The trip state machine of docs/08-tracking-channel.md §2.
 *
 * ```
 * idle ──trigger──► tentative ──speed > 4 m/s for 20 s──► active ──3 min < 1 m/s──► ended (stationary)
 *   ▲                  │                                     │──IN_VEHICLE exit, no car BT──► ended (exit)
 *   └── 120 s, unconfirmed (discarded) ◄┘                   └──forceEndTrip──────────────► ended (manual)
 * ```
 *
 * Phase, trip id, start time and trigger kind live in [TrackingPrefs], so a process that
 * is killed mid-trip and restarted by the sticky foreground service resumes the same trip
 * id. Only the short-lived evidence (how long we have been fast / stationary) is kept in
 * memory; losing it costs at most one confirmation or stationary window.
 *
 * All methods must be called on the main thread (location callbacks, receivers and the
 * method channel already are). Timers use a main-looper [Handler]; they only need to run
 * while the foreground service keeps the process alive, which is exactly when a trip is
 * in progress.
 */
class TripStateMachine(
    private val prefs: TrackingPrefs,
    private val events: TrackingEvents,
    private val listener: Listener,
) {
    enum class Phase(val wire: String) {
        IDLE("idle"), TENTATIVE("tentative"), ACTIVE("active");

        companion object {
            fun fromWire(value: String?): Phase = entries.firstOrNull { it.wire == value } ?: IDLE
        }
    }

    interface Listener {
        /**
         * Called synchronously *before* the `phase: ended` event is written, so the recorder
         * can flush fixes / motion it is holding for this trip and keep events in time order.
         */
        fun onTripEnding(tripId: String, reason: String)

        /** Called after the phase event for the transition has been emitted. */
        fun onPhaseChanged(from: Phase, to: Phase, tripId: String, reason: String, trigger: String?)
    }

    private val handler = Handler(Looper.getMainLooper())
    private val timerTick = Runnable { checkTimers(System.currentTimeMillis()) }

    // Evidence, in fix time (ms). Reset on every phase change and on process restart.
    private var fastSince: Long? = null
    private var stationarySince: Long? = null
    private var lastFixWallClock: Long? = null
    private var lastFix: FixSample? = null

    val phase: Phase get() = prefs.phase
    val tripId: String? get() = prefs.tripId
    val startedAt: Long? get() = prefs.tripStartedAt

    /** Call once when the service (re)starts with a persisted non-idle phase. */
    fun resume() {
        if (phase == Phase.IDLE) return
        resetEvidence()
        lastFixWallClock = System.currentTimeMillis()
        scheduleTimers()
    }

    /** idle → tentative. Returns false when a trip is already in progress. */
    fun startTentative(kind: String): Boolean {
        if (phase != Phase.IDLE) return false
        val now = System.currentTimeMillis()
        val id = UUID.randomUUID().toString()
        prefs.tripId = id
        prefs.phase = Phase.TENTATIVE
        prefs.tentativeAt = now
        prefs.tripStartedAt = null
        prefs.tripTrigger = kind
        prefs.vehicleExitPending = false
        prefs.incrementTentativeStarts()
        prefs.lastTriggerAt = now
        prefs.lastTriggerKind = kind
        resetEvidence()
        lastFixWallClock = now
        events.phase(id, "tentative", kind, t = now)
        listener.onPhaseChanged(Phase.IDLE, Phase.TENTATIVE, id, kind, kind)
        scheduleTimers()
        return true
    }

    /**
     * `forceStartTrip`: straight to active. From idle a new trip id is created; a tentative
     * trip is confirmed on the spot. Returns false when already active.
     */
    fun forceActive(): Boolean {
        val now = System.currentTimeMillis()
        return when (phase) {
            Phase.ACTIVE -> false
            Phase.TENTATIVE -> {
                confirm(now, "manual")
                true
            }
            Phase.IDLE -> {
                val id = UUID.randomUUID().toString()
                prefs.tripId = id
                prefs.phase = Phase.TENTATIVE // transiently, so confirm() sees a consistent from-phase
                prefs.tentativeAt = now
                prefs.tripTrigger = "manual"
                prefs.vehicleExitPending = false
                prefs.incrementTentativeStarts()
                prefs.lastTriggerAt = now
                prefs.lastTriggerKind = "manual"
                resetEvidence()
                lastFixWallClock = now
                // Dart sees idle → active directly: the §2 diagram allows forceStartTrip to
                // skip tentative, and emitting a tentative phase here would be noise.
                listener.onPhaseChanged(Phase.IDLE, Phase.TENTATIVE, id, "manual", "manual")
                confirm(now, "manual")
                true
            }
        }
    }

    /**
     * Feed one fix. [speedMps] is null when the OS reports no speed; the machine then derives
     * one from consecutive accurate fixes, and failing that treats the fix as "not moving"
     * (the only fixes without speed come from network/Wi-Fi positioning, i.e. GPS is lost,
     * which in practice means indoors or parked).
     */
    fun onFix(t: Long, lat: Double, lon: Double, accuracyM: Float?, speedMps: Double?) {
        if (phase == Phase.IDLE) return
        val now = System.currentTimeMillis()
        lastFixWallClock = now
        val sample = FixSample(t, lat, lon, accuracyM)
        val speed = speedMps ?: derivedSpeed(lastFix, sample)
        lastFix = sample

        when (phase) {
            Phase.TENTATIVE -> {
                if (speed != null && speed > CONFIRM_SPEED_MPS) {
                    val since = fastSince ?: t.also { fastSince = it }
                    if (t - since >= CONFIRM_DURATION_MS) {
                        confirm(since, prefs.tripTrigger ?: "activity")
                        return
                    }
                } else {
                    fastSince = null
                }
                checkTimers(now)
            }
            Phase.ACTIVE -> {
                if (speed == null || speed < STATIONARY_SPEED_MPS) {
                    val since = stationarySince ?: t.also { stationarySince = it }
                    if (t - since >= STATIONARY_DURATION_MS) {
                        end("stationary")
                        return
                    }
                } else {
                    stationarySince = null
                }
                scheduleTimers()
            }
            Phase.IDLE -> Unit
        }
    }

    /** IN_VEHICLE ENTER while a trip is running cancels a pending exit. */
    fun onVehicleEnter() {
        if (phase != Phase.IDLE) prefs.vehicleExitPending = false
    }

    /**
     * IN_VEHICLE EXIT: ends the trip unless a car Bluetooth device is still connected, in
     * which case the exit is remembered and applied when that device disconnects (or the
     * stationary rule ends the trip first).
     */
    fun onVehicleExit() {
        if (phase != Phase.ACTIVE) return
        if (prefs.carBluetoothConnected) {
            prefs.vehicleExitPending = true
        } else {
            end("exit")
        }
    }

    fun onCarBluetoothDisconnected() {
        if (phase == Phase.ACTIVE && prefs.vehicleExitPending && !prefs.carBluetoothConnected) {
            end("exit")
        }
    }

    /**
     * Ends the current trip with [reason] (`stationary` | `exit` | `manual`). A tentative
     * trip has nothing worth keeping, so ending it discards it instead. Returns false when idle.
     */
    fun end(reason: String): Boolean {
        val id = tripId ?: return false
        when (phase) {
            Phase.IDLE -> return false
            Phase.TENTATIVE -> {
                discard()
                return true
            }
            Phase.ACTIVE -> Unit
        }
        val now = System.currentTimeMillis()
        val trigger = prefs.tripTrigger
        handler.removeCallbacks(timerTick)
        listener.onTripEnding(id, reason)
        events.phase(id, "ended", reason, t = now)
        prefs.lastTripEndedAt = now
        prefs.lastTripEndReason = reason
        prefs.clearTrip()
        resetEvidence()
        listener.onPhaseChanged(Phase.ACTIVE, Phase.IDLE, id, reason, trigger)
        return true
    }

    /** Timer-driven checks; also run on each fix. Safe to call at any time. */
    fun checkTimers(now: Long) {
        when (phase) {
            Phase.IDLE -> return
            Phase.TENTATIVE -> {
                val since = prefs.tentativeAt ?: now.also { prefs.tentativeAt = it }
                if (now - since >= TENTATIVE_TIMEOUT_MS) {
                    discard()
                    return
                }
            }
            Phase.ACTIVE -> {
                val since = stationarySince
                if (since != null && now - since >= STATIONARY_DURATION_MS) {
                    end("stationary")
                    return
                }
                // No fix at all for a long time means the receiver cannot see the sky and the
                // phone is not moving in a way we can record. Ending here keeps GPS from
                // burning in a parking garage; a new trip starts on the next trigger.
                val lastSeen = lastFixWallClock
                if (lastSeen != null && now - lastSeen >= NO_FIX_TIMEOUT_MS) {
                    end("stationary")
                    return
                }
            }
        }
        scheduleTimers()
    }

    // --- internals --------------------------------------------------------------------------

    private fun confirm(startedAt: Long, reason: String) {
        val id = tripId ?: return
        prefs.phase = Phase.ACTIVE
        prefs.tripStartedAt = startedAt
        prefs.incrementConfirmedTrips()
        fastSince = null
        stationarySince = null
        events.phase(id, "active", reason, startedAt = startedAt)
        listener.onPhaseChanged(Phase.TENTATIVE, Phase.ACTIVE, id, reason, prefs.tripTrigger)
        scheduleTimers()
    }

    private fun discard() {
        val id = tripId ?: return
        val trigger = prefs.tripTrigger
        handler.removeCallbacks(timerTick)
        events.phase(id, "discarded", "unconfirmed")
        prefs.incrementDiscardedTentatives()
        prefs.clearTrip()
        resetEvidence()
        listener.onPhaseChanged(Phase.TENTATIVE, Phase.IDLE, id, "unconfirmed", trigger)
    }

    /**
     * Posts a single wake-up for the earliest deadline instead of polling: fewer CPU wake-ups
     * while the batched location stream is the only thing keeping the device awake.
     */
    private fun scheduleTimers() {
        handler.removeCallbacks(timerTick)
        val now = System.currentTimeMillis()
        val deadline: Long = when (phase) {
            Phase.IDLE -> return
            Phase.TENTATIVE -> (prefs.tentativeAt ?: now) + TENTATIVE_TIMEOUT_MS
            Phase.ACTIVE -> {
                val stationaryDeadline = stationarySince?.plus(STATIONARY_DURATION_MS)
                val fixDeadline = (lastFixWallClock ?: now) + NO_FIX_TIMEOUT_MS
                minOf(stationaryDeadline ?: Long.MAX_VALUE, fixDeadline)
            }
        }
        handler.postDelayed(timerTick, (deadline - now).coerceAtLeast(0L) + TIMER_SLACK_MS)
    }

    private fun resetEvidence() {
        fastSince = null
        stationarySince = null
        lastFix = null
    }

    private fun derivedSpeed(previous: FixSample?, current: FixSample): Double? {
        if (previous == null) return null
        val dtMs = current.t - previous.t
        if (dtMs <= 0 || dtMs > DERIVED_SPEED_MAX_GAP_MS) return null
        val prevAcc = previous.accuracyM ?: return null
        val curAcc = current.accuracyM ?: return null
        if (prevAcc > DERIVED_SPEED_MAX_ACCURACY_M || curAcc > DERIVED_SPEED_MAX_ACCURACY_M) return null
        val results = FloatArray(1)
        Location.distanceBetween(previous.lat, previous.lon, current.lat, current.lon, results)
        return results[0].toDouble() / (dtMs / 1000.0)
    }

    private data class FixSample(val t: Long, val lat: Double, val lon: Double, val accuracyM: Float?)

    companion object {
        const val CONFIRM_SPEED_MPS = 4.0
        const val CONFIRM_DURATION_MS = 20_000L
        const val TENTATIVE_TIMEOUT_MS = 120_000L
        const val STATIONARY_SPEED_MPS = 1.0
        const val STATIONARY_DURATION_MS = 180_000L
        const val NO_FIX_TIMEOUT_MS = 300_000L
        private const val TIMER_SLACK_MS = 500L
        private const val DERIVED_SPEED_MAX_GAP_MS = 10_000L
        private const val DERIVED_SPEED_MAX_ACCURACY_M = 50f
    }
}
