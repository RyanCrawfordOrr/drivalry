package app.drivalry.tracking

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
}
