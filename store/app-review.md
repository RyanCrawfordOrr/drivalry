# Resubmit Drivalry to App Review: every step, in order

Apple paused the review of 1.0.0 with a *Guideline 2.1 - Information Needed* message. They want a screen recording, a description, setup instructions, the list of outside services, regional differences and a word on regulated content. All of that is below, in the order you do it. Nothing here points anywhere else; if a step says to paste something, the thing to paste is right there.

**What you need:** your Windows PC; the Mac with the repo at `~/dev/drivalry` and the `.env` file already in it (the same Mac that built the last upload); an iPhone on the latest iOS with a cable; your own phone signed in to Drivalry; about two hours, half of it waiting for Apple to process the build.

**Why a new build:** the notes Apple read said "open Drive → menu → Simulate a drive". That menu only exists in debug builds, so the reviewer had no way to see a scored trip. The build you upload below has **See a sample drive** on the Drive tab, a working **Report**, and **Block** everywhere a person appears.

---

## Step 1. Create the two new database tables (PC, 3 minutes)

1. Open https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/sql/new
2. Open PowerShell (Start → type `PowerShell` → Enter) and run:
   ```powershell
   Get-Content -Raw C:\Drivalry\supabase\migrations\0008_blocks_reports.sql | Set-Clipboard
   ```
3. Click inside the SQL editor, press Ctrl+A, then Ctrl+V, then **Run** (bottom right).

**Check it worked.** The result panel says *Success. No rows returned*. To be sure, replace the editor text with this and **Run**; it must print `true`:
```sql
select to_regclass('public.user_blocks') is not null
   and to_regclass('public.content_reports') is not null as ok;
```

**If it fails.** `relation "profiles" does not exist`: the earlier migrations were never applied; run `0001` to `0007` the same way first (same PowerShell line with each file name). Anything else: paste the red error text into the chat.

---

## Step 2. Build the new app and send it to Apple (Mac, 15 minutes plus waiting)

1. On the Mac open Terminal and run:
   ```sh
   cd ~/dev/drivalry
   git pull
   tools/release/build_ios.sh
   ```
   Five to ten minutes. The last lines read `Done: …/build/ios/ipa/….ipa (NN MB), version 1.0.0 (CODE)`. Write down CODE; you need it twice below.
2. Open **Transporter** (free, Mac App Store), sign in with the developer Apple ID, drag the `.ipa` from `~/dev/drivalry/app/build/ios/ipa/` into the window, click **Deliver**.
3. Wait for Apple's email *"The following build has completed processing"* (10 to 30 minutes). Meanwhile do Step 4.

**Check it worked.** https://appstoreconnect.apple.com/apps/6830844356/testflight/ios lists **1.0.0 (CODE)** with status *Ready to Submit*.

**If it fails.** `git pull` says the folder does not exist: the repo was cloned somewhere else; `cd` there instead. The build stops on signing: open `~/dev/drivalry/app/ios/Runner.xcworkspace` in Xcode → Runner target → *Signing & Capabilities* → pick your team → run the build command again. Transporter rejects the file: the build number CODE was already uploaded; make any small commit on the PC (`git commit --allow-empty -m "bump"` then `git push`), `git pull` on the Mac, build again.

---

## Step 3. Attach the build to version 1.0.0 (browser, 2 minutes)

1. Open https://appstoreconnect.apple.com/apps/6830844356/distribution/ios/version/inflight
2. Scroll to **Build** → **Add Build** (or the **+**) → pick **1.0.0 (CODE)** → **Done**.
3. Click **Save** (top right).

**Check it worked.** The Build section shows 1.0.0 (CODE) with no *Missing Compliance* warning.

**If it fails.** The build is not in the list: it is still processing; wait for the email from Step 2 and reload.

---

## Step 4. Make the review league and circle, write down the codes (your own phone, 5 minutes)

Use the phone you normally use, signed in as yourself. The reviewer will join these to see posts, standings and the live map.

1. **Leagues** tab → the **+** at the top right (tooltip *New league*) → **Create a league** → name `App Review` → **Create league**. The league opens. Tap **Invite** (top right). Write down the code shown (letters and digits).
2. **Friends** tab → **Circles** tab at the top → **New circle** → name `App Review` → **Create circle**. The circle opens. Tap **Invite** (top right). Write down that code too.
3. Tap your avatar on the Drive tab → your handle is under your name, like `@ryan`. Write it down.

Your own scored drives already post to the feed, so the reviewer will see trip cards as soon as they join the league. If you have not driven in a while, drive once before Step 6.

**Check it worked.** Both codes are 6 to 8 characters and the two screens show you as the only member.

---

## Step 5. Record the video (iPhone, 15 minutes)

### 5a. Put the new build on the iPhone

1. If Drivalry is on the iPhone, delete it (hold the icon → **Remove App** → **Delete App**), so the recording starts with the first-run pages.
2. Plug the iPhone into the Mac, unlock it, tap **Trust** if asked. In Terminal:
   ```sh
   cd ~/dev/drivalry/app
   flutter run --release --dart-define-from-file=../.env
   ```
   Wait for `Installing and launching…` and then the app on the phone. Press `q` in Terminal to quit; the app stays installed.
3. Unplug the phone. Open **Settings → Control Center** on the iPhone and make sure **Screen Recording** is in the list of included controls (tap the green **+** next to it if not).

**Check it worked.** Open Drivalry: the first page says *Every drive gets a score.* Close it with a swipe up.

**If it fails.** `flutter run` cannot see the phone: *Settings → Privacy & Security → Developer Mode* on the iPhone must be on (restart when asked), then run the command again.

### 5b. Record, shot by shot

Go to the Home Screen. Swipe down from the top right, tap the **record** button (circle in a circle), wait for the 3-second countdown, then:

| # | Do | What the reviewer sees |
| --- | --- | --- |
| 1 | Tap the Drivalry icon | Launch, then *Every drive gets a score.* |
| 2 | **Next** → **Allow** → **Allow While Using App** → **Allow** on the motion page | The first-run pages and the system prompts |
| 3 | On the Drive tab tap **See a sample drive** → **A messy commute** | The trip page: score, verdict, events on the map. Scroll to the bottom and back up |
| 4 | Back → tap the round person icon (top right) → **Continue with Apple** → on Apple's sheet choose **Hide My Email** → confirm with Face ID | A new account is created. **Hide My Email matters**: it keeps this throwaway account separate from your real one, which you must not delete in shot 13 |
| 5 | Tap your avatar → the profile page | The generated handle |
| 6 | **Leagues** tab → **Create or join** (or the **+**) → **Join with a code** → type the league code from Step 4 → **Join** | Standings with you in them |
| 7 | **Friends** tab | The feed with your real trip posts |
| 8 | Long-press a post → tap a reaction | The actions sheet (React / Comment / Share / Report / Block), the reaction lands |
| 9 | Tap a post → type `Nice drive` → **Send** | The comment appears |
| 10 | Back → long-press a different post → **Report** → **Abusive or hateful** | *Reported. The post is hidden for you…* and the post disappears |
| 11 | Long-press another post → **Block …** → **Block** | *Blocked …* and that person's posts disappear |
| 12 | Avatar → profile → gear (top right) → **Blocked people** → **Unblock** → back twice → **Friends** tab → pull down to refresh | The blocked list, then empty, then the posts are back |
| 13 | Avatar → profile → gear → scroll to **Account** → **Delete account** → **Delete** | *Account deleted.* and the Drive tab signed out |
| 14 | Swipe down from the top right → tap the red record button to stop | |

Keep it under four minutes. No narration needed.

**Check it worked.** Photos → the newest video plays and starts on the Home Screen. AirDrop it to the Mac (share → AirDrop → the Mac) or leave it on the phone and do Step 6 from the phone's browser later; either works.

**If it fails.** Shot 6 says the code is wrong: 0 and O look alike; read the code again from the league's Invite screen on your other phone. Shot 11 shows no Block: you long-pressed your own post; pick one by the other account.

---

## Step 6. Fill in App Review Information (browser, 10 minutes)

1. Open https://appstoreconnect.apple.com/apps/6830844356/distribution/ios/version/inflight and scroll to **App Review Information**.
2. **Sign-In required**: leave it **off** (the app works without an account).
3. **Contact Information**: first name, last name, phone number, email. All four.
4. **Notes**: paste the block below. Before you paste, replace the six bracketed values: the league code, the circle code and your handle from Step 4, CODE from Step 2, and the iPhone model and iOS version from the phone's *Settings → General → About*.
5. **Attachments** (just under Notes): **Choose File** → the video. If it refuses the file, put the video in iCloud Drive or Google Drive, turn on link sharing, and paste that link in the Notes where it says `[VIDEO LINK]`.
6. **Save** (top right).

```
WHAT DRIVALRY IS, AND FOR WHOM
Drivalry is a "step challenge for driving". The phone notices when the user drives and scores each trip from 0 to 100 on the device (speed against the posted limit, smoothness, phone handling). Friends compete in weekly leagues on those scores; good drives get praise and bad ones get a one-line "roast" from a fixed template library. It is for friends, families and car clubs who want a reason to drive more calmly; nothing in the app rewards speed or distance. Around that: a live-location map shared only with chosen friends ("circles"), road-trip "convoys" with a shared map and push-to-talk radio, crash detection that texts emergency contacts, and a garage for fuel and maintenance notes. Free, no ads, no in-app purchases, no subscriptions. Age 16+.

HOW TO SIGN IN (there is no password to give you)
The app has no email/password login, so no demo credentials exist. Sign in with Apple creates an account instantly: on the Drive tab tap the round person icon (top right) → "Continue with Apple" → use any Apple ID. A handle such as @driver_1234 is generated automatically; "Continue with Google" works too. Account deletion: person icon → Profile → gear (Settings) → Account → "Delete account" → Delete. It removes the profile, friendships, posts and memberships from our database immediately.
Most of the app works without an account (trip scoring, garage). Friends, leagues, the feed, circles and convoys need one.

HOW TO SEE THE MAIN FEATURES WITHOUT DRIVING
1. A scored trip: Drive tab → "See a sample drive" (under "Go for a drive") → "A messy commute". A pretend 20-minute trip runs through the same scoring as a real one and opens: score, verdict, events on the map. Also at Settings → Drives → Sample drive. Sample drives stay on the phone and never post to friends.
2. Real trips start on their own from motion and location, which is why first launch asks for "Always" location and Motion & Fitness. "Not now" is fine on both pages; the sample drive still works.
3. Friends and the feed: Leagues tab → "Join with a code" → [LEAGUE CODE]. This is a league we made for review; it has standings and trip posts from our test driver, and sharing a league makes those posts visible in your Friends tab feed. You can also add us: Friends tab → Add friend → search [YOUR HANDLE].
4. User-generated content and moderation: posts are trip cards with a template verdict; people react (six fixed emoji) and comment (free text, 280 characters). Long-press any post → React / Comment / Share / Report / Block. On a post's page the ⋮ menu has Report post and Block, and a long-press on a comment offers Report comment / Block. Reporting hides the content for the reporter at once and files a report that a person reviews within 24 hours. Blocking removes the person from your feed, comments, map, friends list and requests in both directions; Settings → Friends → Blocked people lists them with Unblock.
5. Live-location map: Friends tab → Circles → "Join with code" → [CIRCLE CODE]. Our test phone then appears on the Drive-tab map. Sharing is opt-in per circle and "Hide my location" (Settings → Friends) stops it with one switch.
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
Attached under App Review Information (also at [VIDEO LINK]). Captured on an iPhone [MODEL] running iOS [VERSION] with build 1.0.0 ([CODE]): launch, first-run pages, sample drive, Sign in with Apple, joining the review league, the feed, commenting, reporting a post, blocking and unblocking a person, and account deletion.
```

**Check it worked.** After Save, the Notes show your real codes (no square brackets left) and the Attachments row lists the video.

---

## Step 7. Reply to Apple and submit (browser, 2 minutes)

1. On the same page, Apple's message sits at the top under **App Review** (if not, click **App Review** in the left column of https://appstoreconnect.apple.com/apps/6830844356). Click **Reply** and paste:
   > Thank you. A new build (1.0.0 CODE) with the sample drive, report and block flows is attached, the screen recording is under Attachments, and the requested information is in the Notes.
   Send it.
2. Back on the version page click **Submit for Review** (on some accounts it reads **Add for Review**, then **Submit to App Review** on the next page).

**Check it worked.** The version status at the top reads **Waiting for Review**.

**If it fails.** The submit button is grey: either no build is attached (Step 3), App Privacy is not published (left column → **App Privacy** → **Publish**), or Contact Information is empty (Step 6). The reply box is missing: replying is optional; the Notes carry everything.

---

## Afterwards: when someone reports a post (optional, 10 minutes once)

The Notes promise that a person reads every report within 24 hours. Reports land in a table you read in the Supabase dashboard; this sends you a push notification for each one so you do not have to look. Skip it if you have not set up push notifications yet (no `push` function deployed); the table still fills up and you can check it by hand.

1. Your user id: https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/auth/users → the **UID** column of your own row → copy it.
2. In PowerShell:
   ```powershell
   cd C:\Drivalry
   supabase secrets set MODERATOR_USER_ID=PASTE_YOUR_UID --project-ref htqyutdwnnguqatakofx
   supabase functions deploy push --project-ref htqyutdwnnguqatakofx --use-api
   ```
3. https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/integrations/webhooks/overview → open the existing `push_feed_reactions` hook and copy the value of its `x-push-secret` header → **Create a new hook**: name `push_content_reports`, table `content_reports`, events **Insert**, type **HTTP Request**, method `POST`, URL `https://htqyutdwnnguqatakofx.supabase.co/functions/v1/push`, add header `x-push-secret` with the copied value → **Create webhook**.

**Check it worked.** From any second account, long-press one of your posts → **Report** → any reason. Your phone shows *Content report* within seconds.

**Handling a report.** https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/editor → **content_reports**. The `snapshot` column holds the reported text. To take a post down: **feed_posts** → filter `id` = the report's `post_id` → select the row → **Delete** (comments and reactions go with it). For a comment: **feed_comments** and its `comment_id`. For a repeat offender: **Authentication → Users** → the account → **Delete user**. Then set the report's `status` to `actioned` (or `reviewed` if you left it up). The reporter never sees the content again either way.
