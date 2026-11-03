# `push`: notification fan-out

One Edge Function. Database Webhooks call it when a row that should notify someone is written; it looks up the recipients' device tokens and sends through APNs and FCM. It never sends for trip scoring (the phone scores locally and shows its own notification), only for things another person did: reactions, comments, friend requests and acceptances, and crash alerts to circle members.

## Deploy (owner, once; then on every change to `index.ts`)

Needs the Supabase CLI (`npm i -g supabase` or `winget install Supabase.CLI`) and a one-time `supabase login` in a browser.

```powershell
cd C:\Drivalry
supabase link --project-ref htqyutdwnnguqatakofx
supabase functions deploy push --no-verify-jwt
```

`--no-verify-jwt` because webhooks do not carry a user JWT; the function checks `x-push-secret` instead.

## Secrets

```powershell
supabase secrets set PUSH_WEBHOOK_SECRET=<long random string>
supabase secrets set APNS_TEAM_ID=<10-char team id> APNS_KEY_ID=<10-char key id> APNS_BUNDLE_ID=app.drivalry APNS_SANDBOX=true
supabase secrets set APNS_PRIVATE_KEY="$(Get-Content -Raw .\AuthKey_XXXXXXXXXX.p8)"
supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(Get-Content -Raw .\drivalry-firebase-adminsdk.json)"
```

- **APNs key**: developer.apple.com → Keys → `+` → name `Drivalry push`, tick Apple Push Notifications service (APNs) → Register → download the `.p8` once. Team ID is top right of the account page. Set `APNS_SANDBOX=false` once builds come from TestFlight or the App Store.
- **FCM**: console.firebase.google.com → Add project → pick the existing Google Cloud project `drivalry` (no new billing; Firebase Cloud Messaging is free) → Project settings → Cloud Messaging → make sure the Firebase Cloud Messaging API (V1) is enabled → Service accounts → Generate new private key. The app itself needs no `google-services.json`: it initialises Firebase from the `FIREBASE_*` values in `.env` (docs/09-auth-setup.md §7). Both platforms register FCM tokens; the function routes 64-hex tokens to APNs and everything else to FCM, so the APNs secrets are only needed if a native APNs path is ever added.
- Keep the `.p8` and the service-account JSON out of the repo. Delete the local copies after setting the secrets.

## Database Webhooks (Dashboard → Database → Webhooks → Create)

Create one webhook per row, all `POST` to the function URL `https://htqyutdwnnguqatakofx.supabase.co/functions/v1/push`, with the HTTP header `x-push-secret: <the same random string>` and the default timeout:

| Table | Events |
| --- | --- |
| `feed_reactions` | INSERT |
| `feed_comments` | INSERT |
| `friendships` | INSERT, UPDATE |
| `crash_alerts` | INSERT |

## Test

```powershell
curl -X POST https://htqyutdwnnguqatakofx.supabase.co/functions/v1/push -H "x-push-secret: <secret>" -H "content-type: application/json" -d '{"type":"INSERT","table":"friendships","schema":"public","record":{"requester_id":"<uuid>","addressee_id":"<uuid>","status":"pending"},"old_record":null}'
```

Expect `{"sent":N,"dead":0,"recipients":1}`. Logs: Dashboard → Edge Functions → push → Logs.

## Budget

Free tier: 500k invocations a month. One invocation per webhook event; a crash alert to a 10-person circle is still one invocation. Quiet hours are enforced on the phone (the payload carries `category`), except `crash`, which is always shown.
