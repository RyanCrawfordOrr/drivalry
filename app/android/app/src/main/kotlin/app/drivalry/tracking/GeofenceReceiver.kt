package app.drivalry.tracking

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofenceStatusCodes
import com.google.android.gms.location.GeofencingEvent

/**
 * Parked backstop: leaving the 100 m fence around the last trip end starts a tentative
 * trip. If the phone left on foot the tentative trip discards itself after 120 s and the
 * fence is re-centred where the phone is now (see TrackingRuntime.onPhaseChanged).
 */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        val runtime = TrackingRuntime.get(context)
        if (event.hasError()) {
            // e.g. GEOFENCE_NOT_AVAILABLE when location services are switched off; the fence
            // is re-registered on the next app start or trip end.
            runtime.events.error("trigger.geofence", GeofenceStatusCodes.getStatusCodeString(event.errorCode))
            return
        }
        if (event.geofenceTransition == Geofence.GEOFENCE_TRANSITION_EXIT) {
            runtime.trigger("geofence")
        }
    }
}
