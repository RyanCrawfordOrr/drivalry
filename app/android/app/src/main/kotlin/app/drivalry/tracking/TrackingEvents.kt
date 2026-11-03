package app.drivalry.tracking

import android.location.Location
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Single exit point for every event in docs/08-tracking-channel.md §4.
 *
 * Each event is appended to the [Spool] first (so a trip recorded while the Dart side is
 * dead is replayed later) and then handed to the live [EventChannel] sink when one is
 * attached. The sink is only ever touched on the main thread, as the Flutter engine
 * requires; callers may emit from any thread.
 */
class TrackingEvents(private val spool: Spool) {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var sink: EventChannel.EventSink? = null

    fun emit(event: Map<String, Any?>) {
        spool.append(event)
        if (Looper.myLooper() == main.looper) {
            sink?.success(event)
        } else {
            main.post { sink?.success(event) }
        }
    }

    fun phase(
        tripId: String,
        phase: String,
        reason: String?,
        startedAt: Long? = null,
        t: Long = System.currentTimeMillis(),
    ) = emit(
        linkedMapOf(
            "type" to "phase",
            "tripId" to tripId,
            "t" to t,
            "phase" to phase,
            "reason" to reason,
            "startedAt" to startedAt,
        ),
    )

    fun fixes(tripId: String, fixes: List<Map<String, Any?>>) {
        if (fixes.isEmpty()) return
        val last = fixes.last()["t"] as Long
        emit(linkedMapOf("type" to "fixes", "tripId" to tripId, "t" to last, "fixes" to fixes))
    }

    /** `events` entries are `{t, kind: "accelPeak", peak}`. */
    fun motion(tripId: String, t: Long, events: List<Map<String, Any?>>) {
        if (events.isEmpty()) return
        emit(linkedMapOf("type" to "motion", "tripId" to tripId, "t" to t, "events" to events))
    }

    fun phone(tripId: String, kind: String, t: Long = System.currentTimeMillis()) =
        emit(linkedMapOf("type" to "phone", "tripId" to tripId, "t" to t, "kind" to kind))

    fun hint(tripId: String, kind: String, name: String?, t: Long = System.currentTimeMillis()) =
        emit(linkedMapOf("type" to "hint", "tripId" to tripId, "t" to t, "kind" to kind, "name" to name))

    /**
     * §4 `crashCandidate`: a hard impact at speed followed by a dead stop, at most once per trip.
     * The position is the newest fix the service has; Dart owns the countdown and the alert.
     */
    fun crashCandidate(tripId: String, candidate: CrashDetector.Candidate, location: Location?) =
        emit(
            LinkedHashMap<String, Any?>(9).apply {
                put("type", "crashCandidate")
                put("tripId", tripId)
                put("t", candidate.t)
                put("peakMps2", candidate.peakMps2)
                put("speedBeforeMps", candidate.speedBeforeMps)
                put("lat", location?.latitude ?: 0.0)
                put("lon", location?.longitude ?: 0.0)
                put("accuracy", if (location != null && location.hasAccuracy()) location.accuracy.toDouble() else 50.0)
            },
        )

    fun error(code: String, message: String, t: Long = System.currentTimeMillis()) =
        emit(
            linkedMapOf(
                "type" to "error",
                "tripId" to null,
                "t" to t,
                "code" to code,
                "message" to message,
            ),
        )

    /**
     * §4 `parkedFix`: a position the OS handed us for free while idle. Callers (the
     * passive-location and geofence receivers, via [TrackingRuntime.parkedFix]) have
     * already applied the idle check and the rate limit.
     */
    fun parkedFix(location: Location) =
        emit(
            LinkedHashMap<String, Any?>(8).apply {
                put("type", "parkedFix")
                put("tripId", null)
                putAll(position(location))
            },
        )

    companion object {
        /**
         * `{t, lat, lon, accuracy, speed?, heading?}`: the shape shared by `parkedFix` and
         * `getLastKnownLocation` (§3). Unknown speed / heading are omitted, never -1 or 0;
         * `accuracy` is omitted only when the OS reports none, which fused location never does.
         */
        fun position(loc: Location): Map<String, Any?> = LinkedHashMap<String, Any?>(6).apply {
            put("t", loc.time)
            put("lat", loc.latitude)
            put("lon", loc.longitude)
            if (loc.hasAccuracy()) put("accuracy", loc.accuracy.toDouble())
            if (loc.hasSpeed() && loc.speed >= 0f) put("speed", loc.speed.toDouble())
            if (loc.hasBearing() && loc.bearing >= 0f) put("heading", loc.bearing.toDouble())
        }
    }
}
