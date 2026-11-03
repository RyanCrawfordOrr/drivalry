package app.drivalry.tracking

import android.annotation.SuppressLint
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.media.AudioManager
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import app.drivalry.MainActivity
import app.drivalry.R
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Foreground service (type `location`) that records a trip while the [TripStateMachine]
 * is tentative or active. It is the only component that touches the GPS or the sensors,
 * and it stops itself the moment the machine returns to idle, so the parked cost is zero
 * (03-architecture §6.1).
 *
 * Battery notes:
 * - Fused location runs at 1 Hz but with `setMaxUpdateDelayMillis(15 s)`, so fixes arrive
 *   in batches and the CPU wakes every ~15 s instead of every second. Each batch is
 *   processed in a few milliseconds on the main thread; no wake lock is held, because the
 *   location delivery itself already holds the CPU awake for the callback.
 * - Linear acceleration is sampled at 20 Hz with `maxReportLatencyUs = 1 s`, so the sensor
 *   hub FIFO-batches samples and the AP is woken at most once a second for them. Only the
 *   per-second peak above 2.5 m/s² survives; raw samples are never stored.
 * - Sensors and the phone-event receivers are registered only once the trip is confirmed
 *   (active); a tentative trip needs nothing but GPS.
 */
class TrackingService : Service(), TripStateMachine.Listener {
    private lateinit var runtime: TrackingRuntime
    private lateinit var fused: FusedLocationProviderClient

    private var locationStarted = false
    private var sensorsStarted = false
    private var sensorThread: HandlerThread? = null

    /** docs/08 §4 `crashCandidate`: fed every accelerometer sample and every fix while active. */
    private val crash = CrashDetector()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val motion = MotionAggregator { t, magnitude ->
        // A 4 g hit at speed opens a candidate; pull the batched fixes in now so the
        // "did the car stop?" answer does not wait out the 15 s delivery delay.
        if (crash.onAccel(t, magnitude)) mainHandler.post { flushLocationsNow() }
    }

    private var phoneReceiverRegistered = false
    private var inCall = false
    private var projecting = false

    /** Fixes processed in the current batch while active, emitted as one `fixes` event. */
    private val pendingFixes = ArrayList<Map<String, Any?>>()

    /**
     * Fixes seen while tentative. Nothing is spooled during tentative, but once the trip
     * is confirmed the fixes from `startedAt` (the first fast fix) onwards belong to it,
     * so they are replayed as the first `fixes` batch.
     */
    private val tentativeBuffer = ArrayDeque<Map<String, Any?>>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        runtime = TrackingRuntime.get(this)
        fused = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException (API 31+) or SecurityException on
            // API 34+ when location permission is missing. Without the service we cannot
            // record, so give the trip up rather than leave the machine stuck.
            Log.w(TAG, "startForeground failed", e)
            runtime.events.error("service.foreground", e.message ?: e.javaClass.simpleName)
            runtime.machine.end("manual")
            stopSelf()
            return
        }
        isRunning = true
        runtime.serviceListener = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isRunning) return START_NOT_STICKY

        if (intent?.action == ACTION_END_TRIP) {
            runtime.machine.end("manual")
            return START_NOT_STICKY
        }

        val machine = runtime.machine
        if (machine.phase == TripStateMachine.Phase.IDLE) {
            // Nothing to record (e.g. sticky restart after the trip already ended).
            shutdown()
            return START_NOT_STICKY
        }

        // Fresh process (normal start, sticky restart, or resume from the plugin / boot):
        // re-arm the machine's timers and start whatever the current phase needs.
        machine.resume()
        startLocation()
        if (machine.phase == TripStateMachine.Phase.ACTIVE) startActivePhaseInputs(initial = true)

        // START_STICKY: if the system kills the process mid-trip, it restarts the service
        // with a null intent and the persisted trip resumes.
        return START_STICKY
    }

    override fun onDestroy() {
        stopRecording()
        if (runtime.serviceListener === this) runtime.serviceListener = null
        isRunning = false
        super.onDestroy()
    }

    // --- TripStateMachine.Listener (forwarded by TrackingRuntime) ---------------------------

    override fun onTripEnding(tripId: String, reason: String) {
        flushPending(tripId, final = true)
    }

    override fun onPhaseChanged(
        from: TripStateMachine.Phase,
        to: TripStateMachine.Phase,
        tripId: String,
        reason: String,
        trigger: String?,
    ) {
        when (to) {
            TripStateMachine.Phase.TENTATIVE -> startLocation()
            TripStateMachine.Phase.ACTIVE -> {
                // Just confirmed: the trip starts at the first fast fix, so the tentative
                // fixes from `startedAt` onwards become the first `fixes` batch. This runs
                // synchronously inside machine.onFix (or forceStartTrip), before the batch
                // loop continues.
                val startedAt = runtime.machine.startedAt ?: 0L
                tentativeBuffer.filterTo(pendingFixes) { (it["t"] as Long) >= startedAt }
                tentativeBuffer.clear()
                crash.reset()
                startActivePhaseInputs(initial = true)
            }
            TripStateMachine.Phase.IDLE -> shutdown()
        }
    }

    // --- Location -------------------------------------------------------------------------------

    @SuppressLint("MissingPermission") // guarded by Permissions.hasAnyLocation
    private fun startLocation() {
        if (locationStarted) return
        if (!Permissions.hasAnyLocation(this)) {
            runtime.events.error("permission.location", "location permission missing; ending trip")
            runtime.machine.end("manual")
            return
        }
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1_000L)
            .setMinUpdateIntervalMillis(1_000L)
            // Batching: the provider may hold fixes for up to 15 s before delivering them,
            // which is what lets the CPU sleep between batches.
            .setMaxUpdateDelayMillis(15_000L)
            .setWaitForAccurateLocation(false)
            .build()
        try {
            fused.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
            locationStarted = true
        } catch (e: SecurityException) {
            runtime.events.error("permission.location", e.message ?: "location denied")
            runtime.machine.end("manual")
        }
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val machine = runtime.machine
            if (machine.phase == TripStateMachine.Phase.IDLE) return
            val locations = result.locations
            if (locations.isEmpty()) return

            // Remember the newest position first: if this batch ends the trip, the parking
            // geofence must be centred on where the car is now.
            locations.last().let { runtime.prefs.lastFix = TrackingPrefs.LatLon(it.latitude, it.longitude) }

            for (loc in locations) {
                val fix = toFix(loc)
                val wasActive = machine.phase == TripStateMachine.Phase.ACTIVE
                if (!wasActive) {
                    tentativeBuffer.addLast(fix)
                    while (tentativeBuffer.size > TENTATIVE_BUFFER_MAX) tentativeBuffer.removeFirst()
                }
                machine.onFix(
                    t = loc.time,
                    lat = loc.latitude,
                    lon = loc.longitude,
                    accuracyM = if (loc.hasAccuracy()) loc.accuracy else null,
                    speedMps = if (loc.hasSpeed()) loc.speed.toDouble() else null,
                )
                when (machine.phase) {
                    // If this fix confirmed the trip, onPhaseChanged(ACTIVE) has already moved
                    // it (and the earlier fast fixes) from the tentative buffer into pendingFixes.
                    TripStateMachine.Phase.ACTIVE -> if (wasActive) pendingFixes.add(fix)
                    TripStateMachine.Phase.TENTATIVE -> Unit
                    TripStateMachine.Phase.IDLE -> return // ended inside onFix; already flushed
                }
                if (machine.phase == TripStateMachine.Phase.ACTIVE) {
                    val speed = if (loc.hasSpeed()) loc.speed.toDouble() else null
                    crash.onSpeed(loc.time, speed)?.let { candidate ->
                        machine.tripId?.let { id -> runtime.events.crashCandidate(id, candidate, loc) }
                    }
                }
            }

            val tripId = machine.tripId ?: return
            if (machine.phase == TripStateMachine.Phase.ACTIVE) {
                flushPending(tripId, final = false)
                samplePhoneState(tripId, locations.last().time, initial = false)
            }
        }
    }

    /** §4 `fixes` entry. Unknown speed / heading are omitted, never sent as -1 or 0. */
    private fun toFix(loc: Location): Map<String, Any?> = LinkedHashMap<String, Any?>(10).apply {
        put("t", loc.time)
        put("lat", loc.latitude)
        put("lon", loc.longitude)
        if (loc.hasSpeed()) put("speed", loc.speed.toDouble())
        if (loc.hasAccuracy()) put("accuracy", loc.accuracy.toDouble())
        if (loc.hasBearing()) put("heading", loc.bearing.toDouble())
        if (loc.hasAltitude()) put("altitude", loc.altitude)
        if (loc.hasSpeedAccuracy()) put("speedAccuracy", loc.speedAccuracyMetersPerSecond.toDouble())
        if (loc.hasBearingAccuracy()) put("headingAccuracy", loc.bearingAccuracyDegrees.toDouble())
    }

    /** Emits the pending `fixes` batch and the completed per-second motion peaks, in that order. */
    private fun flushPending(tripId: String, final: Boolean) {
        if (pendingFixes.isNotEmpty()) {
            runtime.events.fixes(tripId, ArrayList(pendingFixes))
            pendingFixes.clear()
        }
        // A second is "complete" once the 1 s sensor latency can no longer add to it.
        val cutoff = if (final) Long.MAX_VALUE else System.currentTimeMillis() / 1000 - 1
        val peaks = motion.drain(beforeSecondExclusive = cutoff)
        if (peaks.isNotEmpty()) {
            runtime.events.motion(
                tripId,
                t = peaks.last().t,
                events = peaks.map { linkedMapOf("t" to it.t, "kind" to "accelPeak", "peak" to it.peak) },
            )
        }
    }

    // --- Active-phase inputs: sensors + phone events ------------------------------------------

    private fun startActivePhaseInputs(initial: Boolean) {
        startSensors()
        registerPhoneReceiver()
        val tripId = runtime.machine.tripId ?: return
        if (initial) samplePhoneState(tripId, System.currentTimeMillis(), initial = true)
    }

    private fun startSensors() {
        if (sensorsStarted) return
        val manager = getSystemService(SensorManager::class.java) ?: return
        val sensor = manager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
        if (sensor == null) {
            runtime.events.error("sensor.unavailable", "TYPE_LINEAR_ACCELERATION not available")
            return
        }
        val thread = HandlerThread("drivalry-sensors").apply { start() }
        sensorThread = thread
        // 50 000 µs = 20 Hz; 1 s report latency lets the sensor hub batch 20 samples per wake-up.
        val ok = manager.registerListener(motion, sensor, SENSOR_PERIOD_US, SENSOR_LATENCY_US, Handler(thread.looper))
        if (!ok) {
            runtime.events.error("sensor.register", "could not register linear acceleration listener")
            thread.quitSafely()
            sensorThread = null
            return
        }
        sensorsStarted = true
    }

    private fun stopSensors() {
        if (sensorsStarted) {
            getSystemService(SensorManager::class.java)?.unregisterListener(motion)
            sensorsStarted = false
        }
        sensorThread?.quitSafely()
        sensorThread = null
        motion.clear()
    }

    /**
     * Screen / unlock broadcasts can only be received by a context-registered receiver.
     * `interaction` is emitted for ACTION_USER_PRESENT and for screen-on while unlocked
     * (docs/08-tracking-channel.md §4).
     */
    private val phoneReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (runtime.machine.phase != TripStateMachine.Phase.ACTIVE) return
            val tripId = runtime.machine.tripId ?: return
            val now = System.currentTimeMillis()
            when (intent.action) {
                Intent.ACTION_USER_PRESENT -> {
                    runtime.events.phone(tripId, "unlock", now)
                    runtime.events.phone(tripId, "interaction", now)
                }
                Intent.ACTION_SCREEN_ON -> {
                    runtime.events.phone(tripId, "screenOn", now)
                    val locked = getSystemService(KeyguardManager::class.java)?.isKeyguardLocked ?: true
                    if (!locked) runtime.events.phone(tripId, "interaction", now)
                }
                Intent.ACTION_SCREEN_OFF -> runtime.events.phone(tripId, "screenOff", now)
            }
        }
    }

    private fun registerPhoneReceiver() {
        if (phoneReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        // System broadcasts are still delivered to a NOT_EXPORTED receiver.
        ContextCompat.registerReceiver(this, phoneReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        phoneReceiverRegistered = true
    }

    private fun unregisterPhoneReceiver() {
        if (!phoneReceiverRegistered) return
        try {
            unregisterReceiver(phoneReceiver)
        } catch (_: IllegalArgumentException) {
        }
        phoneReceiverRegistered = false
    }

    /**
     * Call and projection state are sampled once per fix batch (no READ_PHONE_STATE, no
     * extra wake-ups); transitions become `callStart`/`callEnd` and `projectionOn`/`Off`.
     * On [initial] only the "on" states are reported so Dart learns about a call or an
     * Android Auto session that was already under way when the trip became active.
     */
    private fun samplePhoneState(tripId: String, t: Long, initial: Boolean) {
        val mode = getSystemService(AudioManager::class.java)?.mode
        val nowInCall = mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION
        if (initial) {
            if (nowInCall) runtime.events.phone(tripId, "callStart", t)
        } else if (nowInCall != inCall) {
            runtime.events.phone(tripId, if (nowInCall) "callStart" else "callEnd", t)
        }
        inCall = nowInCall

        val uiMode = getSystemService(UiModeManager::class.java)?.currentModeType
        val nowProjecting = uiMode == Configuration.UI_MODE_TYPE_CAR
        if (initial) {
            if (nowProjecting) {
                runtime.events.phone(tripId, "projectionOn", t)
                runtime.events.hint(tripId, "androidAuto", null, t)
            }
        } else if (nowProjecting != projecting) {
            runtime.events.phone(tripId, if (nowProjecting) "projectionOn" else "projectionOff", t)
            if (nowProjecting) runtime.events.hint(tripId, "androidAuto", null, t)
        }
        projecting = nowProjecting
    }

    // --- Lifecycle ---------------------------------------------------------------------------------

    private fun stopRecording() {
        if (locationStarted) {
            fused.removeLocationUpdates(locationCallback)
            locationStarted = false
        }
        stopSensors()
        unregisterPhoneReceiver()
        pendingFixes.clear()
        tentativeBuffer.clear()
        crash.reset()
        inCall = false
        projecting = false
    }

    /** Asks fused location to deliver what it is holding. Harmless when nothing is pending. */
    @SuppressLint("MissingPermission") // only called while a location request is active
    private fun flushLocationsNow() {
        if (!locationStarted) return
        try {
            fused.flushLocations()
        } catch (e: SecurityException) {
            Log.w(TAG, "flushLocations denied", e)
        }
    }

    private fun shutdown() {
        stopRecording()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    // --- Notification ------------------------------------------------------------------------------

    private fun createNotificationChannel() {
        val channel = NotificationChannel(CHANNEL_ID, "Trip recording", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Shown while Drivalry records a drive"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        NotificationManagerCompat.from(this).createNotificationChannel(channel)
    }

    private fun buildNotification() = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_stat_tracking)
        .setContentTitle("Drivalry")
        .setContentText("Drivalry is recording your drive")
        .setOngoing(true)
        .setSilent(true)
        .setOnlyAlertOnce(true)
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        .setContentIntent(
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        .addAction(
            0,
            "End trip",
            PendingIntent.getService(
                this,
                1,
                Intent(this, TrackingService::class.java).setAction(ACTION_END_TRIP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        .build()

    /**
     * Per-second peaks of the linear-acceleration magnitude. The phone's orientation in the
     * car is unknown (pocket, mount, seat), so no "horizontal plane" can be identified; the
     * magnitude of the full gravity-free vector is used instead. Vertical bumps therefore
     * also count, which is why the scoring engine treats these peaks as corroboration for
     * GPS-derived events rather than as events in their own right.
     */
    private class MotionAggregator(
        /** Every sample as (epoch ms, m/s²), for the crash detector. Runs on the sensor thread. */
        private val onSample: (Long, Double) -> Unit,
    ) : SensorEventListener {
        private val lock = Any()
        private val peaks = HashMap<Long, Float>()

        override fun onSensorChanged(event: SensorEvent) {
            val v = event.values
            val magnitude = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
            // event.timestamp is nanoseconds since boot; convert to epoch milliseconds.
            val bootEpochMs = System.currentTimeMillis() - SystemClock.elapsedRealtime()
            val tMs = bootEpochMs + event.timestamp / 1_000_000L
            onSample(tMs, magnitude.toDouble())
            if (magnitude <= PEAK_THRESHOLD_MPS2) return // seconds below the threshold never produce an entry
            val second = tMs / 1000L
            synchronized(lock) {
                peaks[second] = max(peaks[second] ?: 0f, magnitude)
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

        /** Removes and returns peaks for seconds strictly before [beforeSecondExclusive], oldest first. */
        fun drain(beforeSecondExclusive: Long): List<Peak> = synchronized(lock) {
            val done = peaks.keys.filter { it < beforeSecondExclusive }.sorted()
            done.map { second -> Peak(second * 1000L, peaks.remove(second)!!.toDouble()) }
        }

        fun clear() = synchronized(lock) { peaks.clear() }
    }

    private data class Peak(val t: Long, val peak: Double)

    companion object {
        private const val TAG = "Drivalry.Service"
        const val CHANNEL_ID = "tracking"
        const val ACTION_END_TRIP = "app.drivalry.tracking.END_TRIP"
        private const val NOTIFICATION_ID = 0x7D1
        private const val SENSOR_PERIOD_US = 50_000
        private const val SENSOR_LATENCY_US = 1_000_000
        private const val PEAK_THRESHOLD_MPS2 = 2.5f
        private const val TENTATIVE_BUFFER_MAX = 150 // > 120 s of 1 Hz fixes

        @Volatile
        var isRunning: Boolean = false
            private set

        /** Starts (or pokes) the service; failures are reported on the event stream and abort the trip. */
        fun start(context: Context, runtime: TrackingRuntime) {
            val app = context.applicationContext
            try {
                ContextCompat.startForegroundService(app, Intent(app, TrackingService::class.java))
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException (API 31+) when a background start
                // is not exempt, or IllegalStateException on older releases.
                Log.w(TAG, "startForegroundService failed", e)
                runtime.events.error("service.start", e.message ?: e.javaClass.simpleName)
                runtime.machine.end("manual")
            }
        }
    }
}
