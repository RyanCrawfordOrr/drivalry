# Building Drivalry for iOS on the Mac

Everything is authored on Windows; the Mac only builds, signs and uploads. The native
tracking plugin in `Runner/Tracking/` has never been compiled when it lands here, so expect
the first build to surface Swift errors. Fix them in Xcode, then copy the fixes back to
`C:\Drivalry\app\ios\Runner\Tracking\` (or describe them so they can be applied on Windows).

## 1. One-time setup

1. **Xcode** from the App Store (16 or newer), then open it once to accept the licence and
   install the iOS platform. Command line tools:
   ```sh
   xcode-select --install
   sudo xcode-select -s /Applications/Xcode.app
   ```
2. **Flutter 3.44.6** (the exact version the Windows side uses; `app/.metadata` pins the
   revision `ee80f08b`):
   ```sh
   git clone -b stable https://github.com/flutter/flutter.git ~/dev/flutter
   cd ~/dev/flutter && git checkout 3.44.6
   echo 'export PATH="$HOME/dev/flutter/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
   ```
   (Or download the 3.44.6 zip from docs.flutter.dev/release/archive and unzip it to `~/dev/flutter`.)
3. **CocoaPods** (google_maps_flutter_ios needs it; it has no Swift package):
   ```sh
   sudo gem install cocoapods      # or: brew install cocoapods
   ```
4. Check:
   ```sh
   flutter doctor -v
   ```
   Xcode and CocoaPods must both be green. Android toolchain warnings can be ignored here.

## 2. Get the repo and the secrets

```sh
git clone https://github.com/RyanCrawfordOrr/drivalry.git ~/dev/drivalry
cd ~/dev/drivalry
```

Copy the whole `C:\Drivalry\.env` to the repo root here. Every value in it is baked into the
build (Maps, Supabase, Google client IDs, Firebase, Metered, Spotify), so a partial copy
builds an app with sign-in or push silently disabled. `.env` is gitignored; move it over by
AirDrop or a password manager, never by committing it.

Check: `grep -c = .env` prints the same number on both machines.

## 3. Install dependencies

```sh
cd ~/dev/drivalry/app
flutter pub get
cd ios
pod install
```

`ios/Podfile` is committed with `platform :ios, '16.0'`. If CocoaPods complains about the
GoogleMaps version, run `pod repo update` and `pod install` again. If `pod install` ever
rewrites `project.pbxproj`, that is expected (it adds the Pods configuration).

All plugins go through CocoaPods: `pubspec.yaml` sets `flutter: config:
enable-swift-package-manager: false`. With Swift Package Manager on, Xcode cannot resolve
`firebase_messaging` (Firebase 13, GTMSessionFetcher 4.x) together with `google_sign_in_ios`
(GoogleSignIn 9.x, GTMSessionFetcher 3.x). Re-enable it once `google_sign_in_ios` moves to
GoogleSignIn 10; Firebase stops publishing new CocoaPods versions after October 2026.

## 4. Open and configure in Xcode

Always open the **workspace**, not the project:

```sh
open Runner.xcworkspace
```

Then, with the `Runner` target selected:

1. **Signing & Capabilities** → Team: pick your Apple Developer team. Bundle identifier must
   be `app.drivalry` (it already is in all three configurations; check that automatic signing
   did not append a suffix).
2. **Signing & Capabilities** → `+ Capability` → **Background Modes**, tick
   **Location updates** and **Remote notifications**. `Info.plist` already contains
   `UIBackgroundModes = [location, remote-notification]`; adding the capability only makes
   Xcode show it. Do not tick anything else.
3. **Signing & Capabilities** → `+ Capability` → **Push Notifications** (Firebase Cloud
   Messaging via APNs; the APNs key upload is docs/09-auth-setup.md §7 step 4). Xcode adds
   the `aps-environment` entitlement to `Runner.entitlements`.
4. **Signing & Capabilities** → `+ Capability` → **Sign in with Apple**
   (docs/09-auth-setup.md §2 step 3). This also lands in `Runner.entitlements`; commit that
   file together with the `project.pbxproj` change.
5. `Info.plist` already declares the `drivalry://` URL scheme (`CFBundleURLTypes`, name
   `app.drivalry`) for invite links; nothing to add in Xcode, but check it survived if
   Xcode rewrites the plist.
6. **General** → Minimum Deployments must read **iOS 16.0** (set in `project.pbxproj`).
7. If the files under `Runner › Tracking` show in **red** in the navigator, the group
   reference did not survive the Windows edit: right-click the `Tracking` group → Delete →
   *Remove Reference*, then right-click `Runner` → *Add Files to "Runner"…* → select the
   `Runner/Tracking` folder, tick *Create groups* and the *Runner* target → Add.
   The same applies to `Runner/PrivacyInfo.xcprivacy`, the privacy manifest Apple requires
   since May 2024: it is registered in the project from Windows and must show in black under
   `Runner`. If it is red or missing, *Add Files to "Runner"…* → that file, target Runner.

8. **Live Activity widget extension** (docs/04 §2). The sources are already in
   `ios/DrivalryWidgets/`; Xcode has to create the target:
   1. *File › New › Target…* → **Widget Extension** → Product Name `DrivalryWidgets`,
      tick **Include Live Activity**, untick *Include Configuration App Intent* → Finish →
      *Activate* the scheme when asked. Bundle id becomes `app.drivalry.DrivalryWidgets`;
      the extension's Minimum Deployment must be **iOS 16.2** (General tab).
   2. Xcode generated `DrivalryWidgets/DrivalryWidgetsBundle.swift`, `DrivalryWidgets.swift`,
      `DrivalryWidgetsLiveActivity.swift`, `Assets.xcassets` and an `Info.plist`. Delete
      the three generated `.swift` files and the generated `Info.plist` (*Move to Trash*),
      keep `Assets.xcassets`.
   3. Right-click the `DrivalryWidgets` group → *Add Files to "Runner"…* → select
      `DrivalryWidgetsBundle.swift`, `DriveLiveActivity.swift` and `Info.plist` from
      `ios/DrivalryWidgets/`, target **DrivalryWidgets** only.
   4. Select `Runner/Tracking/DriveActivityAttributes.swift` in the navigator → File
      inspector → *Target Membership*: tick **DrivalryWidgets** as well as Runner. The
      ActivityKit type must compile into both.
   5. *Signing & Capabilities* for the extension: same team, automatic signing.
   6. `Runner/Info.plist` already has `NSSupportsLiveActivities = YES`. Build and run the
      **Runner** scheme; start a drive (or the simulator trip in Diagnostics) and the
      activity appears on the lock screen and in the Dynamic Island (iPhone 14 Pro or
      later; other models show the lock-screen banner only).
   7. Run `flutter build ipa` as usual; the extension is embedded automatically once the
      target exists. If `flutter build` complains about the extension's deployment target,
      set it to 16.2 in the extension target, not in the Podfile.
9. **CarPlay** stays off until Apple grants the entitlement; the steps are in
   `docs/04-car-platforms.md` §2 "When the entitlement arrives".

## 5. Build to a device

1. Plug in an iPhone, unlock it, trust the Mac. On the phone enable *Settings › Privacy &
   Security › Developer Mode* (iOS 16+) and restart it when asked.
2. In Xcode pick the phone as the run destination and press **Run** (⌘R), or from the shell:
   ```sh
   cd ~/dev/drivalry/app
   flutter run --dart-define-from-file=../.env
   ```
3. First launch: wherever the Dart side calls `requestPermissions` (Drive tab onboarding),
   the prompts appear in order: location while in use → Always → Motion & Fitness →
   notifications. For automatic trip detection the location choice must end up as
   **Always**; `openSettings` opens the system page if it was declined.

If Xcode stops with an error inside `Runner/Tracking/*.swift`, fix it there; the files are
plain Swift with no generated code. Common first-build issues: a renamed delegate method,
an API marked unavailable on the chosen iOS target, or a missing `import`.

## 6. Release build (.ipa)

`tools/release/build_ios.sh` is the iOS twin of the Android release script: version name from
`pubspec.yaml`, build number = number of commits on the branch, `.env` baked in.

1. Commit first. App Store Connect refuses a build number it has already seen for this
   version, and the number only grows with a new commit.
2. Build:
   ```sh
   cd ~/dev/drivalry
   tools/release/build_ios.sh
   ```
   Five to ten minutes. The last lines read `Done: …/build/ios/ipa/….ipa (NN MB), version
   1.0.0 (CODE)`. Check: the `.ipa` exists and CODE is higher than the last one you uploaded.
   If the build stops on signing, open `Runner.xcworkspace` and fix the team under
   *Signing & Capabilities* (§4 step 1); automatic signing creates the App Store profile.
3. Upload: open **Transporter** (free, Mac App Store), sign in with the developer Apple ID,
   drag the `.ipa` in, **Deliver**. Or Xcode → *Window › Organizer* → the archive →
   **Distribute App** → *App Store Connect*. Check: App Store Connect → Drivalry →
   **TestFlight** → *iOS Builds* lists `1.0.0 (CODE)` as *Processing*, then *Ready to Submit*
   after 10 to 30 minutes (Apple emails when it is done).
4. Attach it: https://appstoreconnect.apple.com/apps/6830844356/distribution/ios/version/inflight
   → **Build** → **Add Build** → pick `1.0.0 (CODE)` → **Done** → **Save**. Check: the build
   shows under *Build* with no *Missing Compliance* badge (`Info.plist` already answers the
   export-compliance question with `ITSAppUsesNonExemptEncryption = NO`: TLS and WebRTC's
   standard DTLS-SRTP only).

For test installs on the five iPhones without TestFlight: `tools/release/build_ios.sh --ad-hoc`
(the phones must be registered under *Devices* in the developer account), then drag the
`.ipa` onto the phone in Finder.

## 7. What the tracking plugin needs on the phone

- Location **Always** with Precise on, Motion & Fitness on. Without Always, trips only
  record while the app is open or in the background after being opened.
- Background relaunch is driven by significant-change monitoring and a 100 m region around
  the last parking spot (see `docs/08-tracking-channel.md` §6). To test, end a trip, kill the
  app from the switcher, drive away: the app should wake and record. The Diagnostics screen
  (`getDiagnostics`) shows `lastTriggerKind` and the counters.
- Battery targets: under 1 % per day parked, under 6 % per hour driving.
