# Drivalry Privacy Policy

**Effective date:** 3 November 2026

Drivalry is a driving app made by Ryan Orr, an independent developer. This policy explains what the Drivalry app for Android and iOS (package name `app.drivalry`) and the account service behind it collect, how that information is used, who can see it, how long it is kept, and how you can delete it.

## The short version

- Drivalry records your drives and scores them. The raw GPS route is processed and stored **on your phone only** and is deleted after 90 days. It is never uploaded.
- The cloud receives a **summary** of each drive (when, how far, how long, the score, the events that affected it, and the written verdict). It never receives coordinates or a route.
- Your **live location** is shared only with the friends, circles, and convoys you choose, and you can hide it with one switch.
- There are **no ads, no analytics or tracking SDKs, and no sale of data**. Nothing is shared with insurers, employers, advertisers, or data brokers.
- You can delete your account, and everything stored in the cloud about you, from inside the app at any time.

## 1. Information we collect

### Account

You sign in with Google or Apple. From that sign-in we receive a unique account identifier, your email address, and the name attached to your Google or Apple account. You then choose a handle and a display name, and you can add a profile photo. Your email address is used only to identify your account and is never shown to other users.

### Driving data that stays on your phone

To detect and score trips, the app processes the following on your device. None of this is uploaded.

- **Precise location**, recorded continuously while you drive, including in the background. Raw traces are kept for 90 days so you can view the trip map, then deleted.
- **Motion and activity data** (accelerometer, gyroscope, and the operating system's activity recognition) to tell driving from walking and to detect hard braking, acceleration, and cornering. The raw stream is discarded as it is processed; only detected events are kept.
- **Phone-handling signals**: the time your screen turned on or the phone was unlocked during a drive. Drivalry never reads notification content, app names, or what is on your screen.
- **Bluetooth device names** of cars you pair in the Garage, so the app can tell which car you are in and whether you are likely a passenger.
- **Battery level samples** while tracking, shown in the Diagnostics screen.
- **Saved places** (such as Home or Work), parking spots, vehicles, fuel and maintenance records, and vehicle documents. Documents are encrypted on the device.
- **Emergency contacts** you add for crash detection. Their phone numbers never leave your phone.

### Driving data stored in the cloud

For each trip, the app uploads a summary: start and end time, distance, moving time, the score and its components, points earned, whether you marked yourself a passenger, the vehicle label you chose, the weather category, how much of the drive was at night, the speed-limit data region used, and the written verdict ("roast" or praise). It also uploads the list of scored events (for example speeding or a harsh brake) with their type, severity, time offset within the trip, duration, how far over the limit, and the name of the road. Coordinates, start and end places, and the route are not uploaded.

### Live location

If you join a circle or convoy, or accept a friend, the app periodically sends your current latitude and longitude, speed, heading, battery level, and whether you are driving. Only the latest position is stored; each update overwrites the previous one, so there is no location history in the cloud. Nothing is sent while you are hiding.

### Social and game data

Friend connections, league and circle memberships, feed posts (trip cards and verdicts), reactions, comments, badges, duels, group challenges, season results, and global league entries.

### Blocks and reports

If you block someone, we store your account ID and theirs so the block can be enforced; the other person is not told. If you report a post or a comment, we store who reported it, who wrote it, which post or comment it was, the reason you chose, any note you typed, and a copy of the reported text so that we can review it even after it is deleted. Reports are read by a person and acted on within 24 hours.

### Convoys

Convoy membership, proposed stops and votes, shared expenses (amount, currency, category, and an optional note), and photos you add to the shared album. Convoy positions and push-to-talk voice travel directly between the phones in the convoy and are not stored by us.

### Crash alerts

If crash detection fires and you do not dismiss the countdown, the app stores your location at that moment and the time so that your emergency contacts who also use Drivalry can be notified. Your phone also opens a pre-filled text message to your other contacts, which you send yourself. Drivalry never calls emergency services automatically.

### Speed-limit corrections

If you flag a wrong speed limit, we store the road identifier (an OpenStreetMap way ID), the region, the limit you suggested, and your account ID. Once two users agree, the correction is shared with everyone anonymously.

### Push notifications

A device push token, the platform (Android or iOS), and a device label, so we can deliver notifications.

### Diagnostics

Battery and detection statistics are computed on your phone and shown in Settings. They are shared only if you tap "Send diagnostics", and they contain no coordinates.

### What we do not collect

Drivalry contains no advertising or analytics SDK, does not use the advertising identifier, does not upload your contacts or photo library, does not read your messages or notifications, and never uploads raw GPS routes.

## 2. How we use information

- To detect, score, and show your drives, and to generate the verdict for each one.
- To run leagues, circles, convoys, duels, challenges, seasons, and badges.
- To show your live location to the people you have chosen.
- To send notifications you have enabled (friend requests, reactions, league results, convoy events, arrival alerts, crash alerts).
- To improve shared speed-limit data from user corrections.
- To secure accounts and prevent abuse.

We do not use your information for advertising or profiling, and we do not sell it.

## 3. Who can see your information

Drivalry is a social app. Depending on what you join, other users can see:

- **Friends**: your handle, display name, profile photo, driver rating, trip cards and verdicts, badges, and your live location unless you hide it.
- **Circles**: your precise live location and arrival and departure alerts for places they have saved, unless you hide from that circle. Members can see that you are hiding.
- **Leagues**: your handle, display name, photo, scores, points, and verdicts. Global leagues match you with players you do not know, who see the same information.
- **Convoys**: your position during the convoy, your voice when you hold the talk button, stops, votes, expenses, and album photos.
- **Emergency contacts** who use Drivalry: your location at the moment of a crash alert.

Profile photos are stored at a public URL, so anyone who has the link can view the image.

## 4. Service providers and other third parties

We use the following companies to run the app. Each receives only what is needed for its function and is bound by its own privacy policy.

- **Supabase** hosts our database, sign-in, file storage, realtime messaging, and server functions. All cloud data described above is stored there.
- **Google** provides Sign in with Google, the Google Maps SDK, Places API, and Routes API, and Firebase Cloud Messaging for Android push notifications. When you view a map, search for a place, or ask for a route, your location or map viewport is sent to Google under the Google Privacy Policy.
- **Apple** provides Sign in with Apple and the Apple Push Notification service on iOS.
- **Open-Meteo** receives the rounded coordinates and date of a trip, once per trip, so we can tag the weather.
- **OpenStreetMap Nominatim** receives the coordinates of a parking spot or saved place to look up its street name. Requests are rate-limited and cached. Speed-limit data is derived from OpenStreetMap.
- **Metered** provides a relay server for convoy voice when the phones cannot connect directly. Voice is encrypted between phones; the relay only forwards packets and cannot listen.
- **Spotify** (optional) powers Convoy DJ. You sign in to your own Spotify account; your Spotify credentials are stored on your phone and are never sent to us.
- **GitHub** hosts the speed-limit data packs the app downloads. Like any download, GitHub sees your IP address.

We do not share personal data with advertisers, data brokers, insurers, or employers. We disclose information to authorities only when required by valid legal process, and we hold no raw location traces to hand over.

## 5. How long we keep information

| Data | Kept for |
| --- | --- |
| Raw GPS traces, motion data | On your phone only; traces deleted after 90 days |
| Trip summaries | Until you delete the trip or your account |
| Trip events | 1 year |
| Feed posts, verdicts, reactions, comments | 90 days |
| Live location | Latest position only; overwritten on each update |
| Crash alerts | 24 hours |
| Convoy photos and ended convoys | 30 days |
| Speed-limit corrections | Until your account is deleted |
| Push tokens | Until you sign out or delete your account |
| Blocks | Until you unblock or delete your account |
| Content reports | Until reviewed and deleted by us, or until the reporter deletes their account |
| Account, friends, leagues, badges | Until you delete your account |

## 6. Your choices

- **Location sharing**: hide from any circle, or from everyone, in Settings. Circles see that you are hiding.
- **Background location, motion, Bluetooth, microphone, and notifications** can be turned off in your phone's settings. Automatic trip detection stops without background location and motion access; push-to-talk needs the microphone only while you hold the button.
- **Passenger**: mark any trip as a passenger trip and it is not scored or posted.
- **Report and block**: long-press any post or comment to report it or to block its author. Reported content disappears for you immediately. Blocked people cannot see your drives, posts or location and cannot contact you; **Settings → Friends → Blocked people** lets you unblock.
- **Delete a trip** in the app and its cloud summary is removed as well.
- **Leave** any league, circle, or convoy at any time.
- **Access or correct** your information by contacting us at the address below.

## 7. Delete your account

Open **Settings** in the app and choose **Delete account**. This immediately removes your profile, trips, events, posts, memberships, corrections, crash alerts, push tokens, and photos from our database. Data on your phone stays until you uninstall the app. Content other people have already saved, such as a shared score card, is not affected.

If you cannot access the app, email us at the address below from the account's email address and we will delete it for you.

## 8. Security

Data travels over encrypted connections. Database rules ensure each user can read only the rows they are allowed to see. Vehicle documents are encrypted on your device. Raw location traces never leave your phone.

## 9. Children

Drivalry is for people aged 16 and over. We do not knowingly collect personal information from anyone under 16. If you believe a child has created an account, contact us and we will delete it.

## 10. Where data is processed and your rights

Our service providers may store and process data outside the country you live in, including in the United States. If you are in the EU, UK, or another region with data-protection law, our basis for processing is the contract to provide the service you signed up for, and your consent for optional features such as location sharing and Spotify. You have the right to access, correct, export, or delete your data, and to object to or restrict processing. You can exercise these rights in the app or by contacting us, and you may complain to your local data-protection authority. We do not sell personal information or share it for cross-context behavioral advertising.

## 11. Changes

If this policy changes, the new version will be posted at this address with a new effective date. Material changes will be announced in the app.

## 12. Contact

Questions, requests, or concerns: **[your contact email]**
