# Drivalry: owner setup checklist

> Everything the app needs that only the account owner can do. The code for every feature is in the repo; these steps turn the features on. Each step says what it unlocks, so skip what you do not need yet. Nothing here costs money. The detailed walkthroughs live in the files linked; this page is the order.

Status column: tick when done, and add the date.

## 1. Apply the Supabase migrations (unlocks every cloud feature)

Dashboard → SQL Editor → New query → paste one file → Run, in this order:

| File | Unlocks |
| --- | --- |
| `supabase/migrations/0001_init.sql` | accounts, friends, leagues, feed, badges, circles, convoys, buckets |
| `0002_presence_friends_account.sql` | friends map, hide location, delete account |
| `0003_checkins.sql` | check-in posts |
| `0004_crash_contacts.sql` | emergency contacts outside your circles |
| `0005_convoy_vote_withdraw.sql` | withdrawing a stop vote |
| `0006_convoy_can_view.sql` | convoy recap can read co-members' summaries |
| `0007_duels_challenges_seasons.sql` | duels, group challenges, seasons, global leagues |

`0001` runs once on a fresh project and fails loudly if re-run; the rest only add. If a statement fails, paste the error into the session and it gets fixed forward (`supabase/README.md`).

`0007` creates three pg_cron jobs. pg_cron is on by default for Supabase projects; if the editor says the extension is missing, run `create extension if not exists pg_cron;` first and re-run the file.

## 2. Sign-in (unlocks accounts; `docs/09-auth-setup.md` §1–§6)

1. §1 Google: one OAuth client of type **Web application** (its id goes in `.env` as `GOOGLE_WEB_CLIENT_ID`) plus one **Android** client with package `app.drivalry` and your debug keystore SHA-1, and one **iOS** client with bundle `app.drivalry` (`GOOGLE_IOS_CLIENT_ID`). Paste the web client id and secret into Supabase → Authentication → Providers → Google.
2. §2 Apple: needs the Mac and the developer account; can wait until the first iOS build.
3. §3 Turn email sign-in off. §4 Auth settings.
4. §5 Put the ids in `.env`. §6 Check it worked.

## 3. Push notifications (unlocks reactions, friend requests, crash alerts, duels, convoy alerts)

1. `docs/09-auth-setup.md` §7: create the Firebase project on the existing Google Cloud project, copy the five `FIREBASE_*` values into `.env`, and upload the APNs key when the iOS build exists.
2. `supabase/functions/push/README.md`: install the Supabase CLI, `supabase link`, `supabase functions deploy push --no-verify-jwt`, set the secrets (`PUSH_WEBHOOK_SECRET`, `FCM_SERVICE_ACCOUNT_JSON`, and the APNs ones later), then create the five Database Webhooks (`feed_reactions`, `feed_comments`, `friendships`, `duels`, `crash_alerts`) with the `x-push-secret` header.
3. Redeploy the function after any later edit to `index.ts`.

## 4. Lock the Google key (protects the free tier; do this before the key is in anyone else's hands)

Google Cloud Console → APIs & Services → Credentials → the Maps key:

1. **API restrictions** → Restrict key → tick only: Maps SDK for Android, Maps SDK for iOS, Routes API, Places API (New).
2. **Application restrictions**: a single key can carry only one kind. Leave it on *None* while one key serves both platforms and lean on the API restriction plus the quotas below; split into an Android-restricted and an iOS-restricted key later if abuse ever shows in the console.
3. APIs & Services → Quotas: Routes API `Compute Routes requests per day` → 300; Places API (New) `Nearby Search requests per day` and `Text Search requests per day` → 150 each. Map tiles for the mobile SDKs are free without limit. The phone also enforces per-device daily caps (Places 20, Routes 40), so these are the ceiling, not the normal spend (`docs/03-architecture.md` §9–§10).

## 5. Optional keys (each one switches on a convoy feature; the app is honest about their absence)

| `.env` key | Get it from | Unlocks | Without it |
| --- | --- | --- | --- |
| `METERED_DOMAIN`, `METERED_API_KEY` | dashboard.metered.ca → free account → create an app → *TURN server* → API key; the domain is `<app>.metered.live` (`docs/10-convoy-protocol.md` §7) | convoy radio between phones on different mobile networks (TURN relay, 20 GB/month free) | radio works on the same Wi-Fi only; relayed connections show "direct connection failed" |
| `SPOTIFY_CLIENT_ID` | developer.spotify.com → Create app → redirect URI `drivalry-auth://spotify-callback`; add each friend's Spotify email under *User Management* (`docs/09-auth-setup.md` §8) | Convoy DJ (Spotify Premium accounts, up to 25 allowlisted) | Music screen shows Jam and SharePlay links only |

## 6. Rebuild and install after any `.env` change

The values are compiled in, so every `.env` edit needs a rebuild:

```powershell
cd C:\Drivalry\app
flutter build apk --debug --dart-define-from-file=../.env
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Sign in on two phones (or two accounts) to see friends, leagues, convoys and the radio do anything.

## 7. Android Auto (`docs/04-car-platforms.md` §3.4–§3.5)

1. Test now on the Desktop Head Unit: install it from the SDK Manager, unlock Android Auto developer settings on the phone, enable *Unknown sources* and *Start head unit server*, `adb forward tcp:5277 tcp:5277`, run `desktop-head-unit.exe`.
2. Before the Play release: declare the Android Auto form factor under *App content*, category **Point of interest**, with DHU screenshots.

## 8. On the Mac (`app/ios/README-mac.md`)

1. §1–§3 Xcode, Flutter, CocoaPods, the repo and `.env`.
2. §4 steps 1–7: team, Background Modes, Push Notifications, Sign in with Apple, URL scheme, minimum iOS 16.0, Tracking group.
3. §4 step 8: create the `DrivalryWidgets` extension target for the Live Activity and add the two source files that are already in the repo.
4. §5 build to an iPhone; Settings → Drivalry → Live Activities on.
5. Request the **CarPlay Driving Task** entitlement at developer.apple.com → Account → Additional resources → CarPlay. The in-app tree is ready; `docs/04` §2 has the five Xcode steps for when it is granted.
6. §6 TestFlight when the seven test phones are ready (`docs/06-roadmap.md` M1.6).

## 9. Nothing to do

- Speed-limit packs rebuild monthly on GitHub Actions and the app reads the `packs-index` release; the first release (`packs-2026.11`, 52 packs) is live.
- The Supabase keep-alive runs daily with the two repo secrets already set.
- CI runs on every push (five jobs).

## 10. Before the first external build

- Check every free allowance in `docs/03-architecture.md` §10 against the providers' current pricing pages.
- Set `APNS_SANDBOX=false` on the push function once builds come from TestFlight.
- Read `docs/05-privacy-safety-legal.md` and publish the privacy policy page it describes; the store listings link to it.
