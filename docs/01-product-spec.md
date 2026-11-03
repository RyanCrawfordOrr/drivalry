# Drivalry: Product Spec

> Status: v0.2 draft, rewritten 2026-11-02 for the Flutter, local-first, zero-cost architecture. Everything here is the intended product. `docs/06-roadmap.md` says the order it gets built in. `docs/00-decisions.md` says why.

## 1. One-liner

A step challenge for driving. Every trip is detected and scored automatically, on the phone. Friends compete in weekly leagues on *how well* they drive, not how far or fast. The app praises good driving, roasts bad driving in front of your friends, keeps your circle in the loop like Life360, and turns road trips into a multiplayer event.

## 2. Who it is for

- **Friend groups** who already share location and trash-talk each other. Primary.
- **Households and families** who want Life360-style awareness without a surveillance vibe. Secondary.
- **Car clubs and road-trip crews** who want convoy coordination and a trip recap. Secondary.
- Global from day one. Speed limits only work where a regional pack exists; the first packs cover every US state.
- 16+ by the terms of service. No teen mode. Explicitly not a teen-monitoring product and not an insurance telematics product (see §9).
- A hobby project by Ryan Orr, built with Claude Code, in a public MIT repo (https://github.com/RyanCrawfordOrr/drivalry). That shapes the product: no paid services, no server we run, nothing that needs a support team.

## 3. The core loop

```
Phone detects you are driving  →  trip is recorded on the phone (low power)
      →  trip ends  →  "Were you the passenger?"  →  scored on the phone (0–100 Drive Score)
      →  trip summary uploads (no raw GPS)  →  praise or a public roast, XP, badge progress
      →  XP feeds your weekly league with friends
      →  Sunday night: promotions, demotions, Wall of Fame / Wall of Shame
      →  repeat
```

The thing that keeps people opening the app is the **league** and the **feed** (friends' trip cards, roasts, reactions, comments). The thing that keeps them *installed* is the passive value: parking memory, live circle, crash detection, trip log.

## 4. Feature areas

### 4.1 Automatic trip tracking

- Trips start and stop with **no user action**. Triggers: OS vehicle-motion detection, car Bluetooth / CarPlay / Android Auto connection, or leaving a known parking spot at vehicle speed.
- Each trip records, on the phone only: route, per-second speed, heading, altitude, motion events, phone-handling events, start and end places, vehicle used, weather at start, daylight or night. Raw GPS stays on the phone for 90 days and is never uploaded.
- Speed limits come from a downloaded regional pack built from OpenStreetMap. Matching the route to roads and scoring both happen on the phone, so a trip is scored with no network at all.
- **Passenger interstitial**: when a trip ends, the app asks "Were you the passenger?" before it scores. The answer is pre-filled "yes" when the phone connected to a car that is not in your garage, or when a circle member's trip overlaps yours in time and place. Passenger trips earn no XP and no roasts, but still count toward road-trip stats. Passenger claims are honor-system; your groups see how many trips you have marked.
- **Manual controls**: pause tracking for N hours, mark a vehicle as "never track" (rental, work truck), delete any trip.
- Trip cards show: map (on your phone only), score ring, component breakdown, timeline of events with map pins ("41 in a 25 for 90 s on Elm St"), stats (distance, time, average and max speed, fuel estimate), how much of the trip had a known speed limit, and the roast or praise line.

### 4.2 Drive Score and feedback

Covered in detail in `02-game-design.md`. Summary:

- **Drive Score 0–100** per trip from four components: Speed Discipline, Smoothness, Attention, Efficiency.
- **Driver Rating** is a rolling 30-day weighted average shown on your profile.
- **Praise and roasts** are picked from a fixed, human-written library based on the events in the trip. No generated text. Roasts are **public to your groups by default**: the roast line is posted with the trip card to every league and circle feed you belong to, and friends can react and comment. Every group is mean. There is no per-group toggle. The only opt-out is a per-member **hiding** toggle, and everyone in the group can see that you are hiding.
- **Reckless flag**: egregious trips (25+ mph over the limit sustained, 100+ mph anywhere, phone use at highway speed for long stretches) get stamped RECKLESS: zero XP, streak reset, and a Wall of Shame post in your groups.
- **Silent where unsure**: no roast is issued on a road where the pack has no limit or the confidence is below 0.7. You can flag a wrong limit from the trip card; two agreeing flags fix it for everyone.
- **Spoken cues (optional, off by default)**: short cues during a drive through the car speakers ("Limit's 35." / "Smooth."). No screen interaction. The roast itself always waits until after the trip.

### 4.3 Leagues, challenges, and rivalry

- **Weekly leagues**: up to 30 people, Monday to Sunday, Duolingo-style tiers (Learner → Bronze → Silver → Gold → Platinum → Diamond → Chauffeur). Top 5 promote, bottom 5 demote. You can be in one "global" league (matched with strangers of similar rating) and any number of **friend leagues**.
- **Friend leaderboards**: all-time and weekly, filterable by stat (Drive Score, smoothness, phone-free streak, states visited, etc.). Never filterable by top speed.
- **Head-to-head duels**: challenge a friend for a week on one metric; the loser's profile shows the loser badge for 7 days.
- **Group challenges**: cooperative goals ("circle logs 20 phone-free trips this week"). Unlocks a group badge.
- **Streaks**: clean-trip streak (score ≥ 80, no reckless), phone-free streak. A daily "drove today" streak is intentionally *not* a thing.
- **Seasons**: 3-month seasons with a seasonal badge set and a "Season Wrapped".

### 4.4 Stats and fun facts

All computed on your phone from your own trips, shown on your profile and in the Wrapped:

- Totals: miles, hours, trips, fuel estimate and $ estimate, CO₂ estimate.
- Records: longest trip, highest altitude, earliest and latest drive, most trips in a day, longest clean streak.
- Geography: states/provinces and counties visited (a map that fills in), home radius (90% of miles within X miles of home), farthest point from home, "most driven road".
- Habits: Night Owl %, weekend vs weekday split, average trip length, most visited places (labels from your saved places), "Groundhog Route" (most repeated route).
- Reality checks: **time saved by speeding** (e.g. "You drove over the limit for 4.2 h this month. It saved you 11 minutes."), ticket-risk minutes, money burned by hard acceleration.
- Social: convoys joined, convoy miles, friends you have driven with most, "DJ score" if music is connected.
- Vehicle: per-car MPG (manual fill-ups or OBD-II), per-car score (are you worse in the truck?).

Only the headline numbers you choose to show go to your profile. The trips behind them stay on the phone.

### 4.5 Friends and circles (the Life360 layer)

- **Circles**: named groups (Family, Roommates, The Boys). Location sharing in a circle is **precise by default** for every member. Each member has a **hiding** toggle per circle. While hiding, your position is not published and the circle sees that you are hiding. There are no intermediate levels.
- **Live map** (Google Maps): the Drive tab opens with it. It shows accepted friends and circle members: positions, "Driving now", battery level, last-seen time, and expands to full screen. Positions update every 30 s while driving and on significant movement otherwise (see architecture). Accepted friends see each other by default (ADR-018); a single "Hide my location" switch in Settings stops all sharing at once, on top of the per-circle hiding toggle.
- **Places and alerts**: saved places (Home, Work, School); opt-in arrive/leave notifications per member per place. Quiet hours. Your places never leave your phone; the alert is computed on your phone from the member's position.
- **Driving status**: "Ryan is driving, 12 min away" in the circle, plus an "I'm driving" auto-reply to texts via OS Focus / Driving mode integration where available. _Built 2026-11-03 as a link, not an implementation: Settings › During a drive › Auto-reply to texts opens Android's Do Not Disturb settings (where the Driving rule lives) and, on iOS, shows the steps to create a Driving Focus. Drivalry never reads or sends messages._
- **Crash detection**: accelerometer spike plus sudden stop plus no movement starts a 30 s full-screen countdown. On timeout the app pushes an alert to your emergency contacts who use Drivalry and opens a pre-filled SMS with your location for the rest. Never an automatic phone call. Can be turned off. Clear false-positive handling.
- **Check-in**: one tap "I got home" that posts to the circle. Also auto-fires when arriving at Home after a trip, if enabled.
- **Trip visibility**: circle members see your trip cards (score, events with road names, roast). Route lines never leave your phone, so nobody sees where a trip went, only how it was driven.

### 4.6 Convoys and road trips

A **Convoy** is a temporary group of 2–6 cars with a shared destination and a shared session.

- Create → invite (link / QR / circle) → set destination and optional stops → go.
- **Convoy map**: everyone's position at 3–5 s refresh, leader marked, gap in minutes between cars, each car's ETA. Positions travel car to car over the same peer-to-peer connection as the radio.
- **Regroup**: leader drops a pin; everyone gets a route to it. "Lost sheep" alert when a member falls more than N minutes behind or takes a different route.
- **Stops**: anyone proposes a stop (gas, food, bathroom, photo); quick vote; the winner becomes the next waypoint. Suggestions come from Google Places near the route, filtered by category and detour time. Places is capped per day; past the cap, stops are proposed by dropping a pin or typing a name.
- **ETAs** come from the Google Routes API, also capped per day. Past the cap the app shows a straight-line estimate and says so.
- **Radio**:
  - **Push-to-talk** between cars, peer to peer over LTE/5G. Big button on the phone, Siri/Assistant shortcut, steering-wheel voice command via the car-platform app, and a hardware-button option where the OS allows. This is the signature convoy feature.
  - **Shared music**: one-tap into Spotify Jam / Apple Music SharePlay (deep links; both have no public API). Plus **Convoy DJ**, our own sync: a shared queue where each car's Spotify plays the same track in lockstep via the Spotify Web API (each car needs Premium). Vote-to-skip. Spotify keeps hobby apps on a small user allowlist, so Convoy DJ is a friends-only feature by design.
  - **Convoy chat**: voice-note-first chat thread, read aloud to drivers, typed by passengers.
- **Convoy games** (passenger-driven, driver gets audio only): license-plate bingo, roadside trivia, "spot the…" scavenger lists, "who's smoothest this leg".
- **Cost split**: log gas/tolls/food per car, settle up at the end (Venmo/Cash App deep links).
- **Shared album**: small photos grouped by stop; the recap stitches them onto the map. Cloud storage is limited, so albums are capped per convoy and age out after 30 days.
- **Recap**: animated map playback built from the convoy positions your phone saw during the drive, per-car stats from trip summaries, awards (Smoothest, Lead Foot (dishonorable), Most Stops Proposed, DJ, Navigator), total cost, shareable video.
- **Planning**: multi-day itineraries, "leave by" times, lodging pins. Optional.

### 4.7 Garage

- Multiple vehicles, auto-detected by Bluetooth name; per-vehicle stats and score.
- Fuel log: manual fill-ups (odometer, gallons, $) → true MPG; optional OBD-II Bluetooth dongle for live fuel rate and RPM (deepens the Efficiency score).
- Maintenance reminders by mileage/time (oil, tires, registration, inspection).
- **Parking memory**: trip end location auto-saved with a photo option and a walking route back. Free by-product of trip detection. Stays on the phone.
- Documents: insurance card, registration photos (local, encrypted).

### 4.8 In-car experience

Covered in `04-car-platforms.md`. Summary: CarPlay (Driving Task category) and Android Auto (POI category) apps that show *one* big number (live Drive Score or "Clean so far"), the convoy member list with gaps and ETAs, a push-to-talk button, and the next stop. No feed, no leaderboard, no roast text while moving. iOS Live Activity / Dynamic Island and the Android ongoing notification do the same job without the car screen.

### 4.9 Social and sharing

- Feed per circle and league: trip cards (score, events, roast or praise), badges earned, league results, convoy recaps. Reactions and comments on everything. A "Snitch" reaction on friends' speeding events.
- Shareable images and video: trip card, Wrapped, convoy recap, badge unlock. Shared images never include a route map.
- Profile: rating, tier, badges, headline stats, garage, passenger-marked trip count, hiding status per group.

### 4.10 Notifications

- Trip scored (with the roast or praise line). Batched if several trips in a row.
- League events: promoted/demoted, friend passed you, final hours.
- Circle: arrive/leave alerts, driving-now (opt-in), check-ins, crash alerts (always).
- Convoy: invites, lost sheep, stop votes, PTT messages when backgrounded.
- Everything but crash alerts respects quiet hours.
- Delivered through APNs and FCM.

## 5. Things we deliberately do not build

- Any speed-based achievement: top speed, 0–60, fastest route, quickest commute, "beat your time". Nothing that makes a faster drive feel like a win.
- Mileage-based leagues. Distance credit is capped per day so the league rewards quality.
- Covert tracking. Every tracked person is a user who consented in the app on their own phone, and sees exactly who can see them.
- Selling or sharing location data with third parties, including insurers and data brokers. A user-initiated "export my driving report" is fine; a data feed is not.
- Roasts of people. Roasts target the drive ("that lane change"), never the driver's intelligence, body, etc. Fixed template library. No generated text, no free-text roasts by users.
- A teen mode or any parent-over-child feature.
- A server we operate, or any paid API. If a feature needs one, the feature changes.

## 6. Money

Drivalry is free. No ads, no subscription, no data sales. The owner pays the store fees ($99/yr Apple Developer, $25 Google Play) and nothing else. Every service runs on a free tier, and when a free tier runs out the feature degrades instead of billing (see `03-architecture.md` §10). Outgrowing free tiers would be a new decision, not an automatic upgrade.

## 7. Platforms

iOS 16+ and Android 10+ (background location and activity recognition behave acceptably from there). Flutter app in `app/` with our own native plugins for tracking and car screens. Bundle and package id `app.drivalry`. All authoring on Windows; a Mac only builds, signs and uploads the iOS app. Testers get builds through TestFlight and Play internal testing. No web app.

## 8. Success metrics

- D7 retention of users who completed one league week.
- % of trips auto-detected correctly (target > 95% start, > 98% end).
- Battery: < 6% per hour while driving, < 1% per day parked, measured on the owner's test phones.
- Share of moving time with a known speed limit (target ≥ 80% on the owner's regular routes).
- Average Drive Score trend for users after 4 weeks (the product should make people drive better).
- Convoys created per 100 weekly actives.

## 9. Adjacent products we are not

- **Teen monitoring**: a legit market but a different brand promise. Drivalry is 16+ and has no teen mode.
- **Insurance telematics**: a user may export their own driving report and hand it to anyone they like. We never integrate with insurers.
- **Fleet**: no.
