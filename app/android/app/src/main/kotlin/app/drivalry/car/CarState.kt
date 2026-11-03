package app.drivalry.car

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Process-wide mirror of what the phone app last said over `app.drivalry/car`.
 *
 * Both car surfaces read from here: [app.drivalry.tracking.TrackingService] for the
 * live notification line and the Android Auto screens for everything else. It is
 * persisted so a car session that starts while the Flutter engine is dead still shows
 * the last known state (marked stale by [CarSnapshot.isStale]) instead of nothing, and
 * so taps made while Dart is away survive until it comes back ([ActionQueue]).
 *
 * All mutation happens on the main thread (the method channel and the car host both
 * call there); reads are safe from anywhere.
 */
object CarState {
    private const val PREFS = "drivalry.car"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_LINE_TITLE = "line.title"
    private const val KEY_LINE_TEXT = "line.text"
    private const val KEY_LINE_SUB = "line.subText"
    private const val KEY_LINE_PASSENGER = "line.passengerAction"
    private const val KEY_LINE_TRIP = "line.tripId"
    private const val KEY_QUEUE = "queue"

    fun interface Listener {
        /** Called on the main thread after the snapshot, the notification line or the Dart link changed. */
        fun onCarStateChanged()
    }

    /** The `ongoingNotification` payload from Dart (`OngoingNotificationLine.toWire`). */
    data class NotificationLine(
        val title: String,
        val text: String,
        val subText: String?,
        val passengerAction: Boolean,
        val tripId: String?,
    ) {
        companion object {
            fun fromArgs(m: Map<*, *>): NotificationLine? {
                val text = m["text"] as? String ?: return null
                return NotificationLine(
                    title = m["title"] as? String ?: "Drivalry",
                    text = text,
                    subText = m["subText"] as? String,
                    passengerAction = m["passengerAction"] == true,
                    tripId = m["tripId"] as? String,
                )
            }
        }
    }

    /** Hands an action to the running Dart isolate; the callback says whether Dart handled it. */
    fun interface DartSink {
        fun send(action: CarAction, onResult: (Boolean) -> Unit)
    }

    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<Listener>()
    private var prefs: SharedPreferences? = null

    @Volatile
    var snapshot: CarSnapshot = CarSnapshot.EMPTY
        private set

    @Volatile
    var notification: NotificationLine? = null
        private set

    /** Non-null while a Flutter engine has the car plugin attached. */
    @Volatile
    var dartSink: DartSink? = null
        set(value) {
            field = value
            notifyListeners()
        }

    val dartAttached: Boolean get() = dartSink != null

    /** Idempotent; loads the persisted state the first time. */
    @Synchronized
    fun init(context: Context) {
        if (prefs != null) return
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs = p
        CarSnapshot.parse(p.getString(KEY_SNAPSHOT, null))?.let { snapshot = it }
        val lineTrip = p.getString(KEY_LINE_TRIP, null)
        p.getString(KEY_LINE_TEXT, null)?.let { text ->
            if (NotificationLines.restorable(lineTrip)) {
                notification = NotificationLine(
                    title = p.getString(KEY_LINE_TITLE, null) ?: "Drivalry",
                    text = text,
                    subText = p.getString(KEY_LINE_SUB, null),
                    passengerAction = p.getBoolean(KEY_LINE_PASSENGER, false),
                    tripId = lineTrip,
                )
            } else {
                // A line about no trip in particular (tentative phase) must not survive a
                // process death: it would describe the next drive.
                p.edit().remove(KEY_LINE_TITLE).remove(KEY_LINE_TEXT).remove(KEY_LINE_SUB)
                    .remove(KEY_LINE_PASSENGER).remove(KEY_LINE_TRIP).apply()
            }
        }
    }

    fun setSnapshot(context: Context, json: String) {
        init(context)
        val parsed = CarSnapshot.parse(json) ?: return
        snapshot = parsed
        prefs?.edit()?.putString(KEY_SNAPSHOT, json)?.apply()
        notifyListeners()
    }

    fun setNotification(context: Context, line: NotificationLine?) {
        init(context)
        notification = line
        prefs?.edit()?.apply {
            if (line == null) {
                remove(KEY_LINE_TITLE); remove(KEY_LINE_TEXT); remove(KEY_LINE_SUB)
                remove(KEY_LINE_PASSENGER); remove(KEY_LINE_TRIP)
            } else {
                putString(KEY_LINE_TITLE, line.title)
                putString(KEY_LINE_TEXT, line.text)
                if (line.subText == null) remove(KEY_LINE_SUB) else putString(KEY_LINE_SUB, line.subText)
                putBoolean(KEY_LINE_PASSENGER, line.passengerAction)
                if (line.tripId == null) remove(KEY_LINE_TRIP) else putString(KEY_LINE_TRIP, line.tripId)
            }
            apply()
        }
        notifyListeners()
    }

    /** Remembers an action for Dart's next `drainActions`. */
    fun queue(context: Context, action: CarAction) {
        init(context)
        val p = prefs ?: return
        val next = ActionQueue.append(ActionQueue.decode(p.getString(KEY_QUEUE, null)), action)
        p.edit().putString(KEY_QUEUE, ActionQueue.encode(next)).apply()
    }

    /** Returns and clears the queued actions. */
    fun drain(context: Context): List<CarAction> {
        init(context)
        val p = prefs ?: return emptyList()
        val list = ActionQueue.decode(p.getString(KEY_QUEUE, null))
        if (list.isNotEmpty()) p.edit().remove(KEY_QUEUE).apply()
        return list
    }

    fun addListener(l: Listener) {
        listeners.addIfAbsent(l)
    }

    fun removeListener(l: Listener) {
        listeners.remove(l)
    }

    private fun notifyListeners() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            for (l in listeners) l.onCarStateChanged()
        } else {
            main.post { for (l in listeners) l.onCarStateChanged() }
        }
    }
}
