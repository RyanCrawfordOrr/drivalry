# Store listing copy

The approved brand line is **“Good drives. Good company.”** Character limits are in brackets. This is an existing listing draft, not a verified compliance statement: check feature availability, privacy, battery, pricing, supported platforms, and age-rating answers against the release build before submission.

## Google Play

**App name** [30]
`Drivalry: Drive Score leagues`

**Short description** [80]
`Every drive scored 0–100 on your phone. Beat friends by driving well, not fast.`

**Full description** [4000]

```
Drivalry is the step challenge for driving.

Your phone notices when you drive and scores the trip from 0 to 100, right there on the device. Smooth, legal, attentive driving scores high. Speeding, hard braking and picking up the phone cost points, and the worst trips get roasted in public, where your friends can see them.

HOW IT WORKS
• Trips start and stop on their own. No buttons, no dashcam, no dongle.
• Every trip gets a Drive Score and a one-line verdict.
• Posted speed limits come from offline map packs on the phone, so scoring works without signal.
• Passengers are never scored. One tap says "I wasn't driving".

FRIENDS AND LEAGUES
• Weekly leagues with the people you add. Tiers from Learner to Chauffeur.
• Duels: challenge one friend to a week of better driving.
• Group challenges: a league goal everyone has to hit.
• Badges for streaks, clean trips and phone-free weeks. No badge rewards speed, ever.
• A feed where good drives get reactions and bad ones get a roast.

CIRCLES AND CONVOYS
• Circles share live location with the people you choose, and only them. Turn it off any time.
• Convoys for road trips: one shared map of every car, ETAs, a vote on the next stop, split costs, a shared album and a recap at the end.
• Push-to-talk radio between cars in a convoy, straight through your car's speakers.
• Convoy DJ keeps the same song playing in every car.

IN THE CAR
• Android Auto: your convoy, stops and live limit on the car screen.
• An ongoing notification shows the limit while you drive, with a Passenger button.
• Optional spoken cues. Off by default.

STATS AND SEASONS
• Streets, states, night miles, fuel estimates, fun facts.
• Quarterly seasons end with a shareable Season Wrapped.

PRIVACY, IN ONE PARAGRAPH
Raw GPS never leaves your phone; it is deleted after 90 days. Only trip summaries (score, distance, duration, the verdict) are stored in the cloud, and only your friends can see them. Your live location is shared only inside the circles and convoys you join, and you can hide it with one switch. Nothing is sold, and there are no ads.

Drivalry needs location access "all the time" to detect drives automatically while the app is closed, plus motion data to tell driving from walking. Battery use is under 1% a day parked.

Free. No subscriptions, no in-app purchases.
```

**Category** Maps & Navigation (or Auto & Vehicles)
**Tags** driving, safe driving, friends, league, road trip
**Contact email** your Gmail
**Privacy policy URL** the page from `docs/05-privacy-safety-legal.md` once published

### Declarations the console asks for

| Question | Answer |
| --- | --- |
| Target audience | 18+ (driving) |
| Ads | No |
| In-app purchases | No |
| User-generated content | Yes: roast comments and reactions between friends, with report and block, visible only to accepted friends |
| Location permission (background) | Yes: automatic trip detection while the app is closed; a prominent in-app disclosure appears before the request |
| Data safety: location | Collected and shared with user-chosen friends; user controls; not sold; not used for ads |
| Data safety: personal info | Name and email from the sign-in provider; account can be deleted in Settings |
| Android Auto | Declared, category Point of interest, Car App Library templates only |

## App Store

**Name** [30]
`Drivalry: Drive Score leagues`

**Subtitle** [30]
`Drive well. Beat your friends.`

**Promotional text** [170]
`Your phone scores every drive 0–100 and your friends see the result. Smooth driving climbs the weekly league. Speeding gets roasted. Convoys get a shared map and a radio.`

**Keywords** [100]
`driving,drive score,safe driving,friends,league,convoy,road trip,walkie talkie,speed limit,commute`

**Description** [4000]
Same text as the Play full description, with the IN THE CAR section replaced by:

```
IN THE CAR
• A Live Activity on the lock screen and in the Dynamic Island shows your live limit and the convoy, with a Passenger button.
• Optional spoken cues. Off by default.
• CarPlay is on its way.
```

**Primary category** Navigation. **Secondary** Social Networking.
**Age rating** 17+ is not needed; answer the questionnaire honestly (no violence, no gambling, infrequent mild language in roasts is "None" because roasts are generated from fixed templates).
**Copyright** `2026 Ryan Orr`
**Privacy nutrition labels** Location (linked to you, used for app functionality, shared with friends you choose); Contact info: email and name (sign-in); Identifiers: user id. Nothing used for tracking.

**App Review notes**
The full text, the screen-recording shot list and the resubmission checks are in `store/app-review.md` (Apple asked for them under Guideline 2.1 on 2026-11-05). The short version: there is no password to give, Sign in with Apple with any Apple ID creates an account; a scored trip without driving is Drive → **See a sample drive** (also Settings → Drives → Sample drive); a review league code and a circle code let the reviewer see posts and the live map; Report and Block are on every post, comment and profile.

## Screenshot captions

The marketing lines rendered onto each screenshot are in the scenes under `app/test/art/scenes/`; the stores need no separate captions.

## What is not written here

- Android Auto review screenshots must come from the Desktop Head Unit (`docs/11-owner-setup.md` Part 7).
- The privacy policy text lives in `docs/05-privacy-safety-legal.md`.
