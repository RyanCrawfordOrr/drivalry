package app.drivalry.car

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `app.drivalry/car`: the Android half of the car bridge (docs/04 §3.3).
 *
 * Dart → native: `snapshot {json}` (the full [CarSnapshot]), `ongoingNotification
 * {title, text, subText, passengerAction, tripId}` (null clears it), `drainActions`
 * (returns `[{name, args}]` queued while Dart was away).
 * Native → Dart: `action {name, args}`; Dart answers `true` when it applied it.
 *
 * Registered from `MainActivity.configureFlutterEngine`. While attached it is the
 * [CarState.DartSink]; detaching clears the sink so later taps queue instead.
 */
class CarPlugin private constructor(
    private val activity: Activity,
    engine: FlutterEngine,
) : CarState.DartSink {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    init {
        CarState.init(activity)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "snapshot" -> {
                        val json = call.argument<String>("json")
                        if (json != null) CarState.setSnapshot(activity, json)
                        result.success(null)
                    }
                    "ongoingNotification" -> {
                        val args = call.arguments as? Map<*, *>
                        CarState.setNotification(activity, args?.let(CarState.NotificationLine::fromArgs))
                        result.success(null)
                    }
                    "drainActions" -> result.success(CarState.drain(activity).map { it.toWire() })
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("car", e.message, null)
            }
        }
        CarState.dartSink = this
    }

    override fun send(action: CarAction, onResult: (Boolean) -> Unit) {
        main.post {
            channel.invokeMethod(
                "action",
                action.toWire(),
                object : MethodChannel.Result {
                    override fun success(result: Any?) = onResult(result == true)
                    override fun error(code: String, message: String?, details: Any?) = onResult(false)
                    override fun notImplemented() = onResult(false)
                },
            )
        }
    }

    fun detach() {
        if (CarState.dartSink === this) CarState.dartSink = null
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL = "app.drivalry/car"

        fun attach(activity: Activity, engine: FlutterEngine): CarPlugin = CarPlugin(activity, engine)
    }
}
