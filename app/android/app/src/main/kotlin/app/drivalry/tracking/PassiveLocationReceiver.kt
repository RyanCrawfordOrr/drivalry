package app.drivalry.tracking

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import com.google.android.gms.location.LocationResult

/**
 * PRIORITY_PASSIVE backstop (docs/03-architecture.md §3.1, §6.1): fixes that other apps
 * already paid for. Every one received while idle is published as a §4 `parkedFix`
 * (rate-limited in TrackingRuntime) so friends see a stale-but-honest parked position; if
 * one lands well outside the parking spot while no trip is running, it is additionally
 * treated like iOS significant-change and starts a tentative trip.
 */
class PassiveLocationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!LocationResult.hasResult(intent)) return
        val location = LocationResult.extractResult(intent)?.lastLocation ?: return
        val runtime = TrackingRuntime.get(context)
        if (runtime.machine.phase != TripStateMachine.Phase.IDLE) return
        // Presence first: the position is free and worth publishing whether or not it also
        // starts a trip below.
        runtime.parkedFix(location)
        val spot = runtime.prefs.parkingSpot ?: return
        if (location.hasAccuracy() && location.accuracy > MAX_ACCURACY_M) return

        val distance = FloatArray(1)
        Location.distanceBetween(spot.lat, spot.lon, location.latitude, location.longitude, distance)
        if (distance[0] >= TRIGGER_DISTANCE_M) {
            runtime.trigger("significantChange")
        }
    }

    private companion object {
        const val MAX_ACCURACY_M = 150f
        const val TRIGGER_DISTANCE_M = 300f
    }
}
