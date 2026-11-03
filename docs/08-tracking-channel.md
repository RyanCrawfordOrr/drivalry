# Drivalry: Tracking plugin contract

> The platform-channel API between the Dart app (`app/lib/tracking/`) and the two native tracking plugins (`app/android/app/src/main/kotlin/app/drivalry/tracking/`, `app/ios/Runner/Tracking/`). Both platforms implement exactly this. The trip state machine runs natively because it has to gate the GPS radio while the Dart side may not be running (Android kills the app; iOS relaunches it in the background). Dart mirrors the state and owns everything after a trip ends: matching, scoring, storage, UI.

## 1. Channels

| Channel | Kind | Direction |
| --- | --- | --- |
| `app.drivalry/tracking` | `MethodChannel`, standard codec | Dart → native |
| `app.drivalry/tracking/events` | `EventChannel`, standard codec | native → Dart, one `Map<String, Object?>` per event |

All timestamps are epoch **milliseconds** (`int`). All units SI: metres, m/s, m/s², degrees (0 = north, clockwise). Keys are exactly as written; unknown keys are ignored by both sides.

## 2. Trip phases

```
idle ──motion/BT/geofence trigger──► tentative ──speed > 4 m/s for 20 s──► active ──3 min stationary, or
  ▲                                    │                                     │   automotive exit + BT off──► ending ──► idle
  └──── no confirmation in 2 min ──────┘                                     │                                 (trip ended event)
                                                                             └── forceEndTrip() ──────────────► ending
```

- `idle`: no GPS, no sensors, no foreground service. Only OS triggers are armed (activity transitions, Bluetooth connect, significant-change location, parking geofence). On Android 14+ a `location` foreground service started from the background only receives fixes when "Allow all the time" is granted, so automatic trips need the `always` permission; "while in use" still allows a manual `forceStartTrip` from the open app.
- `tentative`: GPS on at 1 Hz, waiting for confirmation. No events are spooled yet except `phase`. If not confirmed within 120 s, back to `idle`; nothing is kept.
- `active`: recording. Fixes, motion, phone events flow to the spool and to the live stream.
- `ending`: the stationary timer or the exit signal has fired; the plugin writes the final `phase` event with `phase: "ended"` and returns to `idle`. `ending` is never observed by Dart as a phase value; it is internal. Dart sees `active` → `ended`.

`tripId` is a UUID v4 string generated natively when the trip becomes tentative. The same id is used for every event of that trip and becomes the drift `trips.id`.

## 3. Methods (Dart → native)

| Method | Arguments | Returns | Notes |
| --- | --- | --- | --- |
| `getState` | – | `State` map (§3.1) | Cheap. Called at start-up and when the app resumes. |
| `setEnabled` | `{enabled: bool}` | `State` | `false` tears everything down and disarms triggers (user turned tracking off). Persisted natively across restarts. |
| `pauseUntil` | `{untilMs: int}` | `State` | Triggers stay armed but are ignored until then. `0` clears the pause. Persisted. |
| `requestPermissions` | – | `Permissions` map (§3.2) | Shows the OS prompts in the right order (when-in-use location, then always/background, then motion/activity, then notifications on Android 13+). Safe to call repeatedly. |
| `openSettings` | – | `null` | Opens the app's OS settings page so the user can grant "Always". |
| `forceStartTrip` | – | `State` | Debug and "start now" button: goes straight to `active` with a new `tripId`. |
| `forceEndTrip` | – | `State` | Ends the current trip now, if any. |
| `drainSpool` | – | `List<Map>` | Returns every spooled event in order (see §5) and deletes them. Dart calls this at start-up and after every `phase: ended`. |
| `setMapsApiKey` | `{key: String}` | `null` | iOS only (`GMSServices.provideAPIKey`). Android ignores it (the key is in the manifest). |
| `getDiagnostics` | – | `Diagnostics` map (§3.3) | For Settings › Diagnostics. |
| `getLastKnownLocation` | `{maxAgeMs: int?}` | `{t, lat, lon, accuracy, speed?, heading?}` or `null` | Cheap: the OS's cached last fix (Android `FusedLocationProviderClient.lastLocation`, iOS `CLLocationManager.location`). When it is older than `maxAgeMs` (default 120000) the plugin requests one fresh fix (Android `getCurrentLocation`, iOS `requestLocation`) and waits up to 10 s. Used to publish presence when the app opens. Needs at least while-in-use permission; returns `null` otherwise. |
| `openDrivingModeSettings` | – | `bool` | Opens the OS screen that owns driving mode / auto-reply: Android tries `ZEN_MODE_SETTINGS`, then the DND priority and sound settings, and answers whether one opened. iOS answers `false` (no public Focus URL), and the app shows the steps instead. Drivalry never sends replies itself (docs/01 §4.2). |

### 3.1 `State`

```
{
  phase: "idle" | "tentative" | "active",
  tripId: String?,          // when phase != idle
  tripStartedAt: int?,      // ms, when phase == active (the first confirmed fix)
  enabled: bool,
  pausedUntil: int,         // ms, 0 when not paused
  permissions: Permissions,
  spooledEvents: int        // how many events are waiting in the spool
}
```

### 3.2 `Permissions`

```
{
  location: "denied" | "whileInUse" | "always",
  preciseLocation: bool,    // iOS reduced accuracy / Android coarse-only → false
  motion: "denied" | "granted" | "notDetermined",   // iOS Motion & Fitness, Android ACTIVITY_RECOGNITION
  notifications: "denied" | "granted" | "notDetermined",
  bluetooth: "denied" | "granted" | "notDetermined" // Android 12+ BLUETOOTH_CONNECT; iOS always "granted"
}
```

### 3.3 `Diagnostics`

```
{
  lastTriggerAt: int?, lastTriggerKind: String?,  // "activity" | "bluetooth" | "geofence" | "significantChange" | "manual"
  tentativeStarts: int, confirmedTrips: int, discardedTentatives: int,   // since install
  lastTripEndedAt: int?, lastTripEndReason: String?,                      // "stationary" | "exit" | "manual"
  batteryLevel: double?,            // 0–1 now
  serviceRunning: bool              // Android foreground service / iOS background location active
}
```

## 4. Events (native → Dart)

Every event is a map with `type`, `tripId` and `t` (ms, when the event happened). Events for a trip are delivered in time order. The live stream and the spool carry the **same** maps.

### `phase`

```
{ type: "phase", tripId, t, phase: "tentative" | "active" | "ended" | "discarded",
  reason: String?,                 // trigger kind for tentative/active; end reason for ended; "unconfirmed" for discarded
  startedAt: int? }                // active: the time of the first confirmed fix (trip start)
```

`discarded` means the tentative trip was never confirmed; Dart deletes anything it has for that id.

### `fixes`

```
{ type: "fixes", tripId, t,         // t = time of the last fix in the batch
  fixes: [ { t, lat, lon, speed, accuracy, heading?, altitude?, speedAccuracy?, headingAccuracy? }, ... ] }
```

GPS at 1 Hz, delivered in batches (Android `setMaxUpdateDelayMillis` 15 s; iOS flushed every 20 s or 20 fixes). `speed` is the OS value, `-1` when unknown is **not** allowed: unknown speed is omitted from the batch. `heading` is omitted when the OS says it is invalid.

### `motion`

```
{ type: "motion", tripId, t, events: [ { t, kind: "accelPeak", peak }, ... ] }
```

One entry per second in which the horizontal linear-acceleration magnitude (gravity removed, from the 20 Hz device-motion stream) exceeded 2.5 m/s². `peak` is the maximum in that second. Raw sensor data is never stored. The scoring engine derives brake, accel and corner events from GPS; these peaks corroborate them and feed crash detection later.

### `phone`

```
{ type: "phone", tripId, t, kind }
kind: "unlock" | "screenOn" | "screenOff" | "interaction" | "callStart" | "callEnd"
    | "projectionOn" | "projectionOff"        // CarPlay / Android Auto connected
    | "foreground" | "background"             // our own app
```

Dart maps these to the engine's `unlock`, `interaction`, `call_handheld` and drops the rest when the screen is projecting. "Interaction" on Android is `ACTION_USER_PRESENT` and screen-on while unlocked; on iOS it is our app entering the foreground (the OS exposes nothing else).

### `hint`

```
{ type: "hint", tripId, t, kind: "bluetooth" | "carplay" | "androidAuto", name: String? }
```

Passenger hints and vehicle identification. `name` is the Bluetooth device name when available.

### `parkedFix`

```
{ type: "parkedFix", tripId: null, t, lat, lon, accuracy, speed?, heading? }
```

Emitted while `idle` whenever the OS wakes the plugin with a position for free: iOS significant-change callbacks and geofence exits, Android the passive-location receiver and geofence exits. The plugin requests nothing extra for this. Dart uses it to update the owner's presence while parked (ADR-018), so friends see a stale-but-honest position without the GPS radio ever turning on for it. Spooled like every other event.

### `crashCandidate`

```
{ type: "crashCandidate", tripId, t, peakMps2, speedBeforeMps, lat, lon, accuracy }
```

Emitted at most once per trip while `active` when all three hold within a 5 s window: a linear-acceleration peak of at least 40 m/s² (about 4 g), GPS speed that was at least 8 m/s in the 3 s before the peak, and speed under 1 m/s for the 5 s after it. The plugin keeps recording; it does not end the trip. Dart starts the 30 s countdown (`docs/01` §4.5), marks the trip `crashCandidate`, and only escalates (push to circle members through `crash_alerts`, prefilled SMS to the on-phone emergency contacts) if the countdown is not cancelled. Never an automatic call. The thresholds are first guesses to be tuned against false positives on the test phones.

### `error`

```
{ type: "error", tripId: null, t, code: String, message: String }
```

Permission lost mid-trip, location services off, sensor unavailable. Informational.

## 5. Spool

The plugin appends every event it emits to `<app files>/tracking/spool.jsonl` (one JSON object per line, UTF-8, the same maps as §4 with numbers as JSON numbers). The file is rotated at 8 MB into `spool.1.jsonl` (older lines are dropped beyond two files). `drainSpool` returns the parsed lines of both files in order, then truncates them. Writes happen whether or not a Dart listener is attached, so a trip recorded while the app was dead is replayed in full when the app next opens.

Because the live stream and the spool carry identical events, Dart must treat a `fixes` batch as idempotent per `(tripId, t)` of the batch and skip batches it has already stored.

## 6. Platform notes

**Android**

- `ActivityRecognition` Transition API (`IN_VEHICLE` ENTER/EXIT) through a manifest-registered `BroadcastReceiver`; re-registered on `BOOT_COMPLETED`.
- Bluetooth: `BluetoothDevice.ACTION_ACL_CONNECTED` / `DISCONNECTED` receiver; the device name needs `BLUETOOTH_CONNECT` on API 31+.
- Recording runs in a foreground service with `foregroundServiceType="location"` and an ongoing notification "Drivalry is recording your drive". The service stops when the trip ends.
- Fused location `PRIORITY_HIGH_ACCURACY`, interval 1000 ms, `setMaxUpdateDelayMillis(15000)`. Parked backstop: `PRIORITY_PASSIVE` request with a 100 m geofence around the last trip end.
- Parked fixes: every `PassiveLocationReceiver` result and the `GeofencingEvent.triggeringLocation` of a fence exit are emitted as `parkedFix` (at most one per 60 s; the timestamp is persisted so a receiver woken in a fresh process honours it) *before* the trigger logic runs, and nothing is requested for them. `getLastKnownLocation` reads `FusedLocationProviderClient.lastLocation` and only calls `getCurrentLocation(PRIORITY_BALANCED_POWER_ACCURACY)` when that is older than `maxAgeMs`; while a trip is tentative/active the service's 1 Hz stream keeps that cache fresh, so the method never adds a second request on top of the recording.
- Sensors: `TYPE_LINEAR_ACCELERATION` at 20 Hz with `maxReportLatencyUs = 1_000_000`.
- Phone events: `ACTION_USER_PRESENT`, `ACTION_SCREEN_ON/OFF`; calls via `AudioManager.mode == MODE_IN_CALL || MODE_IN_COMMUNICATION` sampled on each fix batch (no `READ_PHONE_STATE`); projection via `UiModeManager.currentModeType == UI_MODE_TYPE_CAR` and `CarConnection` when the car app library is present.
- Permissions in the manifest: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `ACTIVITY_RECOGNITION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `BLUETOOTH_CONNECT`, `RECEIVE_BOOT_COMPLETED`.
- Settings persisted in `SharedPreferences` `drivalry_tracking`.

**iOS**

- `CMMotionActivityManager.startActivityUpdates` for `automotive`; `CLLocationManager` with `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`, `activityType = .automotiveNavigation`, `desiredAccuracy = kCLLocationAccuracyBest`, `distanceFilter = kCLDistanceFilterNone` while tentative/active. Parked: `startMonitoringSignificantLocationChanges` plus a 100 m `CLCircularRegion` around the last trip end. Both relaunch the app.
- Parked fixes: the location of each significant-change `didUpdateLocations` while parked and `CLLocationManager.location` at `didExitRegion` are emitted as `parkedFix` (one per 60 s, persisted in the suite) just before the matching trigger; nothing is requested for them. `getLastKnownLocation` uses `CLLocationManager.location` and falls back to `requestLocation()` only while idle, because `requestLocation()` and `startUpdatingLocation()` cancel each other: during a tentative/active trip it answers with the latest recorded fix and never issues a one-shot request, and while a one-shot is pending the `didUpdateLocations` that answers it counts neither as a trigger nor as a parked fix.
- `CMMotionManager.startDeviceMotionUpdates` at 20 Hz while active, `userAcceleration` magnitude in the horizontal plane after removing the gravity-aligned component.
- Phone events: `CXCallObserver` (call start/end), `UIApplication` foreground/background, `UIScreen` connect for CarPlay (`CPTemplateApplicationScene` when the entitlement exists).
- Bluetooth hint: `AVAudioSession.routeChangeNotification` with an output port of type `bluetoothA2DP`, `bluetoothHFP` or `carAudio`; the port name is the hint `name`.
- `Info.plist`: `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSMotionUsageDescription`, `UIBackgroundModes` = `location`, `remote-notification` (the latter for push, not tracking).
- Settings persisted in `UserDefaults` suite `app.drivalry.tracking`.

## 6.1 Behaviour both plugins share (settled by the first implementations)

- Fixes seen during `tentative` are kept in memory, never spooled; on confirmation those with `t >= startedAt` become the first `fixes` batch after `phase: active`, so the trip is complete from `startedAt`. A discard leaves no trace but the `discarded` event.
- `forceStartTrip` from `idle` emits `phase: active` directly (`reason: "manual"`, `startedAt` = now) with no `tentative` event; from `tentative` it confirms the existing id. `forceEndTrip` during `tentative` emits `discarded` with reason `unconfirmed`.
- An active trip with no fix at all for 5 minutes ends with reason `stationary` (underground garages deliver nothing). For `stationary` the `ended` event's `t` is the last moving fix plus 180 s, which is the trip's end time.
- `hint` events may arrive during `tentative` on Android (the Bluetooth connection is the trigger) and are held until `active` on iOS; Dart treats both the same.
- `error` events are spooled with `tripId: null`. Codes in use: `permission.location`, `permission.activityRecognition`, `locationPermissionLost`, `trigger.activity`, `trigger.geofence`, `service.start`, `service.foreground`, `sensor.unavailable`, `sensor.register`.
- Every event is spooled whether or not a live listener is attached, so a live client sees each batch twice over the trip's life (once live, once on drain). Dedupe `fixes` and `motion` by `(tripId, t)` and `phone`/`hint` by `(tripId, t, kind)`.
- Android emits `interaction` alongside `unlock` and alongside `screenOn` when the keyguard is off; iOS emits `interaction` alongside `foreground`. Dart collapses an `unlock` and an `interaction` within one second into a single engine `unlock`.
- After a geofence or significant-change trigger is discarded, those two trigger kinds are ignored for 10 minutes and the parking spot is re-centred, so a pedestrian cannot re-arm GPS every 100 m. Activity and Bluetooth triggers are unaffected.
- `pausedUntil` leaves a running trip alone and auto-clears to 0 when elapsed. `State.tripStartedAt` is non-null only while `active`.
- iOS cannot emit `unlock`, `screenOn`, `screenOff`; without the CarPlay entitlement it never emits `projectionOn/Off` and reports a CarPlay audio route as a `carplay` hint instead. iOS does not wake a suspended app on Bluetooth connect, so the Bluetooth trigger only fires while the app is alive; parked wake-ups come from significant-change and the geofence.
- Spool replay on iOS writes integral doubles as JSON integers; Dart parses every number as `num`.

## 7. Dart side

`app/lib/tracking/tracking_channel.dart` wraps the two channels with typed Dart classes (`TrackingState`, `TrackingPermissions`, `TrackingEvent` subclasses). `app/lib/tracking/trip_recorder.dart` consumes events (live and drained) and writes to drift. `app/lib/tracking/trip_finalizer.dart` runs on `phase: ended`: load samples → match in an isolate against the installed pack → score with `drivalry_scoring` → store the result → surface the passenger interstitial. `app/lib/tracking/simulated_tracking.dart` replays a fixture through the same recorder and finalizer so the whole pipeline is testable on a desk.
