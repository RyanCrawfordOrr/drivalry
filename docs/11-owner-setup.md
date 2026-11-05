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
| Supabase | Project `htqyutdwnnguqatakofx`. `0000` to `0007` are applied (checked 2026-11-05). `0008_blocks_reports.sql` (report and block) is not yet; Part 1 step 5. |
| GitHub | Both repo secrets set. CI and the daily keep-alive already run. |

Parts 1 to 4 make the Android phone work end to end: sign in, friends, leagues, convoys, radio. Part 5 adds push notifications. Parts 6 to 8 are optional or for later.

---

## Part 1: Create the database tables (15 minutes)

**Unlocks:** everything that touches the cloud. Until this is done every signed-in screen fails.

You paste eight SQL files into the Supabase SQL editor, one at a time, in order. If the check at the end already shows `true` for a file, skip that file: every migration is safe to run twice, but there is no need.

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
   Get-Content -Raw C:\Drivalry\supabase\migrations\0008_blocks_reports.sql | Set-Clipboard
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
  (to_regclass('public.duels') is not null)                                           as "0007 applied",
  (to_regclass('public.user_blocks') is not null
     and to_regclass('public.content_reports') is not null)                           as "0008 applied";
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
   | **Project number** of the Firebase project (Project settings → Cloud Messaging → **Sender ID**). Only the same as `GOOGLE_CLOUD_PROJECT_NUMBER` if you attached Firebase to the existing `drivalry` project; a fresh Firebase project has its own number | `FIREBASE_SENDER_ID=` |
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
   | `push_content_reports` | `content_reports` | Insert (Part 17; needs migration 0008 first) |

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
6. README §6: `tools/release/build_ios.sh` builds the `.ipa` (version from `pubspec.yaml`, build number = commit count); upload it with Transporter, then attach it on the version page (README §6 step 4). The App Store Connect record (app 6830844356) was filled in on 2026-11-04: store text, screenshots, categories, privacy answers, price (free) and availability (174 regions, France excluded). Three things are still yours: App Privacy → **Publish**; the version page's App Review **Contact Information** (name, phone, email); and commit and push `docs/privacy-policy.md` so the privacy URL on the record resolves. Check: the version page's **Add for Review** button turns blue.
7. `docs/06-roadmap.md` M1.6: TestFlight when the seven test phones are ready. Set the Edge Function secret `APNS_SANDBOX=false` at that point.

---

## Part 9: Nothing to do

- Speed-limit packs rebuild monthly on GitHub Actions and the app reads the `packs-index` release. The first release, `packs-2026.11` with 52 packs, is live.
- The Supabase keep-alive runs daily with the two repo secrets already set, so the free project never pauses.
- CI runs on every push: five jobs.

## Part 10: Before the first build goes to anyone outside your car

- Check every free allowance in `docs/03-architecture.md` §10 against the providers' current pricing pages; they change.
- Read `docs/05-privacy-safety-legal.md` and publish the privacy-policy page it describes; the store listings link to it.
- Publish the Google consent screen (Part 2a) so testers no longer have to be listed by hand.

## Part 11: Store listings (when you open the Play Console and App Store Connect)

Every graphic is already rendered and every text field already written:

- `store/README.md` says which file goes in which upload box, with sizes.
- `store/listing.md` has the app name, short and long descriptions, keywords, categories and the answers to the content and data-safety questionnaires.
- The launcher icons, splash and status-bar icon inside the app are regenerated from the same source (`DRIVALRY_ART=1 flutter test test/art` in `app/`), so you never edit a PNG by hand.

Two things only you can supply: Android Auto screenshots from the Desktop Head Unit (Part 7), and the iPad decision noted in `store/README.md`.

---

## Part 12: The convoy radio (push-to-talk), step by step

**What it is.** Phones in the same convoy talk to each other directly over the internet (WebRTC), like a walkie-talkie. Hold the big button, speak, let go. Sound comes out wherever your music does (car Bluetooth, speaker, earbuds); the phone's microphone picks you up. Nothing is recorded or stored.

**What it needs, in order.**

| Need | Done by | Where |
| --- | --- | --- |
| Database tables | you, once | Part 1 |
| Sign-in on every phone | you, once | Parts 2 and 4 |
| Two phones, two accounts | you | any two Google accounts in your Test users list |
| A convoy that is *On the road* | the leader, each trip | in the app, below |
| Microphone permission | each phone, first time | the phone asks when you first tap Talk |
| Relay for different mobile networks | you, once, optional | Part 6a (Metered) |

### 12a. Before the first test (owner, 10 minutes)

1. Parts 1, 2 and 4 done, and both phones signed in with different accounts.
2. Decide on the relay. Without Metered, two phones talk when a direct path exists: the same Wi-Fi almost always, two phones on the same carrier usually, different carriers often not. With Metered (free, Part 6a) the relay steps in whenever direct fails. Do Part 6a now if your test phones are on different networks, then rebuild and reinstall (Part 4).
3. Make the two accounts friends: on phone A, Friends → **Add friend** → show the QR; on phone B scan it (or paste the link). Friendship is not strictly required for a convoy, but it is for the map and the feed, so do it now.

### 12b. Start a convoy (phone A, the leader)

1. **Convoy** tab → the **Start a convoy** icon (top right). Name it (e.g. `Test run`), pick a destination a few miles away, then **Create convoy**.
2. The convoy opens. Tap the **invite** icon (top right) → the sheet shows a six-character **code** and a **Share link**. Read the code out or send the link.
3. On phone B: **Convoy** tab → the **Join with a code** icon (top right) → type the code → **Join**. (Or tap the shared link; it opens straight into the join screen.) Phone B now sees the same convoy.
4. Back on phone A, tap **Start trip**. The status pill changes to **On the road** and the big **Talk** button appears. The radio only works while the convoy is On the road; **End trip** (in the ⋮ menu) switches it off for everyone.

### 12c. Talk

1. On both phones open the convoy and tap the big **Talk** button. The radio starts on its own; the screen says *Starting…* for a moment.
2. The phone asks for the **microphone**. Allow it. If you refused once, the screen says *Microphone needed* with an **Open settings** button; allow it there and come back.
3. Within a few seconds each phone's **Cars** list shows the other phone as **Connected**. Hold the big button, say something, let go. On the other phone the banner reads *Someone is talking* and the sound plays.
4. **Mute everyone** silences incoming audio but still lets you transmit. The radio keeps running with the screen off and while you switch apps; the notification's **Stop** ends it.

### 12d. Check it worked

- Both phones show each other under **Cars** as **Connected** within ten seconds.
- Audio arrives with well under a second of delay.
- If the phones were on different networks, Settings → About → **Diagnostics** → *Radio: relayed data* is above zero on at least one phone after a chat. That proves the Metered relay carried it.

### 12e. If it fails

| You see | Cause | Fix |
| --- | --- | --- |
| *Join a convoy to talk* | No convoy, or you are not a member | Join with the code first |
| No Talk button, *Waiting for … to start.* | Convoy is still *Planning* | Leader taps **Start trip** |
| *Microphone needed* | Permission refused | Allow in the phone's app settings |
| Other car stuck on **Connecting…** for more than 20 seconds | No direct path and no relay | Do Part 6a (Metered), rebuild, reinstall; or put both phones on one Wi-Fi to confirm everything else works |
| Connected, but silence | Phone media volume at zero, or a Bluetooth headset holding the audio | Turn media volume up; disconnect the headset to test on the speaker |
| Radio stops when the screen locks | Battery optimisation killed the service (some Android skins) | Phone Settings → Apps → Drivalry → Battery → **Unrestricted** |
| *Works across networks.* missing at the bottom of the radio screen after Part 6a | `.env` edited but not rebuilt, or the domain is not `<name>.metered.live` | Check the two lines, rebuild (Part 4) |

Convoy DJ (same song in every car) is separate: Part 14.

## Part 14: Convoy DJ (Spotify), step by step

**What it is.** One person in the convoy is the DJ. They search Spotify, build a queue, and every car's own Spotify plays the same track at the same moment (the phones measure their clock offsets and start together, about a third of a second apart at worst). Each phone plays through its own Spotify account; nothing streams between phones.

**What it needs.**

| Need | Done by | Where |
| --- | --- | --- |
| A Spotify developer app and its Client ID | you, once | 14a |
| Each rider's Spotify email on the app's allowlist | you, per friend | 14a step 6 |
| `SPOTIFY_CLIENT_ID` in `.env` and a rebuild | you, once | 14b |
| Spotify Premium | every phone that joins DJ | Spotify's rule: free accounts cannot be controlled |
| The Spotify app installed and signed in | every phone | 14c |
| A convoy open on the phones | the group | Part 12b |

Spotify's rules since February 2026: the developer account (yours) must be Premium, you get one app in Development Mode, and at most **five** people can be on its allowlist. So DJ is for your closest car or two. Spotify Jam and Apple Music SharePlay (the buttons at the top of the Music screen) need none of this; they just open those apps.

### 14a. Create the Spotify app (owner, 10 minutes)

1. https://developer.spotify.com/dashboard → **Log in** with your Spotify account (it must be Premium). Accept the developer terms the first time.
2. **Create app**.
   - **App name** `Drivalry`
   - **App description** `Convoy DJ for a driving app`
   - **Website** leave blank or `https://github.com/RyanCrawfordOrr/drivalry`
   - **Redirect URIs** type exactly `drivalry-auth://spotify-callback` and press **Add**. The scheme is deliberately not `drivalry://` so it never collides with invite links.
   - **Which API/SDKs are you planning to use?** tick **Web API** only.
   - Tick the terms → **Save**.
3. The app page opens. Click **Settings** (top right). Under **Basic Information** copy the **Client ID** (32 characters). There is no secret to copy: the phone uses PKCE.
4. Still in Settings, check the Redirect URI list shows `drivalry-auth://spotify-callback`. If you mistyped it, sign-in will fail with "Invalid redirect URI".
5. **User Management** (tab at the top of the app page) → **Add new user** → the person's **full name** and the **email of their Spotify account** (the one they log in to Spotify with; a Facebook-linked account still has an email under Spotify → Account) → **Add user**. Add yourself first, then each friend, five at most.
6. Each friend must also have **Spotify Premium** (individual, Duo, Family or Student all count).

### 14b. Put the Client ID in the app (owner, 5 minutes)

1. `notepad C:\Drivalry\.env` → set the line
   ```
   SPOTIFY_CLIENT_ID=paste-the-32-character-id-here
   ```
   No spaces, no quotes. Save.
2. Rebuild and reinstall (Part 4). Until this rebuild the Music screen says Convoy DJ is not available in this version.

### 14c. On each phone (2 minutes each)

1. Install **Spotify** from the store and sign in with the Premium account that is on the allowlist.
2. Open Spotify once and play anything for a second, then pause. That makes this phone Spotify's "active device"; the Web API can only control an active device.
3. Open Drivalry → **Convoy** → the convoy → **Music** → **Convoy DJ** → **Connect Spotify**. The system browser opens Spotify's login; approve the three playback permissions. It returns to Drivalry on its own and the row now reads *Connected as <name>* with a **Disconnect** button. Tokens live in the phone's secure storage; this is a one-time step.

### 14d. Drive the deck

1. The person who wants to pick music taps **Be the DJ**. Everyone else sees who the DJ is.
2. The DJ types in **Search tracks**, taps a result to add it to **Up next**, and taps the first track to start it. Each connected phone starts the same track within a fraction of a second, through its own Spotify.
3. Anyone can **vote to skip**; a majority skips. The DJ can **Step down**; the next person taps Be the DJ.
4. If a phone falls out of sync it corrects itself at the next 30-second check.

### 14e. Check it worked

- Two phones in the same convoy both show *Connected as …* and the DJ's track title appears on both Music screens.
- Pressing play on the DJ phone makes both phones' Spotify apps show the same track within a second.

### 14f. If it fails

| You see | Cause | Fix |
| --- | --- | --- |
| *Convoy DJ isn't available in this version* | `SPOTIFY_CLIENT_ID` blank or not rebuilt | 14b, then Part 4 |
| Browser says *Invalid redirect URI* | The URI in the Spotify app settings is not exactly `drivalry-auth://spotify-callback` | 14a step 4 |
| Browser says *Invalid client* | Client ID mistyped in `.env` | 14b |
| *Ask Ryan to add your Spotify account to the Drivalry allowlist* | That email is not under User Management, or it is a different email than the one they log in with | 14a step 5 |
| *Convoy DJ needs Spotify Premium on this account* | Free account | Spotify Premium on that phone |
| Connected, but nothing plays on one phone | Spotify is not the active device on that phone | 14c step 2: open Spotify, play and pause once, retry |
| The browser never returns to Drivalry | Another app grabbed the `drivalry-auth` link | Close the browser tab and tap Connect again; on Android pick Drivalry if asked which app should open the link |
| Tracks start a second apart | Clock offsets not measured yet | Wait for the next 30-second ping, or re-open the Music screen |

## Part 13: Things to switch on inside the app (every phone)

Everything else that needs a person. Order is the order a new phone meets them.

| What | Where | Why |
| --- | --- | --- |
| Location **Allow all the time**, precise on | First-run screens, or Drive → **Turn on auto-detect** | Trips start on their own only with "all the time" |
| **Physical activity** (motion) | Same flow | Tells driving from walking without draining the battery |
| **Notifications** | Settings → Friends → Notifications → **Enable** | Trip scored, reactions, friend requests, crash alerts |
| **Speed-limit pack for your state** | Settings → Drives → Speed-limit packs → **Install for my location** | Limits come from the pack; it downloads on Wi-Fi only |
| **Units** | Settings → Drives → Units | mph or km/h everywhere |
| **Your handle and name** | Profile (your avatar, top right of the Drive screen) → tap the handle or the name | What friends see |
| **Add your car** | Garage → **Add vehicle**, or say yes when the app notices new car audio | Trips get credited to the right car; the car's Bluetooth marks you as the driver |
| **Home and Work** | Friends → Circles → **Places** → **Add where I am** | Arrive and leave alerts for your circle; better trip names |
| **Friends** | Friends → **Add friend** → QR, handle or link | Leagues, feed, map |
| **A circle** | Friends → Circles → **New circle** → invite | Live location with the people you choose |
| **Emergency contacts** | Settings → Safety → Crash detection → **Emergency contacts** | Who gets the prefilled text after a crash countdown |
| **Test the crash countdown** | Settings → Safety → Crash detection → **Test the countdown** | See the 30-second screen once, before you need it |
| **Spoken cues** (optional) | Settings → Drives → Spoken cues | Off by default; says the limit and "over by" |
| **Auto-reply while driving** (optional) | Settings → Safety → **Auto-reply to texts** → follow the numbered steps | Uses the phone's own driving mode |
| **Live Activities** (iPhone) | iPhone Settings → Drivalry → Live Activities on | Lock-screen limit and convoy |
| **Android Auto** | Plug in; the Drivalry icon appears in the car launcher | Part 7 to test on the desktop head unit first |

## Part 15: Build for Google Play internal testing (the device-testing pipeline)

**What it is.** From here on, testing on a phone goes through Google Play: one command builds a signed App Bundle, you upload it to the Internal testing track, and every tester's phone gets it from the Play Store like any other update. No cables, no debug APKs, and the build is the same one that will ship.

**What it needs, in order.**

| Need | Done by | Where |
| --- | --- | --- |
| The upload key | done, back it up | 15a |
| The Play Console app (one-time, about 30 minutes of forms) | you | 15b |
| The build command | you, each release | 15c |
| Upload and roll out | you, each release | 15d |
| Two certificate fingerprints in Google Cloud | you, once, after the first upload | 15e |

### 15a. The upload key (already created; back it up now)

Two files exist outside git and must never be committed or shared:

| File | What it is |
| --- | --- |
| `C:\Drivalry\.secrets\upload-keystore.jks` | The upload key. Google verifies every bundle you send against it. |
| `C:\Drivalry\app\android\key.properties` | Its password and alias. The release build reads it. |

1. Copy both files somewhere safe that is not this PC: a password manager's file attachment, or an encrypted drive. If the PC dies and these are gone, Play can still let you back in (Play App Signing keeps the real app key and lets you register a new upload key through support), but it takes days.
2. Check: in Explorer, `C:\Drivalry\.secrets` shows `upload-keystore.jks`, and `git status` in `C:\Drivalry` never lists it.

Its public fingerprints (safe to paste anywhere Google asks for a SHA-1 or SHA-256 of the *upload* certificate):

```
SHA1:   C3:15:76:1C:53:C2:48:1D:10:54:24:40:B9:78:7B:8B:26:36:2D:8F
SHA256: BB:34:A0:88:2D:E9:C0:40:F2:E1:2C:D0:2F:6C:AF:1B:B6:C4:1A:35:0D:89:74:E3:FE:10:1E:52:91:7D:7D:4A
```

### 15b. Create the app in Play Console (once)

1. https://play.google.com/console → sign in with your Google account → if asked, pay the one-time developer registration fee and finish identity verification (this can take a day or two; everything below waits on it).
2. **Create app**. App name `Drivalry`, default language English (United States), **App**, **Free**. Tick the two declarations → **Create app**.
3. The dashboard opens with a **Set up your app** checklist. Work down it; each item is a short form. Answers that fit Drivalry: Privacy policy = the URL from `docs/05-privacy-safety-legal.md` once published (a GitHub Pages page of that file is fine); App access = all functionality available without special access (sign-in is optional); Ads = no; Content rating = fill the questionnaire, answer honestly (no violence, no gambling, user interaction yes, shares location yes); Target audience = 18 and over; News app = no; COVID = no; Data safety = location (collected, shared with friends you choose, not sold), name and email (account), see `store/listing.md` for the wording; Government app = no; Financial features = none; Health = none.
4. **Store listing** (left menu → Grow → Store presence → Main store listing): paste the texts from `store/listing.md`, upload `store/play/icon-512.png`, `store/play/feature-graphic-1024x500.png` and the eight `store/play/phone/*.png`. Save. Internal testing does not need the listing to be approved, but it does need it saved.
5. **Testers**: left menu → Testing → **Internal testing** → **Testers** tab → **Create email list** → name `Drivers`, add the Gmail address of every phone that should get builds (yours first) → **Save changes**. Tick the list. Keep this page open; you will copy the opt-in link in 15d.

Check: Testing → Internal testing shows your list under Testers and "No releases yet".

### 15c. Build the bundle (every release)

1. Commit your work first. The version code is the number of commits on the branch, so an uncommitted build reuses the previous number and Play will refuse it.
2. In a PowerShell window:
   ```powershell
   cd C:\Drivalry
   .\tools\release\build_android.ps1
   ```
   About three minutes. The last line reads `Done: …\app-release.aab (NN MB), version 1.0.0 (CODE)`.
3. Check: `C:\Drivalry\app\build\app\outputs\bundle\release\app-release.aab` exists and the printed CODE is higher than the last one you uploaded.

For a release build you can install by cable instead (same signing, same code), add `-Apk` and run the `adb install` line it prints. That is only for a phone that is not on the tester list.

### 15d. Upload and roll out (every release)

1. Play Console → Testing → **Internal testing** → **Create new release**.
2. The first time, under **App integrity** choose **Use Google-generated key** (Play App Signing) → **Continue**. Google now holds the real signing key; your file from 15a is only the upload key.
3. **App bundles** → **Upload** → pick `app-release.aab` from 15c. Wait for the green tick. Release name fills itself (`CODE (1.0.0)`). Release notes: one line of what changed.
4. **Next** → fix anything red (warnings in yellow are fine for internal testing) → **Save** → **Go to overview** → **Start rollout to Internal testing** → **Rollout**.
5. First time only: **Testers** tab → under "How testers join your test" → **Copy link**. Send it to each tester. On the phone, open the link in a browser signed in with the tester's Gmail → **Accept invite** → **Download it on Google Play** → **Install**.
6. Later releases: repeat 1, 3 and 4. Phones pick the update up within a few minutes; opening the Play Store page for Drivalry and tapping **Update** forces it.

Check: Internal testing → Releases shows the new CODE as "Available to internal testers", and the phone's Play Store page offers Install or Update.

### 15e. Two fingerprints Google needs after the first upload (once)

Phones get APKs signed by Google's app signing key, not by your upload key, so the Maps key lock (Part 3) and the Android sign-in client (Part 2) must both know that certificate, or the Play build shows a blank map and Google sign-in fails with "error 10".

1. Play Console → left menu → Test and release → **Setup** → **App signing** (it may be called App integrity → App signing). Under **App signing key certificate** copy the **SHA-1** and **SHA-256**.
2. Google Cloud Console → APIs & Services → **Credentials** → the Android key from Part 3 → under Android restrictions **Add an item** → package `app.drivalry`, the SHA-1 from step 1 → **Save**. Add a second item with the upload SHA-1 from 15a so `-Apk` builds work too.
3. Same page → **Create credentials** → **OAuth client ID** → Android → name `Drivalry Play`, package `app.drivalry`, the SHA-1 from step 1 → **Create**. Repeat once more with the upload SHA-1 from 15a, named `Drivalry upload key`. No change to `.env`; the Android client is matched by certificate.
4. Check: install the internal-testing build, the map shows tiles, and Settings → Sign in with Google completes.

### 15f. If it fails

| You see | Cause | Fix |
| --- | --- | --- |
| `Version code N has already been used` | No new commit since the last build | Commit, rebuild |
| `…signed in debug mode` or `…upload key does not match` | `key.properties` missing or pointing at a different keystore | 15a; restore the two files from your backup |
| Blank map in the Play build, map fine in debug | Maps key lock lacks the app signing SHA-1 | 15e step 2 |
| Google sign-in "error 10" / "DEVELOPER_ERROR" | No Android OAuth client for the app signing SHA-1 | 15e step 3 |
| Testers see "the item you requested is not found" | They opened the link with a Gmail that is not on the list, or the rollout has not finished | Add the Gmail in 15b step 5; wait ten minutes |
| The build stops at `flutter build appbundle failed` | Read the lines above it; a Kotlin or Gradle error names the file | Fix, or run `flutter build appbundle --release --dart-define-from-file=../.env` by hand inside `app` to see the whole log |

Two things release builds do differently from the debug APKs you used until now: the **Simulate a drive** and **Diagnostics** developer entries on the Drive tab are hidden (Diagnostics stays under Settings → About), and the code is shrunk, so a crash report from a tester names fewer internal details.

### 15g. Move from internal testing to closed testing (30 minutes, then wait for review)

**Why.** A personal developer account made after 13 November 2023 cannot publish to production until a **closed** test has run with at least 12 testers opted in, without a break, for 14 days. Internal testing does not count. Closed testing also goes through Google's app review (hours to a few days the first time), which internal testing skips.

1. **Finish app setup.** https://play.google.com/console → Drivalry → **Dashboard** → the **Set up your app** list. Every task with an open circle has to be done before a closed-testing release rolls out: privacy policy URL (`https://github.com/RyanCrawfordOrr/drivalry/blob/main/docs/privacy-policy.md`), app access (all features available without special access), ads (no), content rating (the questionnaire), target audience (18 and over), news app (no), data safety, government apps (no), financial features (none), health (none), and the **Main store listing** (name, descriptions and graphics from `store/listing.md` and `store/play`). Check: every task shows a green tick.
2. **Open the track.** Left column → **Testing** → **Closed testing**. There is one track already (Google names it *Alpha*); click **Manage track**. If you prefer your own name, **Create track** at the top right → name `Friends` → **Create track**.
3. **Testers.** The **Testers** tab → under *Testers* click **Create email list** → list name `Drivalry testers` → paste the Gmail addresses, comma-separated (12 or more if this test is to unlock production) → **Save changes** → **Create** → tick the list → *Feedback URL or email address*: your email → **Save changes**.
4. **Countries.** Same tab, *Countries/regions* → **Add countries/regions** → tick **United States** (or **Select all**) → **Add countries/regions** → **Save changes**. The choice applies to every track.
5. **Release.** The **Releases** tab → **Create new release**. Under *App bundles* click **Add from library** and pick `1.0.0 (68)`, the bundle already on internal testing (or **Upload** a fresh `app-release.aab` from 15c). Release name stays as filled in. *Release notes*: `First closed test.` → **Next** → **Save** → **Review release** → **Start rollout to Closed testing** → **Rollout**. Shortcut that skips the upload: **Testing → Internal testing → Releases** → the 68 release → **Promote release** → **Closed testing**.
6. **Wait for review.** The release shows *In review*, then *Available on Google Play*. Nothing to do meanwhile.
7. **Invite.** Back on the **Testers** tab → *How testers join your test* → **Copy link** → send it to the testers. Each opens it on their phone, taps **Become a tester**, then installs Drivalry from the Play Store link on the same page. The link only works once the review is done, and can take a few hours to go live after that.

**Check it worked.** Closed testing → *Track summary* shows the release *Active* and the tester count rising as people opt in. Fourteen days after the twelfth tester opted in, **Dashboard → Apply for production** turns on; the form asks about the test and the app, and Google answers within about seven days.

**If it fails.**

- A tester's link says *not available* or *item not found*: their Gmail is not on the list (step 3), or they are still opted in to **internal** testing. Someone on internal testing cannot join a closed test until they open the internal opt-in link and tap **Leave the program**. That includes your own phone.
- **Start rollout** is grey: a *Set up your app* task is still open (step 1), or no countries are selected (step 4).
- *Rejected* after review: open the message under **Policy status** in the left column; fix what it names, build again (15c), and roll out again.
- The tester count drops below 12 before 14 days: the clock restarts for the next person who joins; it is 12 people opted in at the same time for 14 consecutive days.

## Part 16: Answer App Review's "Information Needed" message

Every step is in one file, start to finish, with each command and click written out: `store/app-review.md`. Open it and work down from Step 1. Nothing in it sends you back here.

---

## Part 17: Content reports, what to do when one arrives (10 minutes once, then as they come)

**What it is.** Anyone can report a post or a comment (long-press → Report) and block a person. The reporter stops seeing the content at once; the report lands in the `content_reports` table for you to read. The notes given to Apple promise that a person looks within 24 hours. This part sends you a push notification for every report, then says what to do with one.

### 17a. Get a push for every report (once)

Skip this if the `push` Edge Function was never deployed (no push notifications yet); the table still fills up and you can read it by hand.

1. Your user id: https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/auth/users → the **UID** column of your own row → copy it.
2. In PowerShell (the tool is not installed on the PC; `npx` fetches it each time, the same way the function was deployed in 5c):
   ```powershell
   cd C:\Drivalry
   npx --yes supabase@latest secrets set MODERATOR_USER_ID=PASTE_YOUR_UID --project-ref htqyutdwnnguqatakofx
   npx --yes supabase@latest functions deploy push --no-verify-jwt --use-api --project-ref htqyutdwnnguqatakofx
   ```
   The first ends with *Finished supabase secrets set*, the second with *Deployed Functions on project htqyutdwnnguqatakofx: push*. Keep `--no-verify-jwt`: without it every webhook call is refused and all pushes stop.
3. https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/integrations/webhooks/overview → open the existing `push_feed_reactions` hook and copy the value of its `x-push-secret` header → **Create a new hook**: name `push_content_reports`, table `content_reports`, events **Insert**, type **HTTP Request**, method `POST`, URL `https://htqyutdwnnguqatakofx.supabase.co/functions/v1/push`, add the header `x-push-secret` with the copied value → **Create webhook**.

**Check it worked.** From any second account, long-press one of your posts → **Report** → any reason. Your phone shows *Content report* within seconds.

**If it fails.** No push: the secret was set but the function was not redeployed (run the deploy line again), or the hook's header value differs from the one on `push_feed_reactions`.

### 17b. Handle a report (each time)

1. https://supabase.com/dashboard/project/htqyutdwnnguqatakofx/editor → **content_reports** (left column) → sort by `created_at`, newest first. The `snapshot` column holds the reported text, so you can judge it even after the content is gone.
2. Look at the content: `post_id` → open **feed_posts** and filter `id` = that value; `comment_id` → **feed_comments**. `reported_user_id` is the author; **profiles** shows their handle.
3. Decide:
   - **Fine, leave it**: set `status` to `reviewed`.
   - **Take it down**: in **feed_posts** or **feed_comments** select the row → **Delete** (a post takes its reactions and comments with it). Set `status` to `actioned`.
   - **Repeat offender**: **Authentication → Users** → the account → **Delete user**. Everything of theirs cascades away. Set `status` to `actioned`.
4. Nobody is told who reported; nothing else to do.

**Check it worked.** The reporter never sees the content again (it was hidden for them when they reported); everyone else stops seeing it on their next refresh.

---

## Troubleshooting, all in one place

| You see | Cause | Fix |
| --- | --- | --- |
| Signed-in screens show errors or spin forever | Migrations not applied | Part 1 |
| App Review message *Information Needed* (Guideline 2.1) | Apple wants a video, notes and a new build | `store/app-review.md`, Step 1 to 7 |
| Report or Block say "could not…" | Migration 0008 not applied | `store/app-review.md` Step 1 |
| A report arrived but no push | `MODERATOR_USER_ID` not set, function not redeployed, or no `push_content_reports` webhook | Part 17a |
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
