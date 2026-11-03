package app.drivalry.tracking

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.content.Intent
import android.location.Location
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Dart ↔ native bridge for docs/08-tracking-channel.md: the `app.drivalry/tracking`
 * MethodChannel (§3) and the `app.drivalry/tracking/events` EventChannel (§4).
 *
 * Registered from `MainActivity.configureFlutterEngine`; there is no separate pub plugin.
 * The Activity is needed only for the permission prompts, `openSettings` and the
 * `foreground`/`background` phone events. Everything else goes through [TrackingRuntime],
 * which keeps working (and spooling) while no Flutter engine exists.
 */
class TrackingPlugin private constructor(
    private val activity: Activity,
    engine: FlutterEngine,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, Application.ActivityLifecycleCallbacks {

    private val runtime = TrackingRuntime.get(activity)
    private val methods = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
    private val events = EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor { Thread(it, "drivalry-tracking-io").apply { isDaemon = true } }

    private val pendingPermissionResults = ArrayList<MethodChannel.Result>()
    private val completedPermissionSteps = HashSet<Int>()
    private var permissionFlowActive = false

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        activity.application.registerActivityLifecycleCallbacks(this)
        // App launch: make sure Play services still holds our triggers, and bring the
        // service back if the process died mid-trip without a sticky restart.
        runtime.armIfEnabled()
        runtime.resumeServiceIfNeeded()
    }

    fun detach() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        runtime.events.sink = null
        activity.application.unregisterActivityLifecycleCallbacks(this)
        io.shutdown()
    }

    // --- MethodChannel (§3) ----------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getState" -> result.success(runtime.state())

                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled")
                        ?: return result.error("badArgs", "setEnabled needs {enabled: bool}", null)
                    runtime.setEnabled(enabled)
                    result.success(runtime.state())
                }

                "pauseUntil" -> {
                    val until = call.argument<Number>("untilMs")?.toLong()
                        ?: return result.error("badArgs", "pauseUntil needs {untilMs: int}", null)
                    runtime.pauseUntil(until)
                    result.success(runtime.state())
                }

                "requestPermissions" -> requestPermissions(result)

                "openSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(intent)
                    result.success(null)
                }

                "forceStartTrip" -> {
                    runtime.forceStart()
                    result.success(runtime.state())
                }

                "forceEndTrip" -> {
                    runtime.forceEnd()
                    result.success(runtime.state())
                }

                "drainSpool" -> io.execute {
                    val drained = try {
                        runtime.spool.drain()
                    } catch (e: Exception) {
                        main.post { result.error("spool", e.message, null) }
                        return@execute
                    }
                    main.post { result.success(drained) }
                }

                // Android reads the key from the manifest (<meta-data com.google.android.geo.API_KEY>).
                "setMapsApiKey" -> result.success(null)

                "getDiagnostics" -> result.success(runtime.diagnostics())

                "openDrivingModeSettings" -> result.success(openDrivingModeSettings())

                "getLastKnownLocation" -> getLastKnownLocation(
                    maxAgeMs = call.argument<Number>("maxAgeMs")?.toLong() ?: DEFAULT_LAST_KNOWN_MAX_AGE_MS,
                    result = result,
                )

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.w(TAG, "method ${call.method} failed", e)
            result.error("native", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // --- openDrivingModeSettings (§3) --------------------------------------------------------------

    /**
     * Android's driving mode (auto-reply, silenced notifications) is a Do Not Disturb rule, so the
     * closest screen we can open is DND settings; older or vendor builds fall back to the sound
     * settings. Returns false when no settings activity resolves. Drivalry never sends replies.
     */
    private fun openDrivingModeSettings(): Boolean {
        val actions = listOf(
            "android.settings.ZEN_MODE_SETTINGS",
            Settings.ACTION_ZEN_MODE_PRIORITY_SETTINGS,
            Settings.ACTION_SOUND_SETTINGS,
        )
        for (action in actions) {
            val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(activity.packageManager) == null) continue
            try {
                activity.startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w(TAG, "could not open $action", e)
            }
        }
        return false
    }

    // --- getLastKnownLocation (§3) ---------------------------------------------------------------

    /**
     * The fused provider's cached last fix when it is at most [maxAgeMs] old; otherwise one
     * fresh balanced-power fix, waited for up to 10 s. Resolves `null` (never an error) when
     * location permission is missing, the provider has nothing, or the 10 s pass. While a
     * trip is tentative/active the service's 1 Hz stream keeps the cache fresh, so this
     * never adds a request on top of the recording.
     */
    @SuppressLint("MissingPermission") // guarded by Permissions.hasAnyLocation
    private fun getLastKnownLocation(maxAgeMs: Long, result: MethodChannel.Result) {
        if (!Permissions.hasAnyLocation(activity)) {
            result.success(null)
            return
        }
        val fused = LocationServices.getFusedLocationProviderClient(activity)
        val reply = SingleReply(result)
        try {
            // Task listeners without an executor run on the main thread, where Result must be answered.
            fused.lastLocation
                .addOnSuccessListener { loc ->
                    if (loc != null && System.currentTimeMillis() - loc.time <= maxAgeMs) {
                        reply.success(TrackingEvents.position(loc))
                    } else {
                        requestCurrentLocation(fused, reply)
                    }
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "lastLocation failed", e)
                    requestCurrentLocation(fused, reply)
                }
        } catch (e: SecurityException) {
            reply.success(null)
        }
    }

    @SuppressLint("MissingPermission") // guarded by the caller
    private fun requestCurrentLocation(fused: FusedLocationProviderClient, reply: SingleReply) {
        val cancel = CancellationTokenSource()
        val timeout = Runnable {
            cancel.cancel()
            reply.success(null)
        }
        main.postDelayed(timeout, LAST_KNOWN_FRESH_TIMEOUT_MS)
        try {
            fused.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, cancel.token)
                .addOnSuccessListener { loc: Location? ->
                    main.removeCallbacks(timeout)
                    reply.success(loc?.let { TrackingEvents.position(it) })
                }
                .addOnFailureListener { e ->
                    main.removeCallbacks(timeout)
                    Log.w(TAG, "getCurrentLocation failed", e)
                    reply.success(null)
                }
                .addOnCanceledListener {
                    main.removeCallbacks(timeout)
                    reply.success(null)
                }
        } catch (e: SecurityException) {
            main.removeCallbacks(timeout)
            reply.success(null)
        }
    }

    /** Answers a [MethodChannel.Result] at most once; a second `success` would throw. Main thread only. */
    private class SingleReply(private val result: MethodChannel.Result) {
        private var done = false

        fun success(value: Any?) {
            if (done) return
            done = true
            result.success(value)
        }
    }

    // --- EventChannel (§4) -----------------------------------------------------------------------

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        runtime.events.sink = sink
    }

    override fun onCancel(arguments: Any?) {
        runtime.events.sink = null
    }

    // --- Permissions (§3 requestPermissions, §3.2) -------------------------------------------------

    /**
     * Runs the prompts in order, each only when still missing:
     * 1. fine + coarse location
     * 2. background location (API 29 shows a dialog; API 30+ the system opens the app's
     *    location settings so the user can pick "Allow all the time")
     * 3. ACTIVITY_RECOGNITION
     * 4. POST_NOTIFICATIONS (API 33+)
     * 5. BLUETOOTH_CONNECT (API 31+)
     *
     * Needs the Activity in the foreground. Safe to call repeatedly: calls that arrive while
     * a flow is running are answered with the same final map.
     */
    private fun requestPermissions(result: MethodChannel.Result) {
        pendingPermissionResults.add(result)
        if (permissionFlowActive) return
        permissionFlowActive = true
        completedPermissionSteps.clear()
        continuePermissionFlow()
    }

    private fun continuePermissionFlow() {
        val step = nextPermissionStep()
        if (step == null) {
            finishPermissionFlow()
            return
        }
        val (permissions, requestCode) = step
        permissions.forEach(runtime.prefs::markPermissionAsked)
        try {
            ActivityCompat.requestPermissions(activity, permissions, requestCode)
        } catch (e: Exception) {
            Log.w(TAG, "requestPermissions failed for ${permissions.toList()}", e)
            completedPermissionSteps.add(requestCode)
            continuePermissionFlow()
        }
    }

    private fun nextPermissionStep(): Pair<Array<String>, Int>? {
        val ctx = activity
        fun pending(code: Int) = code !in completedPermissionSteps

        if (pending(RC_LOCATION) && !Permissions.hasAnyLocation(ctx)) {
            return arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) to RC_LOCATION
        }
        // Background location can only be granted on top of a foreground grant; asking
        // without one is silently denied, so skip it in that case.
        if (pending(RC_BACKGROUND) && Permissions.hasAnyLocation(ctx) && !Permissions.hasBackgroundLocation(ctx)) {
            return arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION) to RC_BACKGROUND
        }
        if (pending(RC_ACTIVITY) && !Permissions.hasActivityRecognition(ctx)) {
            return arrayOf(Manifest.permission.ACTIVITY_RECOGNITION) to RC_ACTIVITY
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            pending(RC_NOTIFICATIONS) && !Permissions.hasPostNotifications(ctx)
        ) {
            return arrayOf(Manifest.permission.POST_NOTIFICATIONS) to RC_NOTIFICATIONS
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            pending(RC_BLUETOOTH) && !Permissions.hasBluetoothConnect(ctx)
        ) {
            return arrayOf(Manifest.permission.BLUETOOTH_CONNECT) to RC_BLUETOOTH
        }
        return null
    }

    private fun finishPermissionFlow() {
        permissionFlowActive = false
        completedPermissionSteps.clear()
        // Newly granted permissions may make trigger registration possible now.
        runtime.armIfEnabled()
        val snapshot = Permissions.snapshot(activity, runtime.prefs)
        val results = ArrayList(pendingPermissionResults)
        pendingPermissionResults.clear()
        results.forEach { it.success(snapshot) }
    }

    /** Forwarded by MainActivity. Returns true when the request code was ours. */
    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode !in REQUEST_CODES) return false
        completedPermissionSteps.add(requestCode)
        if (permissionFlowActive) continuePermissionFlow()
        return true
    }

    // --- Own-app foreground/background phone events -------------------------------------------------

    override fun onActivityResumed(activity: Activity) {
        if (activity === this.activity) emitAppPhoneEvent("foreground")
    }

    override fun onActivityPaused(activity: Activity) {
        if (activity === this.activity) emitAppPhoneEvent("background")
    }

    private fun emitAppPhoneEvent(kind: String) {
        if (runtime.machine.phase != TripStateMachine.Phase.ACTIVE) return
        val tripId = runtime.machine.tripId ?: return
        runtime.events.phone(tripId, kind)
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit

    companion object {
        private const val TAG = "Drivalry.Plugin"
        const val METHOD_CHANNEL = "app.drivalry/tracking"
        const val EVENT_CHANNEL = "app.drivalry/tracking/events"

        private const val RC_LOCATION = 0x4D01
        private const val RC_BACKGROUND = 0x4D02
        private const val RC_ACTIVITY = 0x4D03
        private const val RC_NOTIFICATIONS = 0x4D04
        private const val RC_BLUETOOTH = 0x4D05
        private val REQUEST_CODES = setOf(RC_LOCATION, RC_BACKGROUND, RC_ACTIVITY, RC_NOTIFICATIONS, RC_BLUETOOTH)

        private const val DEFAULT_LAST_KNOWN_MAX_AGE_MS = 120_000L
        private const val LAST_KNOWN_FRESH_TIMEOUT_MS = 10_000L

        fun attach(activity: Activity, engine: FlutterEngine): TrackingPlugin = TrackingPlugin(activity, engine)
    }
}
