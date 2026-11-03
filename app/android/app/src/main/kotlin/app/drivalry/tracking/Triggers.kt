package app.drivalry.tracking

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * The OS-driven triggers that are armed while a trip is *not* running (§2 "idle" and
 * 03-architecture §6.1). None of them keeps our process alive: Play services holds the
 * registrations and wakes the matching manifest receiver through a PendingIntent.
 *
 * - Activity Recognition Transition API: IN_VEHICLE ENTER (trigger) and EXIT (end rule).
 * - Parking geofence: 100 m EXIT fence around the last fix of the previous trip.
 * - PRIORITY_PASSIVE location: piggybacks on fixes other apps request; costs no radio time
 *   and is the Android counterpart of iOS significant-change monitoring.
 */
object Triggers {
    private const val TAG = "Drivalry.Triggers"
    const val GEOFENCE_ID = "parking"
    const val GEOFENCE_RADIUS_M = 100f

    /** Idempotent: re-registering with the same PendingIntent replaces the previous request. */
    fun armAll(context: Context, runtime: TrackingRuntime) {
        armActivityTransitions(context, runtime)
        val spot = runtime.prefs.parkingSpot
        if (spot != null) armParking(context, runtime, spot)
    }

    fun disarmAll(context: Context) {
        val app = context.applicationContext
        try {
            ActivityRecognition.getClient(app).removeActivityTransitionUpdates(transitionIntent(app))
        } catch (e: Exception) {
            Log.w(TAG, "removeActivityTransitionUpdates failed", e)
        }
        disarmParking(app)
    }

    @SuppressLint("MissingPermission") // checked via Permissions.hasActivityRecognition
    fun armActivityTransitions(context: Context, runtime: TrackingRuntime) {
        val app = context.applicationContext
        if (!Permissions.hasActivityRecognition(app)) {
            runtime.events.error("permission.activityRecognition", "ACTIVITY_RECOGNITION not granted; vehicle detection is off")
            return
        }
        val transitions = listOf(
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.IN_VEHICLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.IN_VEHICLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_EXIT)
                .build(),
        )
        try {
            ActivityRecognition.getClient(app)
                .requestActivityTransitionUpdates(ActivityTransitionRequest(transitions), transitionIntent(app))
                .addOnFailureListener { e ->
                    Log.w(TAG, "requestActivityTransitionUpdates failed", e)
                    runtime.events.error("trigger.activity", e.message ?: "activity transition registration failed")
                }
        } catch (e: SecurityException) {
            runtime.events.error("permission.activityRecognition", e.message ?: "activity recognition denied")
        }
    }

    /** Geofence + passive request around [spot]. Both need fine location (geofencing also background). */
    @SuppressLint("MissingPermission") // checked via Permissions.hasFineLocation
    fun armParking(context: Context, runtime: TrackingRuntime, spot: TrackingPrefs.LatLon) {
        val app = context.applicationContext
        if (!Permissions.hasFineLocation(app)) {
            runtime.events.error("permission.location", "ACCESS_FINE_LOCATION not granted; parking backstops are off")
            return
        }
        try {
            val fence = Geofence.Builder()
                .setRequestId(GEOFENCE_ID)
                .setCircularRegion(spot.lat, spot.lon, GEOFENCE_RADIUS_M)
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_EXIT)
                .build()
            val request = GeofencingRequest.Builder()
                .setInitialTrigger(0) // never fire on registration; we are standing in the fence
                .addGeofence(fence)
                .build()
            LocationServices.getGeofencingClient(app)
                .addGeofences(request, geofenceIntent(app))
                .addOnFailureListener { e ->
                    Log.w(TAG, "addGeofences failed", e)
                    runtime.events.error("trigger.geofence", e.message ?: "geofence registration failed")
                }

            // Passive: delivered only when some other app already obtained a fix, throttled
            // to one per minute and 200 m. Zero radio cost; one short receiver wake-up per fix.
            val passive = LocationRequest.Builder(Priority.PRIORITY_PASSIVE, 60_000L)
                .setMinUpdateDistanceMeters(200f)
                .setMinUpdateIntervalMillis(60_000L)
                .build()
            LocationServices.getFusedLocationProviderClient(app)
                .requestLocationUpdates(passive, passiveIntent(app))
                .addOnFailureListener { e -> Log.w(TAG, "passive request failed", e) }
        } catch (e: SecurityException) {
            runtime.events.error("permission.location", e.message ?: "location denied")
        }
    }

    fun disarmParking(context: Context) {
        val app = context.applicationContext
        try {
            LocationServices.getGeofencingClient(app).removeGeofences(geofenceIntent(app))
            LocationServices.getFusedLocationProviderClient(app).removeLocationUpdates(passiveIntent(app))
        } catch (e: Exception) {
            Log.w(TAG, "disarmParking failed", e)
        }
    }

    // Play services fills extras into these intents, hence FLAG_MUTABLE. Explicit component
    // targets keep the receivers unexported.
    private fun transitionIntent(app: Context) = broadcast(app, ActivityTransitionReceiver::class.java, 1)
    private fun geofenceIntent(app: Context) = broadcast(app, GeofenceReceiver::class.java, 2)
    private fun passiveIntent(app: Context) = broadcast(app, PassiveLocationReceiver::class.java, 3)

    private fun broadcast(app: Context, receiver: Class<*>, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            app,
            requestCode,
            Intent(app, receiver),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
}
