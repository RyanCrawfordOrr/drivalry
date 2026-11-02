# Drivalry: Privacy, Safety, Legal

This app knows where people are, how they drive, and who they are with. That is a lot of trust. These are the lines.

## 1. Consent and visibility

- **You only ever appear to people you chose.** Circles are opt-in per person. Every circle shares precise location by default. Each member has a per-circle **hiding** toggle, and the other members can see when you are hiding. There are no silent levels in between.
- **You always see who can see you.** A "Who can see me" screen lists every circle, every member, and whether you are hiding from them. Changes to who can see you trigger a notification.
- **No covert installs.** Account creation requires the person's own phone and Sign in with Apple or Google. There is no phone-number or password sign-up and no "add a family member's device" flow.
- **Minors**: 16+ by terms. No teen mode. No marketing to or features aimed at teens.
- **Roasts are public to your groups by default.** Joining a league or circle means your trip cards and roasts post there. The hiding toggle is one tap and visible to the group.

## 2. Data minimisation and retention

| Data | Where it lives | Retention | Notes |
| --- | --- | --- | --- |
| Raw 1 Hz GPS traces | Phone only | 90 days | Never uploaded. Used for the trip map, the appeal re-score and GPX export, then deleted |
| Accelerometer and gyro stream | Phone only | Discarded per batch | Only detected events (brake, accel, corner) are kept |
| Phone-handling events | Phone, then summary | Timestamps only | We never read notification content, app names, or screen content |
| Trip summaries and events | Supabase | Until account deletion | Score, components, XP, events with road names and durations. No coordinates, no start or end place, no route |
| Saved places (Home, Work) | Phone only | Until the user deletes them | Arrive/leave alerts are computed on the viewer's phone from presence updates |
| Presence (live location) | Supabase | Latest position only | Overwritten on each update; no history. Not written while hiding |
| Convoy positions | Phones only, over the peer-to-peer channel | 30 days on each phone | For the recap. The cloud never stores them |
| Crash alerts | Supabase | 24 hours | Location at the moment of the alert, so contacts can be pushed |
| Convoy photos | Supabase Storage | 30 days | Small images only; per-convoy cap |
| Speed-limit flags | Supabase | Indefinite | OSM way id, suggested limit, user id. No coordinates |
| Emergency contacts | Phone only | Until the user removes them | Phone numbers never leave the device; pushes go to contacts who are Drivalry users |

There is no analytics SDK. Battery and detection telemetry is computed on the phone and shown in Settings > Diagnostics. It is shared only if the user taps "Send diagnostics", and it contains no coordinates.

## 3. Account deletion and export

- Delete account: all cloud rows above are removed within 7 days. Shared artifacts (a convoy recap) lose the person's name and track. The local database is wiped on the device.
- Export: JSON of trips, events, scores, badges from the cloud; GPX of trips still within the 90-day window, generated on the phone.

## 4. Platform policies that gate shipping

- **iOS "Always" location** requires a purpose string that explains automatic trip detection and friend sharing. Apple rejects vague strings.
- **Android background location** requires a prominent in-app disclosure *before* the system prompt and a review video for Play. Drivalry's primary feature (automatic trips) justifies it; the disclosure must say so plainly.
- **Motion & Fitness / Activity Recognition** permission is needed for vehicle detection. Explain it is used only to start and stop trips.
- **Data safety / privacy nutrition labels**: precise location, shared with other users (by user choice), used for app functionality, not for tracking or advertising, not sold.
- **Microphone** permission for push-to-talk only, requested the first time a convoy radio is used.

## 5. Speed limits and liability

- Limits come from OpenStreetMap through our regional packs, plus shared user corrections, and **can be wrong**. The UI says "posted limit (map data)" and offers a one-tap correction. No roast is issued on a segment below confidence 0.7.
- Drivalry is **not evidence**. Terms state scores and events are estimates derived from consumer GPS and are not a record of legal violations. We hold no raw traces, so there is nothing to hand over. We do not share data with law enforcement except under valid legal process, and we notify the user where allowed.
- We do not sell or share driving data with insurers. A user may export their own data and do what they like with it.
- No feature rewards speed. This is a product rule and a liability rule.

## 6. Third-party terms we live under

- **OpenStreetMap (ODbL)**: packs are derived databases. Attribution in the app, and the packs themselves are published openly on GitHub Releases, which satisfies share-alike.
- **Google Maps Platform**: Places content is shown only on Google maps. Place details are not cached beyond what the terms allow (place ids may be stored; other fields are refreshed). Google attribution appears on every map.
- **Open-Meteo** (CC BY 4.0) and **Nominatim** (ODbL data, usage policy of 1 request per second with attribution): credited on the attribution screen; Nominatim is called sparingly and cached.
- **Spotify**: Convoy DJ uses the user's own Premium account under Spotify's developer terms. We never store Spotify credentials; tokens stay on the phone.
- The **attribution screen** (Settings > About > Attribution) lists OpenStreetMap, Google, Open-Meteo and Nominatim.

## 7. Safety design

- Driving UI is glanceable and voice-first. The phone app shows a "Driving. Hand this to a passenger." interstitial when a trip is active; the passenger can dismiss it. (This itself is a phone-handling event unless the screen is projecting to the car or the interaction is a single tap.)
- Spoken cues are off by default. When enabled they are short, rate-limited (1 per 60 s), and never scolding. Roasts arrive after the trip.
- A "Were you the passenger?" interstitial precedes scoring, so a passenger is never roasted for someone else's driving.
- Crash detection: on a candidate crash, show a 30 s full-screen countdown with a large "I'm OK" button and an audible alert. On timeout, push an alert with location to emergency contacts who use Drivalry and open a pre-filled SMS for the rest. Never auto-dial emergency services (false positives, jurisdiction differences). Candidate crash trips are excluded from roasting and scoring.
- Convoy "lost sheep" and stop votes are delivered as audio to drivers; passengers get the interactive UI.

## 8. Roast content rules (enforced by tests)

Banned anywhere in the template library: references to crashes, wrecks, death, injury, hospitals, alcohol, insults to the person (intelligence, body), and anything phrased as a dare or that suggests going faster. `packages/scoring/test/roast.test.ts` fails the build if a template matches the banned list, and the Dart port runs the same list against the same templates. New templates go through a human review and the test. There is no generated text, so the library is the whole surface to review.

## 9. Jurisdictional notes

- EU/UK: location is personal data; the lawful basis is contract (the service is location sharing and group play). Public roast posts are part of the service the user signs up for, with the hiding toggle as the withdrawal mechanism. DPIA required before launch there.
- California: CCPA "Do not sell" is trivially true; honor deletion and access requests within statutory windows.
- Some US states restrict recording of driving behaviour by employers; not relevant to a consumer app but a reason to never build the fleet product under this brand.
