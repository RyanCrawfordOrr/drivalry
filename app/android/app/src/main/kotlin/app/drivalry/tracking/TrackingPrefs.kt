package app.drivalry.tracking

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

/**
 * Everything the tracking plugin persists, in the `drivalry_tracking` SharedPreferences
 * file named by docs/08-tracking-channel.md §6: user settings, the current trip (so a
 * process restart resumes it), diagnostics counters and the parking spot used by the
 * geofence / passive backstops.
 */
class TrackingPrefs(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    // --- Settings (§3 setEnabled / pauseUntil) --------------------------------------

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit { putBoolean(KEY_ENABLED, value) }

    /** Raw stored value; use [effectivePausedUntil] for the contract value. */
    var pausedUntil: Long
        get() = prefs.getLong(KEY_PAUSED_UNTIL, 0L)
        set(value) = prefs.edit { putLong(KEY_PAUSED_UNTIL, value) }

    /** `0` when not paused or when the pause has already elapsed. */
    fun effectivePausedUntil(now: Long = System.currentTimeMillis()): Long {
        val until = pausedUntil
        if (until != 0L && until <= now) {
            pausedUntil = 0L
            return 0L
        }
        return until
    }

    fun isPaused(now: Long = System.currentTimeMillis()): Boolean = effectivePausedUntil(now) > now

    // --- Current trip (§2) -------------------------------------------------------------

    var phase: TripStateMachine.Phase
        get() = TripStateMachine.Phase.fromWire(prefs.getString(KEY_PHASE, null))
        set(value) = prefs.edit { putString(KEY_PHASE, value.wire) }

    var tripId: String?
        get() = prefs.getString(KEY_TRIP_ID, null)
        set(value) = prefs.edit { putString(KEY_TRIP_ID, value) }

    /** Time of the first confirmed fix; only meaningful while `phase == ACTIVE`. */
    var tripStartedAt: Long?
        get() = prefs.getLong(KEY_TRIP_STARTED_AT, -1L).takeIf { it >= 0 }
        set(value) = prefs.edit { putLong(KEY_TRIP_STARTED_AT, value ?: -1L) }

    /** Wall-clock time the trip became tentative; drives the 120 s discard timeout. */
    var tentativeAt: Long?
        get() = prefs.getLong(KEY_TENTATIVE_AT, -1L).takeIf { it >= 0 }
        set(value) = prefs.edit { putLong(KEY_TENTATIVE_AT, value ?: -1L) }

    /** Trigger kind that started the current trip (`reason` of the phase events). */
    var tripTrigger: String?
        get() = prefs.getString(KEY_TRIP_TRIGGER, null)
        set(value) = prefs.edit { putString(KEY_TRIP_TRIGGER, value) }

    /** An IN_VEHICLE EXIT arrived while car Bluetooth was still connected. */
    var vehicleExitPending: Boolean
        get() = prefs.getBoolean(KEY_EXIT_PENDING, false)
        set(value) = prefs.edit { putBoolean(KEY_EXIT_PENDING, value) }

    fun clearTrip() = prefs.edit {
        putString(KEY_PHASE, TripStateMachine.Phase.IDLE.wire)
        remove(KEY_TRIP_ID)
        remove(KEY_TRIP_STARTED_AT)
        remove(KEY_TENTATIVE_AT)
        remove(KEY_TRIP_TRIGGER)
        remove(KEY_EXIT_PENDING)
    }

    // --- Car Bluetooth (exit rule, §2) ----------------------------------------------------

    /** Addresses of currently connected car-like Bluetooth devices. */
    var connectedCarDevices: Set<String>
        get() = prefs.getStringSet(KEY_CAR_BT, emptySet())?.toSet() ?: emptySet()
        set(value) = prefs.edit { putStringSet(KEY_CAR_BT, value) }

    val carBluetoothConnected: Boolean get() = connectedCarDevices.isNotEmpty()

    // --- Parking spot for the geofence / passive backstops ----------------------------------

    var lastFix: LatLon?
        get() {
            if (!prefs.contains(KEY_LAST_LAT)) return null
            return LatLon(
                java.lang.Double.longBitsToDouble(prefs.getLong(KEY_LAST_LAT, 0L)),
                java.lang.Double.longBitsToDouble(prefs.getLong(KEY_LAST_LON, 0L)),
            )
        }
        set(value) = prefs.edit {
            if (value == null) {
                remove(KEY_LAST_LAT); remove(KEY_LAST_LON)
            } else {
                putLong(KEY_LAST_LAT, java.lang.Double.doubleToRawLongBits(value.lat))
                putLong(KEY_LAST_LON, java.lang.Double.doubleToRawLongBits(value.lon))
            }
        }

    /** Where the parking geofence is currently centred (null when none is armed). */
    var parkingSpot: LatLon?
        get() {
            if (!prefs.contains(KEY_PARK_LAT)) return null
            return LatLon(
                java.lang.Double.longBitsToDouble(prefs.getLong(KEY_PARK_LAT, 0L)),
                java.lang.Double.longBitsToDouble(prefs.getLong(KEY_PARK_LON, 0L)),
            )
        }
        set(value) = prefs.edit {
            if (value == null) {
                remove(KEY_PARK_LAT); remove(KEY_PARK_LON)
            } else {
                putLong(KEY_PARK_LAT, java.lang.Double.doubleToRawLongBits(value.lat))
                putLong(KEY_PARK_LON, java.lang.Double.doubleToRawLongBits(value.lon))
            }
        }

    /**
     * After a geofence / significant-change trigger is discarded, those two backstops are
     * ignored until this time so a pedestrian does not re-arm GPS every 100 m.
     */
    var backstopCooldownUntil: Long
        get() = prefs.getLong(KEY_BACKSTOP_COOLDOWN, 0L)
        set(value) = prefs.edit { putLong(KEY_BACKSTOP_COOLDOWN, value) }

    // --- Parked presence (§4 parkedFix) --------------------------------------------------------

    /**
     * Wall-clock time of the last `parkedFix` event. Persisted because each passive /
     * geofence delivery may wake a fresh process; the one-per-60 s rate limit must survive that.
     */
    var lastParkedFixAt: Long
        get() = prefs.getLong(KEY_LAST_PARKED_FIX_AT, 0L)
        set(value) = prefs.edit { putLong(KEY_LAST_PARKED_FIX_AT, value) }

    // --- Diagnostics (§3.3) -----------------------------------------------------------------

    var lastTriggerAt: Long?
        get() = prefs.getLong(KEY_LAST_TRIGGER_AT, -1L).takeIf { it >= 0 }
        set(value) = prefs.edit { putLong(KEY_LAST_TRIGGER_AT, value ?: -1L) }

    var lastTriggerKind: String?
        get() = prefs.getString(KEY_LAST_TRIGGER_KIND, null)
        set(value) = prefs.edit { putString(KEY_LAST_TRIGGER_KIND, value) }

    var lastTripEndedAt: Long?
        get() = prefs.getLong(KEY_LAST_END_AT, -1L).takeIf { it >= 0 }
        set(value) = prefs.edit { putLong(KEY_LAST_END_AT, value ?: -1L) }

    var lastTripEndReason: String?
        get() = prefs.getString(KEY_LAST_END_REASON, null)
        set(value) = prefs.edit { putString(KEY_LAST_END_REASON, value) }

    val tentativeStarts: Int get() = prefs.getInt(KEY_TENTATIVE_STARTS, 0)
    val confirmedTrips: Int get() = prefs.getInt(KEY_CONFIRMED_TRIPS, 0)
    val discardedTentatives: Int get() = prefs.getInt(KEY_DISCARDED, 0)

    fun incrementTentativeStarts() = increment(KEY_TENTATIVE_STARTS)
    fun incrementConfirmedTrips() = increment(KEY_CONFIRMED_TRIPS)
    fun incrementDiscardedTentatives() = increment(KEY_DISCARDED)

    private fun increment(key: String) = prefs.edit { putInt(key, prefs.getInt(key, 0) + 1) }

    // --- Permission bookkeeping (for "notDetermined") ---------------------------------------

    fun wasPermissionAsked(permission: String): Boolean = prefs.getBoolean("asked.$permission", false)

    fun markPermissionAsked(permission: String) = prefs.edit { putBoolean("asked.$permission", true) }

    data class LatLon(val lat: Double, val lon: Double)

    private companion object {
        const val FILE = "drivalry_tracking"
        const val KEY_ENABLED = "enabled"
        const val KEY_PAUSED_UNTIL = "pausedUntil"
        const val KEY_PHASE = "phase"
        const val KEY_TRIP_ID = "tripId"
        const val KEY_TRIP_STARTED_AT = "tripStartedAt"
        const val KEY_TENTATIVE_AT = "tentativeAt"
        const val KEY_TRIP_TRIGGER = "tripTrigger"
        const val KEY_EXIT_PENDING = "vehicleExitPending"
        const val KEY_CAR_BT = "connectedCarDevices"
        const val KEY_LAST_LAT = "lastFixLat"
        const val KEY_LAST_LON = "lastFixLon"
        const val KEY_PARK_LAT = "parkingLat"
        const val KEY_PARK_LON = "parkingLon"
        const val KEY_BACKSTOP_COOLDOWN = "backstopCooldownUntil"
        const val KEY_LAST_PARKED_FIX_AT = "lastParkedFixAt"
        const val KEY_LAST_TRIGGER_AT = "lastTriggerAt"
        const val KEY_LAST_TRIGGER_KIND = "lastTriggerKind"
        const val KEY_LAST_END_AT = "lastTripEndedAt"
        const val KEY_LAST_END_REASON = "lastTripEndReason"
        const val KEY_TENTATIVE_STARTS = "tentativeStarts"
        const val KEY_CONFIRMED_TRIPS = "confirmedTrips"
        const val KEY_DISCARDED = "discardedTentatives"
    }
}
