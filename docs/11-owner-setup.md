# Drivalry: owner setup, step by step

> Everything the app needs that only the account owner can do. All the code is already in the repo and on your phone; these steps switch the features on. Nothing here costs money. Work through the parts in order. Each part ends with a check that tells you it worked and a list of what to do if it did not.

## How to read this page

- **Where you type things.** Commands sit in boxes marked `powershell`. Open PowerShell with Start → type `PowerShell` → Enter. Paste with Ctrl+V. A command runs from any folder unless it begins with `cd`.
- **Dashboards.** Links open the exact page. Button names are in **bold**. If a label on your screen is worded a little differently, pick the one that means the same thing; these sites rename things now and then.
- **Your `.env` file.** It is `C:\Drivalry\.env`. Open it with `notepad C:\Drivalry\.env`. Every line is `NAME=value` with no spaces around the `=` and no quotes. The file is gitignored and never leaves your PC. After any change, rebuild and reinstall (Part 4) or the phone will not see it.
- **Two things never to do.** Never paste the Supabase *secret* key (it starts with `sb_secret_` or is labelled `service_role`) anywhere but the Supabase dashboard itself, and never into the chat. Never commit `.env`.

### Where you are right now

| | State |
| --- | --- |
| Phone | Android, debug build installed over adb. Trips, scoring, roasts, badges and speed-limit packs already work offline. |
| `.env` | `GOOGLE_MAPS_API_KEY`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` filled in. Everything else blank. |
| Supabase | Project `htqyutdwnnguqatakofx`. Only `0000_heartbeat.sql` has been applied. |
| GitHub | Both repo secrets set. CI and the daily keep-alive already run. |

Parts 1 to 4 make the Android phone work end to end: sign in, friends, leagues, convoys, radio. Part 5 adds push notifications. Parts 6 to 8 are optional or for later.

---

## Part 1: Create the database tables (15 minutes)

**Unlocks:** everything that touches the cloud. Until this is done every signed-in screen fails.

You paste seven SQL files into the Supabase SQL editor, one at a time, in order.

1. Open the SQL editor: https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/sql/new
2. In PowerShell, copy the first file to the clipboard:
   ```powershell
   Get-Content -Raw C:\Drivalry\supabase\migrations\0001_init.sql | Set-Clipboard
   ```
3. Click inside the editor, press Ctrl+A then Ctrl+V so the file replaces whatever is there, then click **Run** (bottom right, or Ctrl+Enter).
4. Wait for the result panel. **Success. No rows returned** means it worked. `0001` takes a few seconds; the others are instant.
5. Repeat steps 2 to 4 for each remaining file, in this order. Run one line below, paste and **Run** in the editor, then the next line:
   ```powershell
   Get-Content -Raw C:\Drivalry\supabase\migrations\0002_presence_friends_account.sql | Set-Clipboard
   Get-Content -Raw C:\Drivalry\supabase\migrations\0003_checkins.sql | Set-Clipboard
   Get-Content -Raw C:\Drivalry\supabase\migrations\0004_crash_contacts.sql | Set-Clipboard
   Get-Content -Raw C:\Drivalry\supabase\migrations\0005_convoy_vote_withdraw.sql | Set-Clipboard
   Get-Content -Raw C:\Drivalry\supabase\migrations\0006_convoy_can_view.sql | Set-Clipboard
   Get-Content -Raw C:\Drivalry\supabase\migrations\0007_duels_challenges_seasons.sql | Set-Clipboard
   ```

**Check it worked.** Paste this into the editor and **Run**. Every column must read `true`:

```sql
select
  (to_regclass('public.profiles') is not null)                                        as "0001 applied",
  (to_regprocedure('public.delete_own_account()') is not null)                        as "0002 applied",
  exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
          where t.typname = 'post_kind' and e.enumlabel = 'checkin')                  as "0003 applied",
  exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'crash_alerts'
            and column_name = 'notify_user_ids')                                      as "0004 applied",
  exists (select 1 from pg_policies where schemaname = 'public'
          and tablename = 'convoy_stop_votes' and policyname = 'convoy_stop_votes_delete') as "0005 applied",
  coalesce((select pg_get_functiondef(p.oid) ilike '%convoy_members%'
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'can_view'), false)            as "0006 applied",
  (to_regclass('public.duels') is not null)                                           as "0007 applied";
```

Then check the scheduled jobs. Expect five rows: `finalize-duels`, `finalize-group-challenges`, `finalize-leagues`, `matchmake-global-leagues`, `prune-cloud`.

```sql
select jobname, schedule from cron.job order by jobname;
```

**If something fails.**

- `type "league_tier" already exists` or `relation "profiles" already exists` while running `0001`: it was applied before. Skip to `0002`.
- `extension "pg_cron" is not available` or `schema "cron" does not exist`: Dashboard → **Database** → **Extensions** → search `pg_cron` → switch it on → run that file again.
- Anything else: copy the red error text and paste it into the chat. Fixes go into a new numbered file; nothing already applied is edited in place.

---

## Part 2: Google sign-in on Android (20 minutes)

**Unlocks:** accounts. **Continue with Google** on the Profile tab works, and friends, leagues, circles and convoys become usable.

Three things have to agree: a Google Cloud OAuth setup that knows your debug build, a Supabase provider that trusts it, and the web client id in `.env`.

### 2a. Google Cloud: consent screen and test users

1. https://console.cloud.google.com/auth/overview?project=drivalry. Check the project picker at the top says **drivalry**.
2. If the page shows **Get started**: App name `Drivalry`, User support email = your Gmail → **Next**. Audience **External** → **Next**. Contact email = your Gmail → **Next**. Tick the agreement → **Continue** → **Create**.
3. Left menu **Audience** → **Test users** → **+ Add users** → your Gmail and every friend who will test → **Save**. While the app is in *Testing*, only these addresses can sign in (up to 100). **Publish app** on the same page later lets anyone sign in; with only the default scopes that needs no Google review.

### 2b. Google Cloud: the Android client (your debug build's fingerprint)

1. Left menu **Clients** → **+ Create client**.
2. Application type **Android**. Name `Drivalry Android debug`. Package name `app.drivalry`.
3. **SHA-1 certificate fingerprint**: run this in PowerShell and paste the value after `SHA1:` (twenty pairs of hex separated by colons):
   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | Select-String SHA1
   ```
4. **Create**. Nothing from this client goes in `.env`; registering it is the whole job.

Every PC that builds the app has its own debug keystore, so a friend who builds on their machine adds their SHA-1 as another Android client. The release keystore gets one too, later, named `Drivalry Android release`.

### 2c. Google Cloud: the web client (the one the phone and Supabase both trust)

1. **Clients** → **+ Create client** → Application type **Web application**. Name `Drivalry Supabase`.
2. **Authorised redirect URIs** → **+ Add URI** → `https://htqyutdwnnguqatakofx.supabase.co/auth/v1/callback`.
3. **Create**. A dialog shows the **Client ID** (ends in `.apps.googleusercontent.com`) and the **Client secret**. Clicking the client in the list shows both again later.
4. Put the Client ID in `.env`:
   ```
   GOOGLE_WEB_CLIENT_ID=1234567890-abcdefg.apps.googleusercontent.com
   ```
   The client secret does **not** go in `.env`. It goes into Supabase in the next step.

### 2d. Supabase: switch on the Google provider

1. https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/auth/providers → **Google**.
2. Toggle **Enable Sign in with Google** on.
3. **Client IDs**: paste the web Client ID from 2c. (When the iOS client exists in Part 8, add it after a comma.)
4. **Client Secret (for OAuth)**: paste the web client secret from 2c.
5. Toggle **Skip nonce checks** on. iOS native sign-in needs it later; it is harmless now.
6. **Save**.

### 2e. Supabase: two small settings

1. Same page → **Email** → switch **Enable Email provider** off → **Save**. The app has no email form; this stops password sign-ups through the public API.
2. https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/auth/url-configuration → **Site URL** `https://github.com/RyanCrawfordOrr/drivalry` → **Redirect URLs** → **Add URL** → `app.drivalry://login-callback` → **Save**.

**Check it worked.** After Part 4 (rebuild), open the app → Profile → **Continue with Google** → pick an account from your test users. You land on your profile with a generated handle. https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/auth/users shows one row.

**If it fails.**

- App says *Google sign-in is not configured for this build*: `GOOGLE_WEB_CLIENT_ID` is blank, or you did not rebuild after filling it, or the Android client's package or SHA-1 does not match this PC's debug keystore (Google error code 10, `DEVELOPER_ERROR`). Redo 2b and rebuild.
- Google page says *Access blocked: Drivalry has not completed the Google verification process*: that Gmail is not in **Test users** (2a step 3).
- Supabase error *Unacceptable audience in id_token*: the Client ID saved in Supabase (2d step 3) is not the same string as `GOOGLE_WEB_CLIENT_ID` in `.env`.

---

## Part 3: Lock the Google key (10 minutes)

**Protects:** the free tier. The key ships inside the APK. Anyone who pulls it out can only call the four APIs below, only up to the daily caps, and map tiles for the mobile SDKs cost nothing.

### 3a. Make sure the four APIs are on

https://console.cloud.google.com/apis/library?project=drivalry → search each name → **Enable** if the button is not already **Manage**: **Maps SDK for Android**, **Maps SDK for iOS**, **Routes API**, **Places API (New)**.

### 3b. Restrict the key

1. https://console.cloud.google.com/apis/credentials?project=drivalry → under **API Keys** click the key the app uses (its first characters match `GOOGLE_MAPS_API_KEY` in `.env`).
2. **API restrictions** → **Restrict key** → in the dropdown tick exactly four: Maps SDK for Android, Maps SDK for iOS, Routes API, Places API (New) → **OK** → **Save**.
3. **Application restrictions**: leave **None**. A key can carry only one kind of app restriction and this one serves Android and iOS. Split into two keys later only if the console ever shows abuse.

### 3c. Cap the daily calls

1. https://console.cloud.google.com/google/maps-apis/quotas?project=drivalry → in the **Select an API** dropdown pick **Routes API**.
2. Find the row **Compute Routes requests per day** (the wording may be *Requests per day*). Click its pencil → **New limit** `300` → **Save** / **Submit request**. Lowering a quota applies at once; only raising needs review.
3. Dropdown → **Places API (New)** → **Nearby Search requests per day** → `150`. Then **Text Search requests per day** → `150`. If a method shows only a per-minute row, set that row to `10` instead.

The phone also stops itself at 40 Routes calls and 20 Places calls per device per day, so these caps are a ceiling, not normal spend. At the ceiling, ETAs become straight-line estimates and stop suggestions become typed names; nothing is ever billed.

---

## Part 4: Rebuild and install (5 minutes, after every `.env` change)

The `.env` values are compiled into the APK, so the phone only sees them after a rebuild.

```powershell
cd C:\Drivalry\app
flutter build apk --debug --dart-define-from-file=../.env
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Phone plugged in over USB with USB debugging on and the screen unlocked. The build takes two to five minutes; `Success` after `adb install` is the confirmation.

**Check everything so far.** Sign in (Part 2). Friends → **Add friend** shows your handle and a QR code. Sign in on a second phone, or with a second Google account, add each other, and a friend league appears by the next Monday. Start a convoy from the Drive tab and join it from the other phone with the code.

---

## Part 5: Push notifications (45 minutes)

**Unlocks:** a notification when someone reacts to or comments on your drive, sends or accepts a friend request, challenges you to a duel, or when a circle member's crash alert fires. Without it, all of that still shows inside the app on the next refresh.

Three pieces: Firebase (free, delivers the message to the phone), the `push` Edge Function on Supabase (decides who gets what), and five Database Webhooks (call the function when a row is written).

### 5a. Firebase project

1. https://console.firebase.google.com → **Create a project** (or **Add project**).
2. In the name box choose the existing Google Cloud project **drivalry** from the dropdown so Firebase rides on the same project → **Continue**.
3. Switch **Enable Google Analytics** off → **Add Firebase** → **Continue**.
4. Gear (top left, next to *Project Overview*) → **Project settings** → **General** tab → **Your apps** → click the **Android** icon. Package name `app.drivalry`, nickname `Drivalry Android` → **Register app** → **Next** → **Next** → **Continue to console**. Skip the `google-services.json` download; the app does not use it.
5. **Add app** → **iOS**: bundle id `app.drivalry`, nickname `Drivalry iOS` → **Register app** → skip the plist → **Continue to console**. Do this now so the iOS id is in `.env` when the Mac build happens.
6. Still on **General**, copy into `.env`:

   | On the page | `.env` line |
   | --- | --- |
   | **Web API Key** (top block) | `FIREBASE_API_KEY=` |
   | **Project ID** | `FIREBASE_PROJECT_ID=` |
   | **Project number** (same as `GOOGLE_CLOUD_PROJECT_NUMBER` already in `.env`) | `FIREBASE_SENDER_ID=` |
   | Your apps → Drivalry Android → **App ID** (`1:…:android:…`) | `FIREBASE_APP_ID_ANDROID=` |
   | Your apps → Drivalry iOS → **App ID** (`1:…:ios:…`) | `FIREBASE_APP_ID_IOS=` |

7. **Cloud Messaging** tab → **Firebase Cloud Messaging API (V1)** must say **Enabled**. If not, its ⋮ → **Manage API in Google Cloud Console** → **Enable**.
8. **Service accounts** tab → **Generate new private key** → **Generate key**. A `.json` file lands in Downloads. You paste its contents into Supabase in 5d and then delete it. It never goes in the repo.

### 5b. Install the Supabase command-line tool and log in

Only needed to deploy the function. Nothing is installed permanently: `npx` fetches the tool on demand (Node 22 is already on this PC).

```powershell
cd C:\Drivalry
npx --yes supabase@latest login
```

A browser tab opens; approve it. PowerShell prints *You are now logged in*. Then link the folder to the project:

```powershell
npx --yes supabase@latest link --project-ref htqyutdwnnguqatakofx
```

When it asks for the database password, press Enter to skip it.

### 5c. Deploy the function

```powershell
cd C:\Drivalry
npx --yes supabase@latest functions deploy push --no-verify-jwt --use-api
```

It ends with *Deployed Functions on project htqyutdwnnguqatakofx: push*. Run this same command again any time `supabase/functions/push/index.ts` changes.

### 5d. Secrets

Make the shared secret the webhooks will carry. This copies a 64-character random string to the clipboard:

```powershell
[guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') | Set-Clipboard
```

Paste it into Notepad for the moment; you need it twice (here and in 5e).

https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/functions/secrets → **Add new secret**:

| Key | Value |
| --- | --- |
| `PUSH_WEBHOOK_SECRET` | the random string |
| `FCM_SERVICE_ACCOUNT_JSON` | the entire contents of the JSON file from 5a step 8 |

For the JSON, copy the whole file in one go (adjust the filename to the one in your Downloads folder):

```powershell
Get-Content -Raw "$env:USERPROFILE\Downloads\drivalry-firebase-adminsdk-xxxxx.json" | Set-Clipboard
```

**Save**, then delete the JSON file from Downloads. The `APNS_*` secrets are iOS-only and come with Part 8.

### 5e. Webhooks

1. https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/integrations/webhooks/overview → if it shows **Enable webhooks**, click it.
2. **Create a new hook** and fill in:
   - **Name** `push_feed_reactions`
   - **Table** `feed_reactions`
   - **Events** tick **Insert**
   - **Type of webhook** **HTTP Request**
   - **Method** `POST`, **URL** `https://htqyutdwnnguqatakofx.supabase.co/functions/v1/push`
   - **HTTP Headers** → **Add a new header** → name `x-push-secret`, value = the random string. Keep the pre-filled `Content-type: application/json`.
   - Leave the timeout → **Create webhook**.
3. Repeat four more times, changing only the name, table and events:

   | Name | Table | Events |
   | --- | --- | --- |
   | `push_feed_reactions` | `feed_reactions` | Insert |
   | `push_feed_comments` | `feed_comments` | Insert |
   | `push_friendships` | `friendships` | Insert, Update |
   | `push_duels` | `duels` | Insert, Update |
   | `push_crash_alerts` | `crash_alerts` | Insert |

   Choosing type **Supabase Edge Functions** and picking `push` works just as well; the `x-push-secret` header is the only thing the function checks.

### 5f. Check it worked

Rebuild and install (Part 4). On the phone, Settings → **Notifications** shows **registered**, meaning a device token is stored. Then send yourself a friend request from the second account; the notification arrives within seconds.

Direct test without a second phone. Replace the secret, and both ids with your own user id (https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/auth/users → the UUID column):

```powershell
curl.exe -X POST https://htqyutdwnnguqatakofx.supabase.co/functions/v1/push -H "x-push-secret: PASTE_SECRET" -H "content-type: application/json" -d "{\"type\":\"INSERT\",\"table\":\"friendships\",\"schema\":\"public\",\"record\":{\"requester_id\":\"YOUR_UUID\",\"addressee_id\":\"YOUR_UUID\",\"status\":\"pending\"},\"old_record\":null}"
```

Expect `{"sent":1,"dead":0,"recipients":1}`. Logs: Dashboard → **Edge Functions** → **push** → **Logs**.

**If it fails.**

- `401` from the test: the header value is not the same as `PUSH_WEBHOOK_SECRET`.
- `"recipients":0` or no **registered** on the phone: the `FIREBASE_*` lines are blank, you did not rebuild, or notifications are denied for Drivalry in Android settings.
- Deploy complains that Docker is required: the `--use-api` flag is missing from the command.
- Webhook exists but nothing arrives: open the hook and check it is enabled, then read the function logs to see whether it was called at all.

---

## Part 6: Optional convoy keys

Each one switches on one convoy feature. The app says plainly what is missing when they are blank.

### 6a. Metered TURN (convoy radio when a direct connection fails)

Without it: the radio works whenever the two phones can reach each other directly (same Wi-Fi and most mobile pairs). When they cannot, the app shows *direct connection failed*.

1. https://dashboard.metered.ca/signup?tool=turnserver → free account. The app name you choose becomes your domain, `<name>.metered.live`.
2. Dashboard → **TURN Server** → **Credentials** → **Create Credential** → **Create credential**.
3. On the new row click **Get credential**. It shows the URL the phone will call, in the form `https://<name>.metered.live/api/v1/turn/credentials?apiKey=XXXX`.
4. `.env`: `METERED_DOMAIN=<name>.metered.live` and `METERED_API_KEY=XXXX` (the part after `apiKey=`). Not the account **Secret key** under *Developers*; that one must never be on a phone.
5. Rebuild (Part 4). Relayed bytes per convoy show on the Diagnostics screen. Free allowance 20 GB a month, about 14 MB per relayed stream-hour.

### 6b. Spotify (Convoy DJ)

Without it: the Music screen shows the Spotify Jam and Apple Music SharePlay links only. Everyone who uses DJ needs Spotify Premium anyway.

Spotify changed the rules in February 2026: the developer's own account must be Premium, each developer gets one Development Mode app, and at most **five** test users can be allowlisted. So DJ is for your closest car or two, not the whole league.

1. https://developer.spotify.com/dashboard → log in with a Premium account → **Create app**. App name `Drivalry`, description `Convoy DJ for a driving app`, **Redirect URIs** → `drivalry-auth://spotify-callback` → **Add**. Under *Which API/SDKs are you planning to use?* tick **Web API** → agree → **Save**.
2. **Settings** → copy **Client ID** → `.env` line `SPOTIFY_CLIENT_ID=`. There is no secret; the app uses PKCE.
3. **User Management** tab → add each friend's name and the email of their Spotify account → **Add user**. Five at most.
4. Rebuild (Part 4). Convoy → **Music** → **Connect Spotify** opens the browser once; the tokens stay in the phone's secure storage.

---

## Part 7: Android Auto on the desktop head unit (30 minutes)

**Unlocks:** seeing the car screens without a car.

1. Android Studio → **More Actions** (or **Tools**) → **SDK Manager** → **SDK Tools** tab → tick **Android Auto Desktop Head Unit Emulator** → **Apply**. It lands in `%LOCALAPPDATA%\Android\Sdk\extras\google\auto\`.
2. On the phone: update **Android Auto** from Play. Settings → **Connected devices** → **Connection preferences** → **Android Auto**. Scroll to **Version** and tap it ten times → confirm **Developer settings**. Then ⋮ (top right) → **Developer settings** → turn on **Unknown sources**. Back, ⋮ → **Start head unit server** (a notification appears). Under **Previously connected cars**, make sure **Add new cars to Android Auto** is on.
3. Plug the phone in over USB, screen unlocked. In PowerShell:
   ```powershell
   adb forward tcp:5277 tcp:5277
   & "$env:LOCALAPPDATA\Android\Sdk\extras\google\auto\desktop-head-unit.exe"
   ```
4. Accept the terms on the phone the first time. In the DHU window open the app grid and tap **Drivalry**. In the DHU console type `restrict all` to simulate driving, `night` for dark mode, `screenshot name.png` to save a picture.
5. With a trip running (Drive → Diagnostics → simulator, or a real drive) the numbers move. With an active convoy on two phones the Convoy and Stops tabs fill. Swipe the phone app away from Recents: the DHU should say *phone app asleep*, and a Passenger or End trip tap must still be acknowledged.

Logs: `adb logcat -s Drivalry.Car Drivalry.Service CarApp`. The Play Console declaration, needed before any Play release, is `docs/04-car-platforms.md` §3.5.

---

## Part 8: On the Mac (iOS), later

All the iOS code is written and has never been compiled. `app/ios/README-mac.md` is the full walkthrough; this is the order and the account work that goes with it.

1. README §1 to §3: Xcode, Flutter 3.44.6, CocoaPods, clone the repo, copy `.env` over by AirDrop or a password manager (never by committing it), `pod install`.
2. README §4 steps 1 to 7 in Xcode: team, Background Modes, Push Notifications, Sign in with Apple, URL scheme check, iOS 16.0, the Tracking group.
3. README §4 step 8: create the `DrivalryWidgets` extension target for the Live Activity. The two Swift files are already in the repo.
4. README §5: build to an iPhone. Expect a few Swift compile errors the first time; fix them in Xcode and copy the fixes back to Windows.
5. Account work, all at https://developer.apple.com/account unless stated:
   - **Identifiers** → `app.drivalry` → tick **Sign in with Apple** and **Push Notifications** → **Save**. If the identifier does not exist yet: **+** → App IDs → App → explicit bundle id `app.drivalry`.
   - Supabase → https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/auth/providers → **Apple** → enable → **Client IDs** `app.drivalry` → **Save**. Leave the secret empty; the app never uses the web flow.
   - **Keys** → **+** → name `Drivalry push`, tick **Apple Push Notifications service (APNs)** → **Register** → **Download** the `.p8` (only offered once). Note the **Key ID** and your **Team ID** (top right of the account page).
   - Firebase → Project settings → **Cloud Messaging** → *Apple app configuration* → **Upload** the `.p8` with that Key ID and Team ID. Without it iPhones register tokens but never receive anything.
   - Google Cloud → https://console.cloud.google.com/auth/clients?project=drivalry → **+ Create client** → **iOS**, name `Drivalry iOS`, bundle id `app.drivalry` → **Create** → copy the Client ID into `.env` as `GOOGLE_IOS_CLIENT_ID=`, and add it after a comma in the Supabase Google provider's **Client IDs** (Part 2d).
   - Request the **CarPlay Driving Task** entitlement: Account → **Additional resources** → **CarPlay** → describe the app (driving score, convoy map, push-to-talk). Approval takes weeks. The in-app tree is ready; `docs/04-car-platforms.md` §2 lists the five Xcode steps for when it is granted.
6. README §6 and `docs/06-roadmap.md` M1.6: TestFlight when the seven test phones are ready. Set the Edge Function secret `APNS_SANDBOX=false` at that point.

---

## Part 9: Nothing to do

- Speed-limit packs rebuild monthly on GitHub Actions and the app reads the `packs-index` release. The first release, `packs-2026.11` with 52 packs, is live.
- The Supabase keep-alive runs daily with the two repo secrets already set, so the free project never pauses.
- CI runs on every push: five jobs.

## Part 10: Before the first build goes to anyone outside your car

- Check every free allowance in `docs/03-architecture.md` §10 against the providers' current pricing pages; they change.
- Read `docs/05-privacy-safety-legal.md` and publish the privacy-policy page it describes; the store listings link to it.
- Publish the Google consent screen (Part 2a) so testers no longer have to be listed by hand.

---

## Troubleshooting, all in one place

| You see | Cause | Fix |
| --- | --- | --- |
| Signed-in screens show errors or spin forever | Migrations not applied | Part 1 |
| *Google sign-in is not configured for this build* | Blank `GOOGLE_WEB_CLIENT_ID`, no rebuild, or SHA-1 mismatch | Parts 2b, 2c, 4 |
| *Access blocked: … has not completed the Google verification process* | Account not in Test users | Part 2a step 3 |
| *Unacceptable audience in id_token* | Supabase Client IDs differs from `.env` | Part 2d step 3 |
| *waking up* banner in the app | Supabase project paused | Dashboard → **Restore project**; the keep-alive prevents this |
| Settings → Notifications never says *registered* | `FIREBASE_*` blank or no rebuild, or notifications denied | Parts 5a, 4 |
| Push test returns `401` | Header differs from `PUSH_WEBHOOK_SECRET` | Part 5d |
| `supabase functions deploy` wants Docker | `--use-api` missing | Part 5c |
| Radio: *direct connection failed* | No TURN relay configured | Part 6a, optional |
| *Ask Ryan to add your Spotify account to the Drivalry allowlist* | Friend not in Spotify User Management | Part 6b step 3 |
| DHU shows no Drivalry icon | Unknown sources off, or old APK | Part 7 step 2, then Part 4 |
| Routes or Places quota exceeded in the Cloud console | Daily cap reached | Expected; ETAs and stop suggestions degrade, nothing is billed |
