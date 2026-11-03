# Drivalry: CarPlay and Android Auto

> What the platforms allow as of late 2026, and what we build on each. Verify against Apple's CarPlay App Programming Guide and Google's "Supported app categories" table before each submission; both change yearly.

## 1. The honest summary

Neither platform has a category for "gamified driving stats". Both review apps strictly against driver-distraction rules. So:

- The in-car surface is **minimal by design**: one number, one list, big buttons, audio feedback. No feed, no leaderboard, no roast text while moving. That is both a platform requirement and good product sense.
- We **do not depend on car-screen approval to ship**. The phone experience (Live Activity / Dynamic Island on iOS, ongoing notification on Android, spoken cues through the car speakers) delivers the same in-drive value with no entitlement, and most people mount their phone anyway.
- CarPlay requires an **entitlement granted by Apple per app**. Android Auto requires fitting a **supported category** and passing Google's car-app quality review.
- The CarPlay Driving Task entitlement is **requested now**, at the start of the project, because Apple is slow and may refuse. Car screens are the last build stage either way (see `06-roadmap.md`).

## 2. CarPlay

### Category: Driving Task (iOS 16+)

Apple's categories are Audio, Communication (messaging/VoIP), Navigation, EV Charging, Parking, Fueling, Quick Food Ordering, and **Driving Task**. Driving Task covers "tasks people do while driving" such as road conditions, tolls, and vehicle accessories, and explicitly must not duplicate navigation. A live safety score plus convoy coordination is a defensible Driving Task; approval is Apple's call and typically takes weeks.

Entitlement key: `com.apple.developer.carplay-driving-task`. Request at developer.apple.com/carplay with a description and screenshots of the car UI, under bundle id `app.drivalry`.

### Templates available to Driving Task apps

Driving Task apps get the generic templates: `CPTabBarTemplate`, `CPListTemplate`, `CPGridTemplate`, `CPInformationTemplate`, `CPAlertTemplate`, `CPActionSheetTemplate`, and `CPPointOfInterestTemplate` (map-backed POI list, rendered by Apple's map). `CPMapTemplate` (custom map drawing) is Navigation-only, which we do not want anyway.

### Our CarPlay screens

```
Tab bar
├─ Drive      CPInformationTemplate
│             "Clean so far" / live score · streak · limit vs speed (text) · [Mark passenger]
├─ Convoy     CPListTemplate
│             Members with gap (min) and ETA · [Regroup here] · [Propose stop]
├─ Talk       CPGridTemplate
│             One giant PTT button + "Last: Sam, 10 s ago" (Siri: "Hey Siri, talk to my convoy")
└─ Stops      CPPointOfInterestTemplate
              Proposed/voted stops along the route, pins on Apple's map
```

Rules we follow: no text longer than a list row, no scrolling feeds, no roasts, alerts only for convoy events (lost sheep, stop vote) and never while the vehicle is moving unless safety-relevant. The live limit shown on the Drive tab comes from the on-device pack, so it works with no network.

### Push-to-talk

iOS 16's `PushToTalk` framework gives system-level PTT (lock screen button, background audio, routes through CarPlay). Our CarPlay "Talk" button drives the same peer-to-peer WebRTC channel the phone uses. Voice-conversation entitlement may be needed for audio feedback through CarPlay; request alongside Driving Task.

### Without the entitlement

- **Live Activity + Dynamic Island**: live score, limit, convoy gap. Works on any iPhone mount.
- **Spoken cues** through the active audio route (ducks music). Needs only the background-audio mode. Off by default.
- **Siri Shortcuts**: "Start a convoy", "Talk to my convoy", "Mark me as passenger".

### Built 2026-11-03: Live Activity and the CarPlay plan

**Live Activity / Dynamic Island** (M5.1, iOS 16.2+). Dart owns the content, Swift owns the pixels.

| Piece | Where |
|---|---|
| Frame model, builder, throttled driver, providers | `app/lib/car/live_activity.dart` |
| Method channel `app.drivalry/live_activity` (`isSupported`, `start`, `update`, `end`, `endAll`) | `app/ios/Runner/Tracking/LiveActivityPlugin.swift` |
| Shared `ActivityAttributes` (member of Runner **and** the widget extension) | `app/ios/Runner/Tracking/DriveActivityAttributes.swift` |
| Lock-screen banner, Dynamic Island compact/minimal/expanded | `app/ios/DrivalryWidgets/DriveLiveActivity.swift` |
| Extension target sources + `Info.plist` | `app/ios/DrivalryWidgets/` (target created in Xcode, `README-mac.md` §4 step 8) |

Frame fields (`ContentState` ↔ `LiveActivityContent`): `limitPosted`, `limitUnit`, `speedPosted`, `cleanSoFar`, `overBy`, `roadName`, `tripMinutes`, `recording`, `convoyName`, `gapMinutes`, `etaMinutes`, `talking`, `updatedAt` (epoch ms). The activity's fixed attribute `startedAt` is the trip start, or absent when the activity was opened for a convoy that is not driving yet; the phone ends and restarts the activity for each new trip, and the widget shows trip minutes only while `recording` (ticking from `startedAt`, else from `tripMinutes` plus the time since `updatedAt`). The speed is converted into the *limit's* unit so one frame never mixes mph and km/h; with no usable limit the Settings unit applies and the road name is hidden (docs/01 §4.2 "silent where unsure").

Behaviour: the activity starts when a trip turns `active` or a convoy is active, updates at most every 5 s and only when something visible changed, and ends when both are over. "Clean so far" flips once the car is more than 2 m/s (≈4.5 mph) over a confident limit and resets per trip. The island shows the limit badge (compact leading) and the current speed (compact trailing, orange when over); expanded adds the road, trip minutes and the convoy line (name, gap to leader, ETA, who is talking). No score, no roast text, ever. Below iOS 16.2 or with Live Activities turned off every method is a no-op; Android never calls the channel (`liveActivityEnabledProvider`). The widget dims the state as stale a minute after the last update.

**CarPlay plan** (groundwork). `app/lib/car/carplay_stub.dart` maps the same frame plus convoy members and stops to a `CarPlayPlan`: four tabs (Drive = `CPInformationTemplate`, Convoy = `CPListTemplate`, Talk = `CPGridTemplate`, Stops = `CPPointOfInterestTemplate`), rows clipped to 40 characters, buttons `markPassenger`, `regroupHere`, `proposeStop`, `pushToTalk`, `openStop`. `toMap()` is what a future `CPTemplateApplicationSceneDelegate` reads over a method channel; no Swift exists for it yet because the scene class cannot even be instantiated without the entitlement.

**When the entitlement arrives** (Xcode, on the Mac):

1. Download the updated provisioning profile; Apple adds `com.apple.developer.carplay-driving-task` to the app id.
2. Runner → *Signing & Capabilities* → `+ Capability` is not enough for CarPlay: open `Runner/Runner.entitlements` and add `<key>com.apple.developer.carplay-driving-task</key><true/>` by hand.
3. `Info.plist` → `UIApplicationSceneManifest` → `UISceneConfigurations`: add a `CPTemplateApplicationSceneSessionRoleApplication` array with one entry, `UISceneClassName = CPTemplateApplicationScene`, `UISceneDelegateClassName = $(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`, and set `UIApplicationSupportsMultipleScenes = YES`.
4. Add `Runner/Tracking/CarPlaySceneDelegate.swift` implementing `CPTemplateApplicationSceneDelegate`, reading `CarPlayPlan.toMap()` over a new `app.drivalry/carplay` channel and building the four templates; wire the actions back to Dart.
5. Test in the Xcode CarPlay simulator (*I/O › External Displays › CarPlay*) before requesting review.

## 3. Android Auto

### Categories

The Android for Cars App Library supports Navigation, Point of Interest (POI), Internet of Things (IoT), Weather, Media, Messaging/Calling (VoIP), and parked-only Video, Games, and Browsers. There is no "driving task" equivalent.

Best fit: **POI**. A POI app shows places on a map with a list and detail panes using `PlaceListMapTemplate`, `PlaceListNavigationTemplate` (navigation-only), `MessageTemplate`, `PaneTemplate`, `ListTemplate`, `GridTemplate`, and `TabTemplate`. Convoy stops and members-as-places are legitimately points of interest. Google reviews whether the app's *primary purpose* matches the category, so the Android Auto surface must be convoy/stops-first with the score as a secondary pane.

Secondary option later: register also as **Messaging/VoIP** for push-to-talk, which allows voice interaction templates.

### Our Android Auto screens

```
TabTemplate
├─ Convoy    PlaceListMapTemplate: members and next stop as places; map provided by the host
├─ Stops     ListTemplate: proposals with vote counts; [Propose] opens a GridTemplate of categories
├─ Drive     PaneTemplate: "Clean so far" / score · streak · [Mark passenger]
└─ Talk      GridTemplate: PTT button
```

Driver-distraction constraints: template step limits (≤ 5 deep), no free scrolling, text truncation, no animations. Google requires the Car App Library's quality guidelines and tests on the Desktop Head Unit before Play review.

### Without Android Auto

- **Ongoing notification** with live score/limit and quick actions.
- **Spoken cues** via a foreground media session. Off by default.
- **Assistant shortcuts** for convoy actions.

### Built 2026-11-03: the car bridge, the live notification and the Android Auto app

Everything a car surface shows comes from one value, `CarSnapshot` (`app/lib/car/car_snapshot.dart`), built on the phone from the live Riverpod state (tracking, live limit, convoy members/positions/ETAs/stops, radio, crash) and pushed to the native side as JSON. Native code never reads the database or the convoy channel; it renders what it was given and sends taps back as named actions. The same snapshot feeds the iOS Live Activity (§2) and will feed CarPlay.

| Piece | Where |
|---|---|
| Snapshot model + pure builder, speeding tally | `app/lib/car/car_snapshot.dart` |
| Action names, `CarActionHandler` (applies taps to the app) | `app/lib/car/car_actions.dart` |
| Notification words ("Recording · Limit 35 · 31 mph · Clean so far") | `app/lib/car/ongoing_notification.dart` |
| `CarChannel`, `carSnapshotProvider`, `CarBridge` (≤ 1 send/s, skips unchanged) | `app/lib/car/car_bridge.dart`, watched from `lib/app/bootstrap.dart` |
| Android mirror: `CarState` (persisted snapshot + line + action queue), `CarPlugin` (the channel), `CarActions` (Dart or native fallback) | `app/android/app/src/main/kotlin/app/drivalry/car/` |
| Android Auto: `DrivalryCarAppService`, `MainTabScreen`, `ConvoyMapScreen`, `ProposeStopScreen` | same package; manifest `.car.DrivalryCarAppService`, `res/xml/automotive_app_desc.xml` |
| Live notification line + **Passenger** action | `TrackingService.kt` (`buildNotification`, `ACTION_MARK_PASSENGER`) |

#### 3.1 Screens as built

`TabTemplate` only accepts `ListTemplate`, `PaneTemplate`, `GridTemplate`, `MessageTemplate` and `SearchTemplate` as tab content, so the map is one step below the Convoy tab instead of being the tab itself:

```
TabTemplate (header: app icon; minCarApiLevel 6)
├─ Convoy  ListTemplate: destination row (→ ConvoyMapScreen, PlaceListMapTemplate: cars, regroup pin,
│          accepted stops, destination as places; the host draws the map), then cars leader-first /
│          nearest-first with gap · ETA · speed · "Fell behind" / "Gone quiet"
├─ Stops   ListTemplate: "Propose a stop" (→ ProposeStopScreen, GridTemplate of the six categories,
│          placed at the car's position), then stops with votes; the row toggle is "I'm in" (my upvote)
├─ Drive   PaneTemplate: Status / Speed · Limit · road / Trip; actions Passenger and End trip;
│          during a crash countdown: I'm OK / Send help
└─ Talk    GridTemplate: Talk (tap to talk, released after 20 s or on the next tap) and Radio on/off
```

Row titles stay constant while values change so updates count as template refreshes, not steps. Lists are clipped to the host's `ConstraintManager` content limit (usually 6) with a "+N more · on the map" row. Nothing from the feed, leagues or roasts is reachable. The car host can bind the service with the Flutter engine dead: the screens then show the persisted last snapshot marked "phone app asleep", End trip still works natively (`TrackingRuntime.forceEnd`), and every other tap is queued and replayed into Dart on the next launch (`drainActions`, after the tracking controller has imported the spool and finalised pending trips, so a queued "Passenger" flips a trip that ended meanwhile), with one toast asking to open the phone app (a queued action reports through `dispatch`'s return value only, never also through the callback).

#### 3.2 The ongoing notification

While a trip records, Dart sends the line and `TrackingService` re-posts the foreground notification (`setOnlyAlertOnce`, silent). Forms: `Recording · Limit 35 · 31 mph · Clean so far`, `… · 42 mph · 7 over`, `… · 31 mph · 2 min over so far`, `Recording · 41 mph · No limit data here`, `Recording · Passenger · not scored`, `Looks like a drive · confirming`; an active convoy adds the sub-line `Convoy · <name> · 3 cars`. Speeds use the limit's posted unit so the two numbers never disagree. Actions: **Passenger** (sets the trip's passenger hint now and records the answer once the trip ends, so the recording continues but is not scored) and **End trip**. A line is shown only if it belongs to the current trip; otherwise the static text appears.

#### 3.3 Channel contract: `app.drivalry/car`

Dart → native (MethodChannel):

| Method | Arguments | Notes |
|---|---|---|
| `snapshot` | `{json: String}` | the whole `CarSnapshot`; at most once a second, only when the content changed |
| `ongoingNotification` | `{title, text, subText?, passengerAction: bool, tripId?}` or `null` | null clears the live line; the service shows a line only for the trip it names, and never restores a persisted line without a `tripId` (a tentative-phase line must not describe the next drive) |
| `drainActions` | – | returns `[{name, args}]` taken while Dart was away |

Native → Dart: `action {name: String, args: Map}` → `true` when applied. Actions: `endTrip`, `markPassenger {tripId}`, `voteStop {convoyId, stopId, vote ∈ −1..1}`, `proposeStop {convoyId, category, name?}` (at the car's position), `talkStart {convoyId}` / `talkStop {convoyId}` (push-to-talk; the car releases after 20 s), `radioOn` / `radioOff {convoyId}`, `regroupHere {convoyId, name?}` (leader only), `crashOk`, `crashHelp`. Unknown names return `false`.

Snapshot JSON, version `v: 1` (`at` = epoch ms when built; `units` = `mph` | `kmh`; speeds in m/s, distances in metres):

```json
{"v":1,"at":1762200000000,"me":"<userId>","units":"mph",
 "drive":{"phase":"idle|tentative|active","tripId":"…","startedAt":0,"elapsedS":600,"distanceM":8046.7,
          "speedMps":13.4,"limitMps":15.65,"posted":35,"limitUnit":"mph|km/h","road":"Elm St",
          "overMps":0,"speedingS":0,"passenger":false,
          "status":"idle|tentative|passenger|over|cleanish|noLimit|clean"},
 "convoy":{"id":"…","name":"…","status":"planning|active","leaderId":"…",
           "destination":{"name":"…","lat":0,"lon":0},"regroup":{"name":"…","lat":0,"lon":0},
           "members":[{"id":"…","name":"…","initials":"AB","isMe":false,"isLeader":true,"lat":0,"lon":0,
                       "speedMps":0,"etaS":900,"distanceM":5560,"lost":"behind|silent|null",
                       "talking":false,"atMs":0}],
           "stops":[{"id":"…","name":"…","category":"gas|food|restroom|photo|lodging|charging",
                     "status":"proposed|accepted","lat":0,"lon":0,"up":2,"down":1,"myVote":1,
                     "distanceM":1200}]},
 "talk":{"available":true,"on":false,"holding":false,"talking":["Sam"],"peers":0,
         "reason":"noConvoy|convoyNotActive|signedOut|off|starting|noPermission|error|null"},
 "crash":{"countingDown":false,"secondsLeft":0,"unresolved":false}}
```

`convoy` is `null` when I am in none; rejected and done stops are left out; members are leader first then nearest first. `limitMps`, `posted` and `road` are null unless the match confidence is ≥ 0.7 (docs/01 §4.2). Native parsers (`CarSnapshot.kt`, the Live Activity plugin) default every missing field, so adding fields never needs a version bump.

#### 3.4 Testing on the Desktop Head Unit (owner, Windows)

1. Android Studio → *SDK Manager* → *SDK Tools* → install **Android Auto Desktop Head Unit Emulator**. It lands in `%LOCALAPPDATA%\Android\Sdk\extras\google\auto\`.
2. On the phone: install the debug APK (`flutter build apk --debug --dart-define-from-file=../.env`, then `adb install -r build/app/outputs/flutter-apk/app-debug.apk`), update **Android Auto** from Play, open its settings (*Settings → Connected devices → Connection preferences → Android Auto*), tap *Version* ten times to unlock developer settings, then in the ⋮ menu enable **Unknown sources** (needed for a sideloaded car app) and tap **Start head unit server**. Under *Previously connected cars* make sure *Add new cars to Android Auto* is on.
3. Plug the phone in over USB with the screen unlocked, then on the PC:

   ```
   adb forward tcp:5277 tcp:5277
   cd %LOCALAPPDATA%\Android\Sdk\extras\google\auto
   desktop-head-unit.exe
   ```

   (`desktop-head-unit.exe --usb` is the accessory-mode alternative; on Windows it may need the WinUSB driver and `adb kill-server` first.)
4. Accept the terms on the phone the first time. In the DHU, open the app launcher and tap **Drivalry**. Useful DHU console commands: `restrict all` (simulate driving), `night`, `-i rotary` at launch for a rotary head unit, `screenshot x.png`.
5. To see live numbers, start a trip with the Drive tab's simulator or drive; to see the convoy tabs, have an active convoy on the phone (a second phone or account for positions). With the phone app killed the DHU should show "phone app asleep" and a Passenger/End trip tap should still be acknowledged.

Logs: `adb logcat -s Drivalry.Car Drivalry.Service CarApp`.

#### 3.5 Play Console declaration (owner)

1. Play Console → the app → *Policy and programs → App content* → **Android Auto** (under "Car apps" / form factors): declare the app, choose category **Point of interest**, and confirm it uses the Car App Library templates only.
2. *Release → Advanced settings → Form factors*: Android Auto is a declaration, not a separate track; the same APK/AAB serves it. Upload a build whose manifest has the `androidx.car.app.CarAppService` intent filter with the `POI` category (already in `AndroidManifest.xml`).
3. Provide the review assets Google asks for: DHU screenshots of each tab, the map screen and the propose grid; a note that trips start automatically and that Talk needs an active convoy; the background-location disclosure video already prepared for the location policy (§5).
4. Before submitting, go through the [Car app quality guidelines](https://developer.android.com/docs/quality-guidelines/car-app-quality) on the DHU with `restrict all` on: no more than five template steps (ours: tabs → map or propose = 2), no free text paragraphs, every list within the content limit.
5. Later, if push-to-talk should be voice-interactive, add the **Messaging / VoIP** category as a second declaration; it is not needed for the Talk tab as built.

## 4. Flutter implementation

- **CarPlay**: `flutter_carplay` wraps the CarPlay template API for Flutter and is adopted once the entitlement arrives. Until then the Live Activity and spoken cues carry the in-drive experience.
- **Android Auto**: there is no mature Flutter plugin for the Car App Library, so the Android Auto surface is a small Kotlin `CarAppService` in `app/android`. It renders natively from one `CarSnapshot` that Dart pushes over `app.drivalry/car` (§3.3) and never opens the database or the convoy channel itself. It is a separate, tiny render tree, so it cannot accidentally show phone-only content.
- **Native pieces regardless**: iOS `PushToTalk` and the Live Activity (Swift + WidgetKit extension) live in `app/ios`; the Android ongoing notification and foreground services live in `app/android`. All of it is written on Windows. iOS code is compiled, signed and uploaded on the Mac, so iOS native code is kept small and compile errors are expected to round-trip.
- Keep the car UI driven by the same Riverpod state as the phone UI, but with its own widgets. Nothing from the feed, leagues or roast library is reachable from the car tree.

## 5. Submission checklist

**Apple**
- [ ] Entitlement granted (Driving Task; Voice Conversation if we speak in CarPlay)
- [ ] CarPlay screenshots from the simulator for every template state
- [ ] Nothing moves, scrolls, or shows paragraph text on the car screen
- [ ] "Always" location permission string explains automatic trip detection and friend circles
- [ ] Review notes describe how to trigger a trip in the simulator

**Google**
- [ ] Category: POI (and later Messaging) declared in the manifest and Play Console
- [ ] Background location policy: in-app disclosure, prominent, before the runtime prompt; demo video for Play review
- [ ] Car App Library quality guidelines pass on the Desktop Head Unit
- [ ] Foreground service types declared (`location`, `microphone` and `mediaPlayback` for PTT)
- [ ] Data safety form lists precise location, shared with other users, not sold
