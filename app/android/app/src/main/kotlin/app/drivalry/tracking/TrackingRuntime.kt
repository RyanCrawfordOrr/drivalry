package app.drivalry.tracking

import android.content.Context
import android.os.BatteryManager
import android.util.Log
import java.io.File

/**
 * Process-wide owner of the tracking state: preferences, spool, event emitter and the
 * [TripStateMachine]. Both the method-channel plugin and the foreground service talk to
 * this object, so `getState` is answered synchronously from the same machine the service
 * drives, and a broadcast receiver can start a trip in a fresh process without the service
 * or the Flutter engine being up yet.
 */
class TrackingRuntime private constructor(context: Context) : TripStateMachine.Listener {
    val app: Context = context.applicationContext
    val prefs = TrackingPrefs(app)
    val spool = Spool(File(app.filesDir, "tracking"))
    val events = TrackingEvents(spool)
    val machine = TripStateMachine(prefs, events, this)

    /** Set by [TrackingService] while it runs so it can react to transitions. */
    @Volatile
    var serviceListener: TripStateMachine.Listener? = null

    // --- Triggers ---------------------------------------------------------------------------

    /**
     * An OS trigger fired (`activity` | `bluetooth` | `geofence` | `significantChange`).
     * Honours `enabled`, `pausedUntil` and the backstop cooldown; returns true when a
     * tentative trip was started.
     */
    fun trigger(kind: String): Boolean {
        val now = System.currentTimeMillis()
        if (!prefs.enabled) return false
        if (prefs.isPaused(now)) return false
        if (kind in BACKSTOP_KINDS && now < prefs.backstopCooldownUntil) return false
        if (machine.phase != TripStateMachine.Phase.IDLE) return false
        if (!Permissions.hasAnyLocation(app)) {
            events.error("permission.location", "trigger '$kind' ignored: no location permission")
            return false
        }
        return machine.startTentative(kind)
    }

    fun forceStart(): Boolean {
        if (!Permissions.hasAnyLocation(app)) {
            events.error("permission.location", "forceStartTrip ignored: no location permission")
            return false
        }
        return machine.forceActive()
    }

    fun forceEnd(): Boolean = machine.end("manual")

    fun setEnabled(enabled: Boolean) {
        prefs.enabled = enabled
        if (enabled) {
            Triggers.armAll(app, this)
        } else {
            machine.end("manual")
            Triggers.disarmAll(app)
        }
    }

    fun pauseUntil(untilMs: Long) {
        prefs.pausedUntil = untilMs.coerceAtLeast(0L)
    }

    /** Called when the app starts: make sure Play services still holds our registrations. */
    fun armIfEnabled() {
        if (prefs.enabled) Triggers.armAll(app, this)
    }

    /**
     * If the process died mid-trip and the sticky service has not been restarted yet, bring
     * it back so the persisted trip is resumed (or ended by its own timers).
     */
    fun resumeServiceIfNeeded() {
        if (machine.phase != TripStateMachine.Phase.IDLE && !TrackingService.isRunning) {
            TrackingService.start(app, this)
        }
    }

    // --- Contract maps ----------------------------------------------------------------------

    fun state(): Map<String, Any?> {
        val phase = machine.phase
        return linkedMapOf(
            "phase" to phase.wire,
            "tripId" to if (phase != TripStateMachine.Phase.IDLE) machine.tripId else null,
            "tripStartedAt" to if (phase == TripStateMachine.Phase.ACTIVE) machine.startedAt else null,
            "enabled" to prefs.enabled,
            "pausedUntil" to prefs.effectivePausedUntil(),
            "permissions" to Permissions.snapshot(app, prefs),
            "spooledEvents" to spool.count(),
        )
    }

    fun diagnostics(): Map<String, Any?> {
        val battery = app.getSystemService(BatteryManager::class.java)
            ?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            ?.takeIf { it in 0..100 }
            ?.let { it / 100.0 }
        return linkedMapOf(
            "lastTriggerAt" to prefs.lastTriggerAt,
            "lastTriggerKind" to prefs.lastTriggerKind,
            "tentativeStarts" to prefs.tentativeStarts,
            "confirmedTrips" to prefs.confirmedTrips,
            "discardedTentatives" to prefs.discardedTentatives,
            "lastTripEndedAt" to prefs.lastTripEndedAt,
            "lastTripEndReason" to prefs.lastTripEndReason,
            "batteryLevel" to battery,
            "serviceRunning" to TrackingService.isRunning,
        )
    }

    // --- TripStateMachine.Listener ------------------------------------------------------------

    override fun onTripEnding(tripId: String, reason: String) {
        serviceListener?.onTripEnding(tripId, reason)
    }

    override fun onPhaseChanged(
        from: TripStateMachine.Phase,
        to: TripStateMachine.Phase,
        tripId: String,
        reason: String,
        trigger: String?,
    ) {
        when {
            from == TripStateMachine.Phase.IDLE -> {
                // A trip began: the parking fence has done its job, and recording needs the
                // foreground service (GPS + sensors + phone-event receivers).
                Triggers.disarmParking(app)
                TrackingService.start(app, this)
            }
            to == TripStateMachine.Phase.IDLE -> {
                // Trip ended or was discarded: remember where the car is and arm the cheap
                // backstops around it. Discarded backstop triggers get a cooldown so a
                // pedestrian carrying the phone does not re-arm GPS every 100 m.
                if (reason == "unconfirmed" && trigger in BACKSTOP_KINDS) {
                    prefs.backstopCooldownUntil = System.currentTimeMillis() + BACKSTOP_COOLDOWN_MS
                }
                val spot = prefs.lastFix
                if (spot != null && prefs.enabled) {
                    prefs.parkingSpot = spot
                    Triggers.armParking(app, this, spot)
                }
            }
        }
        serviceListener?.onPhaseChanged(from, to, tripId, reason, trigger)
    }

    companion object {
        private const val TAG = "Drivalry.Tracking"
        private val BACKSTOP_KINDS = setOf("geofence", "significantChange")
        private const val BACKSTOP_COOLDOWN_MS = 10 * 60_000L

        @Volatile
        private var instance: TrackingRuntime? = null

        fun get(context: Context): TrackingRuntime =
            instance ?: synchronized(this) {
                instance ?: TrackingRuntime(context).also {
                    instance = it
                    Log.d(TAG, "runtime created, phase=${it.machine.phase.wire}")
                }
            }
    }
}
