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

## 4. Flutter implementation

- **CarPlay**: `flutter_carplay` wraps the CarPlay template API for Flutter and is adopted once the entitlement arrives. Until then the Live Activity and spoken cues carry the in-drive experience.
- **Android Auto**: there is no mature Flutter plugin for the Car App Library, so the Android Auto surface is a small Kotlin `CarAppService` in `app/android`. It reads the same drift database and convoy state through a platform channel and renders templates natively. It is a separate, tiny render tree, so it cannot accidentally show phone-only content.
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
