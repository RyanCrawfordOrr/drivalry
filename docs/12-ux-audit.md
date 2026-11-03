# Drivalry: UX audit before the Waze × Kith pass (2026-11-03)

> Read-only audit of the app as built through Stage 5, produced to drive `12-ux-direction.md`. Paths are under `app/lib/`. Font sizes quoted are Material 3 defaults because the theme set no text theme at the time: bodySmall 12, bodyMedium 14, labelLarge 14, titleMedium 16, titleLarge 22, headlineSmall 24, headlineMedium 28, displayMedium 45.

The theme (`app/theme.dart`) only set a seeded ColorScheme, always-visible nav labels and a Card shape. Every screen therefore used stock M3 widgets with local styling.

## 1. Information architecture

Five tabs (`app/routes.dart` `AppTab`, stock `NavigationBar`; tapping the active tab pops to its root):

| Tab | Root | What it shows |
| --- | --- | --- |
| Drive | `DriveScreen` | App bar with 4 actions; friends-map card (40 % of height, 220–420); crash card; tracking card; parking, vehicle and passenger prompts; Last trip and Recent |
| Leagues | `LeaguesScreen` | Season card, global league card, friend leagues, FAB "League"; Duels and Badges as app-bar icons |
| Friends | `FriendsScreen` | Feed / Friends / Circles tabs, FAB "Add friend", requests icon |
| Convoy | `ConvoyScreen` | Intro sentence, New convoy and Join buttons, active and past convoys |
| Garage | `GarageScreen` | Vehicles, ignored car audio, FAB "Add vehicle" |

Depth: Drive one level (`trip/:id`, `packs`, `map`, `parking`, `diagnostics`); Leagues one level plus `/join/league/:code`; Friends two levels (circles, places, post); Convoy two levels (`:id/{radio,stops,chat,music,games,expenses,album,recap}`); Garage two levels plus four inner tabs. Outside the shell: `/settings` + 6 sub-routes, `/crash`, `/sign-in`, `/profile`, `/profile/stats`, `/profile/wrapped`.

Reachability problems:

- Your own Profile, Stats and Wrapped sit behind Drive → gear → Settings → handle tile; Stats is three levels deep. Profile's gear goes back to Settings (a loop).
- Overflow-only: Drive overflow holds Simulate, Packs, Units, Diagnostics (Simulate is a developer tool); trip detail passenger/re-score/delete; tracking pause and off behind `more_horiz`; league hide/leave; convoy rename/leave; circle leave; stop accept/reject/done in a "Leader" popup; friend removal and request Block in row popups.
- Icon-only app-bar actions: Badges, Duels, friend requests. The Drive requests icon is the same glyph as the Friends tab; Friends uses a different icon for the same action.
- Hidden: Seasons (text button on the season card), Parking (parking card), full-screen friends map (small expand icon), Places (from Circles only). `Routes.circles` is never navigated to.
- Settings opens Packs and Diagnostics with `context.go`, losing the back stack. Leagues and Duels nest a Scaffold inside a Scaffold for a FAB.
- Convoy detail packs eight features into small ActionChips; Radio, the driving-critical one, has no priority. Drive does not surface an active convoy.

## 2. Screen by screen (highlights)

- **Drive.** Above the fold: busy app bar, the map card, then the tracking card; live speed starts around y≈400 on an 800 dp phone. Primary action unclear ("Allow" / "Start now" outlined / "End now" as a TextButton). Empty state points at the Simulate dev tool. Map notices include "Offline build…" and "Map unavailable: build with --dart-define-from-file…". Tracking card: plugin-missing text names the native plugin; permission bullets of 20–30 words; raw `state.error` in red. Live card sizes: speed 45 sp, everything else 12–16 sp. Parking "Forget" deletes the photo without confirm or undo.
- **Trip detail.** 260 px map, ring 112, verdict, breakdown, stats grid, events. Jargon: "pack us-ca, OSM Mar 2026", "Hard brake, 3.4 m/s² at 40 mph" (title says "Harsh brake"), "Observation only: limit not confident". Long flag-sheet copy. "Could not share: $e".
- **Friends.** Feed filter chips, post cards with a hand-made 56 px bordered score circle, reaction FilterChips, a Comment TextButton. Empty feed has no button. Loading is the word "Loading…"; errors show the raw exception in a banner. "rating 72" lowercase here, "Driver Rating" on Profile. QR on a hard-coded white background.
- **Leagues.** Season card, global card, friend leagues; empty state is a 47-word rules paragraph; the global explainer another 35 words. Standings are dense ListTiles in Cards with 11 sp zone labels. Members-sheet error raw.
- **Duels.** A won duel shows "You won" in bodySmall with a 16 px trophy. No celebration.
- **Badges.** Three streak Cards, a flat list, no imagery, no progress toward locked badges. "Could not load badges: $e".
- **Stats / Wrapped.** Chips, headline card, FactTiles, state chips. Wrapped: ten hard-coded palettes, no intro or reveal.
- **Circles.** "I got home" button at the top, create CTA as a TextButton at the bottom; definition-paragraph empty state without a button.
- **Convoy.** Intro text + two buttons; 50-word empty Card. Detail: map flex 5 / panel flex 4, dense member rows ("62 mph · 1.2 mi from the leader · ETA ~14 min"), lost cars flagged by a tooltip icon, eight ActionChips. Radio: 200 px PTT (good), but "Start radio" each time, peers show "Relayed · data on · ↑12 KB ↓40 KB", relay footer jargon. Stops: compact ~40 dp vote buttons, 12 sp counts, leader accept hidden. Music: "no Spotify client id is configured (docs/09 §8)".
- **Garage.** Cards with three-line subtitles; vehicle detail has four tabs each with its own FAB; empty states are plain centred text.
- **Profile.** Avatar with hard-coded 32 sp initials and a white camera icon; clean streak computed twice from two sources; badge chips not tappable; "Pull to refresh" empty copy.
- **Settings.** Six groups with labelLarge-in-primary headers; "Every trip on this phone, as JSON"; raw error toasts; delete account is the only destructive confirm styled as destructive. Notifications list shows raw channel names; emergency contacts render `'$e'`.
- **Sign-in.** Stock `Icons.directions_car` instead of the brand mark; hard-coded black/white Apple button; a "G" text as the Google logo; no "Not now".
- **Diagnostics.** ~40 raw ListTiles, one tap from the home overflow.
- **Crash countdown.** The reference for in-car sizing: 120 sp number, 96 px "I'm OK" with a 32 sp label, 56 px "Send help now", back gesture blocked.

## 3. Consistency

- Score display: 4 variants (ScoreRing; a hand-made bordered circle in the feed; plain text in Season; `_Number` in profile stats).
- Score components: 4 variants (chips "Smooth −2.4"/"Speed ✓"; bars; feed chips shown only when > 0; share-card bars).
- Avatars: 5 implementations plus two marker-bitmap painters.
- Stat tiles: 8 variants; label sometimes above, sometimes below the value.
- Section headers: at least 6 styles across titleSmall, labelLarge, titleMedium, with five different paddings.
- Empty states: 5 patterns, almost none with an in-place button.
- Errors: 30+ sites interpolate the raw exception (`'…: $e'`).
- Cards: everything a stock Card (filled, radius 16), some wrapping a ListTile, some a Padding; ink radius 12 inside radius-16 cards; coloured variants for passenger, crash, lost sheep, league banner.
- Primary action placement varies by tab (FAB, inline FilledButton, bottom TextButton, none).
- Chips used as navigation, as actions, as popup triggers, as status; a custom TierChip with a 0.6-alpha border; three near-identical join-code dialogs; the units picker duplicated as a dialog and a SegmentedButton.
- Units leak: the friend sheet hard-codes mph; parking shows "Accuracy about N m".
- About 50 plain `AppBar(title: Text())`; no large titles or custom headers.
- Padding: `all` 3/6/8/10/12/16/24/32/72; ~40 distinct `fromLTRB` combinations; gutters of 12, 16, 24 and 32.
- Hard-coded colours outside the theme in radio link states, packs, sign-in, profile, friends map, QR backgrounds, stats and wrapped cards, recap playback, standings, tier chip, event text.

## 4. Motion and feedback

Animations: the PTT button (120 ms), the recap route playback, map camera fits. Nothing else: no Hero, no transitions, no count-ups, no ring sweep, no confetti. Haptics in two places (crash, radio). 41 snackbars, 25 dialogs, 20 sheets, one MaterialBanner; no snackbar Undo anywhere; one Dismissible. Destructive actions without confirm or undo: parking Forget, tracking off, pack remove, duel cancel, request decline. Pull-to-refresh missing on Drive, Garage, Badges, Seasons, Convoy detail, Stops. Missing celebrations: trip scored (only a local notification), badge earned, league promotion (silent badge), duel won, challenge met, streaks, convoy arrival, sign-in success.

## 5. First run

No onboarding, welcome or permission priming. Drive, signed out, no trips: a grey map notice, a three-bullet permission card whose "Allow" fires every OS prompt in a row, and "No trips yet… Or simulate one from the menu." Social tabs show sign-in gates; icons that lead to more gates remain. Garage is usable. No-cloud builds show "Offline build" text everywhere.

## 6. Driving context

Screens looked at while driving: Drive live card, convoy detail, radio, stops, chat, friend sheet, crash countdown. The live card's secondary text is 12–16 sp and "End now" is a 40 dp TextButton top-right of a card that sits under a map in a scroll list. Convoy entry points are ~32 dp chips; member rows are dense with long 12 sp subtitles. Radio is two pushes away and needs "Start radio" every time. Stops vote buttons are ~40 dp with 12 sp counts. The crash countdown is the model to copy.

## Top 15 problems and the smallest fix

1. Developer and build strings shown to users → a friendly-copy layer; build detail stays in Diagnostics.
2. Raw exceptions in the UI → one `friendlyError()` helper.
3. Dev tools in the home overflow and the empty state → gate behind debug or a hidden toggle; "Go for a drive. We'll score it when you park."
4. Profile, Stats, Wrapped buried → avatar button on Drive opens Profile; Settings lives on Profile.
5. Drive not map-first while driving → live block first, big, with a 56 px End drive.
6. No celebration when a trip scores → the moment sheet with the ring sweep, XP, share, haptic.
7. Badge, promotion, duel, challenge wins silent → reuse the moment.
8. No first-run or permission priming → three-page first launch, one permission per page.
9. Radio too far away in a convoy → full-width 64 px Radio button on convoy detail; the rest under More.
10. Five avatars, four score renderings → one Avatar, one ScoreRing use.
11. Eight stat tiles, six section headers, forty paddings → StatTile, Kicker/EditorialSection, tokens.
12. Wordy empty states without an action → EmptyState with one button.
13. Jargon and unit leaks → plain words, user units everywhere.
14. In-car touch targets below spec → 48 minimum, 64 on driving screens, inline leader accept.
15. Inconsistent navigation and destructive patterns → push not go, hoist FABs, one requests icon, Undo snackbars.
