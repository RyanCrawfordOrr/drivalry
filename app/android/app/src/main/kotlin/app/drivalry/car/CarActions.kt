package app.drivalry.car

import android.content.Context
import android.util.Log
import app.drivalry.tracking.TrackingRuntime

/**
 * Sends a car action to Dart, or does the best native thing when no Flutter isolate
 * is running (the car host can start our `CarAppService` with the app dead).
 */
object CarActions {
    private const val TAG = "Drivalry.Car"

    const val END_TRIP = "endTrip"
    const val MARK_PASSENGER = "markPassenger"
    const val VOTE_STOP = "voteStop"
    const val PROPOSE_STOP = "proposeStop"
    const val TALK_START = "talkStart"
    const val TALK_STOP = "talkStop"
    const val RADIO_ON = "radioOn"
    const val RADIO_OFF = "radioOff"
    const val REGROUP_HERE = "regroupHere"
    const val CRASH_OK = "crashOk"
    const val CRASH_HELP = "crashHelp"

    enum class Outcome {
        /** Handed to the running Dart isolate; [dispatch]'s callback carries Dart's answer. */
        SENT,

        /** Done natively (ending a trip needs no Dart); the callback fires with `true`. */
        NATIVE,

        /**
         * Stored for Dart's next start; the user should open the app. Reported through the
         * return value only: the callback is NOT invoked, so a caller shows one message.
         */
        QUEUED,
    }

    /**
     * Where an action goes. Pure, so it is unit-tested: with Dart attached everything is
     * [Outcome.SENT]; otherwise ending the trip is [Outcome.NATIVE] and anything else waits
     * in the queue.
     */
    fun route(action: CarAction, dartAttached: Boolean): Outcome = when {
        dartAttached -> Outcome.SENT
        action.name == END_TRIP -> Outcome.NATIVE
        else -> Outcome.QUEUED
    }

    /**
     * Routes [action] per [route]. [onResult] fires exactly once for [Outcome.SENT] (Dart's
     * answer) and [Outcome.NATIVE] (`true`), and never for [Outcome.QUEUED]: the caller
     * reads that from the return value, so there is one path to the user, not two.
     */
    fun dispatch(context: Context, action: CarAction, onResult: ((Boolean) -> Unit)? = null): Outcome {
        val app = context.applicationContext
        CarState.init(app)
        val sink = CarState.dartSink
        return when (route(action, dartAttached = sink != null)) {
            Outcome.SENT -> {
                sink!!.send(action) { ok ->
                    if (!ok) Log.w(TAG, "Dart declined ${action.name} ${action.args}")
                    onResult?.invoke(ok)
                }
                Outcome.SENT
            }
            Outcome.NATIVE -> {
                // The recorder is native; Dart only needs to pick up the spooled events later.
                TrackingRuntime.get(app).forceEnd()
                onResult?.invoke(true)
                Outcome.NATIVE
            }
            Outcome.QUEUED -> {
                CarState.queue(app, action)
                if (action.name == MARK_PASSENGER) {
                    // Confirm on the notification right away; Dart repeats the hint when it wakes.
                    val line = CarState.notification
                    CarState.setNotification(
                        app,
                        CarState.NotificationLine(
                            title = line?.title ?: "Drivalry",
                            text = "Recording · Passenger · not scored",
                            subText = line?.subText,
                            passengerAction = false,
                            tripId = (action.args["tripId"] as? String) ?: line?.tripId,
                        ),
                    )
                }
                Outcome.QUEUED
            }
        }
    }
}
