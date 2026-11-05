# App Review: the "Information Needed" reply (Guideline 2.1)

Apple paused the first review of Drivalry 1.0.0 with a *Guideline 2.1 - Information Needed* message. It asks for six things, all of which go into **App Store Connect → Drivalry → the 1.0.0 version page → App Review Information** before the app is resubmitted:

1. a screen recording from a physical iPhone on the latest iOS, starting at launch, showing sign-up, sign-in, account deletion and the user-generated-content reporting and blocking flows;
2. what the app is for and who it is for;
3. how to set up and reach the main features, with any credentials;
4. the external services the app uses;
5. regional differences;
6. whether the app is in a regulated industry or ships protected third-party material.

`docs/11-owner-setup.md` **Part 16** is the click-by-click order of operations (apply migration 0008, build, record, paste, resubmit). This file holds the words.

## Why a new build is needed

The notes that were on the record said "open Drive → menu → Simulate a drive". That menu only exists in debug builds, so the reviewer had no way to see a scored trip. The release build now has **See a sample drive** on the Drive tab's empty state and **Settings → Drives → Sample drive**; sample drives stay on the phone and never post, upload or count. The feed's **Report** action now files a real report (and hides the content for the reporter), **Block** exists on posts, comments, friends, requests and profiles, and **Settings → Friends → Blocked people** lists them with Unblock. Migration `0008_blocks_reports.sql` carries the tables and policies.

## The Notes field

Paste the block below into **App Review Information → Notes**. Replace every `[…]` first: the league and circle codes come from the app on your own phone (Part 16 step 4), the handle is on your Profile, the build number is what `tools/release/build_ios.sh` printed.

```
WHAT DRIVALRY IS, AND FOR WHOM
Drivalry is a "step challenge for driving". The phone notices when the user drives and scores each trip from 0 to 100 on the device (speed against the posted limit, smoothness, phone handling). Friends compete in weekly leagues on those scores, good drives get praise and bad ones get a one-line "roast" from a fixed template library. It is for friends, families and car clubs who want a reason to drive more calmly; nothing in the app rewards speed or distance. Around that: a live-location map shared only with chosen friends ("circles"), road-trip "convoys" with a shared map and push-to-talk radio, crash detection that texts emergency contacts, and a garage for fuel and maintenance notes. Free, no ads, no in-app purchases, no subscriptions. Age 16+.

HOW TO SIGN IN (there is no password to give you)
The app has no email/password login, so no demo credentials exist. Sign in with Apple creates an account instantly: on the Drive tab tap the round person icon (top right) → "Continue with Apple" → use any Apple ID. A handle such as @driver_1234 is generated automatically; "Continue with Google" works too. Account deletion: person icon → Profile → gear (Settings) → Account → "Delete account" → Delete. It removes the profile, friendships, posts and memberships from our database immediately.
Most of the app works without an account (trip scoring, garage). Friends, leagues, the feed, circles and convoys need one.

HOW TO SEE THE MAIN FEATURES WITHOUT DRIVING
1. A scored trip: Drive tab → "See a sample drive" (under "Go for a drive") → "A messy commute". A pretend 20-minute trip runs through the same scoring as a real one and opens: score, verdict, events on the map. Also at Settings → Drives → Sample drive. Sample drives stay on the phone and never post to friends.
2. Real trips start on their own from motion and location, which is why first launch asks for "Always" location and Motion & Fitness. "Not now" is fine on both pages; the sample drive still works.
3. Friends and the feed: Leagues tab → "Join with a code" → [LEAGUE CODE]. This is a league we made for review; it has standings and trip posts from our test drivers, and sharing a league makes their posts visible in your Friends tab feed. You can also add us: Friends tab → Add friend → search [YOUR HANDLE].
4. User-generated content and moderation: posts are trip cards with a template verdict; people react (six fixed emoji) and comment (free text, 280 characters). Long-press any post → React / Comment / Share / Report / Block. On a post's page the ⋮ menu has Report post and Block, and a long-press on a comment offers Report comment / Block. Reporting hides the content for the reporter at once and files a report that a person reviews within 24 hours. Blocking removes the person from your feed, comments, map, friends list and requests in both directions; Settings → Friends → Blocked people lists them with Unblock.
5. Live-location map: Friends tab → Circles → "Join with a code" → [CIRCLE CODE]. Our test phone then appears on the Drive-tab map. Sharing is opt-in per circle and "Hide my location" (Settings → Friends) stops it with one switch.
6. Convoy push-to-talk needs two phones in one convoy and Convoy DJ needs a Spotify Premium account; both are optional and not needed to review the app.

EXTERNAL SERVICES
- Supabase (authentication, Postgres database, realtime, storage, edge functions): accounts, friends, leagues, trip summaries, feed, live positions, push fan-out.
- Sign in with Apple and Google Sign-In: identity only.
- Google Maps SDK for iOS (map tiles), Google Places API (convoy stop suggestions), Google Routes API (convoy ETAs).
- Firebase Cloud Messaging with APNs: push notifications.
- OpenStreetMap data: we build offline speed-limit packs from OSM and host them on GitHub Releases; Nominatim gives place names for trips.
- Open-Meteo: weather on trip cards.
- Metered.ca TURN relay: carries convoy push-to-talk audio (WebRTC) when a direct connection fails.
- Spotify Web API: the optional Convoy DJ feature, through the user's own Spotify account.
No AI services, no analytics SDK, no ad networks, no payment processors. Raw GPS traces never leave the phone; only trip summaries (score, distance, duration, verdict) are uploaded.

REGIONAL DIFFERENCES
The app behaves the same in every region, with one data limitation: posted speed limits exist as offline packs for the United States only (every state plus DC) so far. Elsewhere a trip is still detected and scored for smoothness and phone handling, no speeding events can be flagged, and the app shows the limit as unknown. Units follow the region (mph or km/h) and can be set by hand. Map tiles are Google Maps, within Google's coverage. The app is not offered in France.

REGULATED INDUSTRY AND THIRD-PARTY MATERIAL
Drivalry is not in a regulated industry: no insurance, no fleet or employer use, no payments. Third-party material: OpenStreetMap data under the ODbL, credited at Settings → About; Google Maps under the Google Maps Platform terms, with Google's attribution on every map; weather from Open-Meteo (CC BY 4.0). No licensed music or media ships in the app; Convoy DJ plays inside the user's own Spotify app.

SCREEN RECORDING
Attached under App Review Information (also at [VIDEO LINK]). Captured on an iPhone [MODEL] running iOS [VERSION] with build 1.0.0 ([BUILD]): launch, first-run pages, sample drive, Sign in with Apple, joining the review league, the feed, reporting a post, blocking and unblocking a person, commenting, and account deletion.
```

## The recording, shot by shot

Use an iPhone on the **latest public iOS** with the build you are submitting installed from TestFlight. Start recording from Control Center (Settings → Control Center → add **Screen Recording** first), then go to the Home Screen. Speak nothing; the recording needs no sound. Delete the app before you start so the first-run pages appear. Keep it under four minutes.

| # | Do | What the reviewer sees |
| --- | --- | --- |
| 1 | Tap the Drivalry icon on the Home Screen | Launch, then "Every drive gets a score." |
| 2 | **Next** → **Allow** → choose **Allow While Using App**, then **Allow** again if iOS asks about Always → **Allow** on the motion page | The three first-run pages and the system prompts |
| 3 | On the Drive tab tap **See a sample drive** → **A messy commute** | The sheet, then the trip page: score, verdict, the events; scroll to the bottom and back |
| 4 | Back → tap the round person icon (top right) → **Continue with Apple** → confirm with Face ID | Account creation; the Drive tab now shows your avatar |
| 5 | Tap the avatar → Profile | The generated handle and name |
| 6 | **Leagues** tab → **Join with a code** → type the review league's code → **Join** | Standings with the test drivers |
| 7 | **Friends** tab | The feed with their trip posts |
| 8 | Long-press a post → tap a reaction | React / Comment / Share / Report / Block in the sheet; the reaction lands |
| 9 | Long-press another post → **Report** → **Abusive or hateful** | "Reported. The post is hidden for you…" and the post disappears |
| 10 | Tap a post → type a comment → send | The comment appears |
| 11 | Long-press someone else's comment → **Block …** → **Block** | "Blocked …" and their comment disappears |
| 12 | Back → avatar → Profile → gear → **Friends → Blocked people** → **Unblock** | The list, then empty |
| 13 | Settings → **Account → Delete account** → **Delete** | "Account deleted." and the Drive tab signed out |
| 14 | Stop the recording | |

The file lands in Photos. AirDrop it to the Mac, or share it to Files. App Store Connect accepts it under **App Review Information → Attachments** (up to 3 files; `.mov` and `.mp4` are fine). If the upload is refused for size, put it in iCloud Drive or Google Drive with link sharing on and paste that link where the Notes say `[VIDEO LINK]`.

## Checks before you press Submit

- The build attached to the version is the one with **See a sample drive** on an empty Drive tab (TestFlight → install → check).
- Migration `0008` is applied (Part 1 check query shows `0008 applied = true`); without it Report and Block fail quietly in the background.
- The league and circle codes in the Notes open on a second phone.
- **Sign-In required** under App Review Information stays **off** (the app works without an account), and the Notes explain Sign in with Apple.
- **Contact Information** has your name, phone and email.
- App Privacy is **Published**.
