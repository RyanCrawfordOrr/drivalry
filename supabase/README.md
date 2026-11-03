# Supabase

Free-tier project `drivalry`. Holds accounts, handles, friends, leagues, trip
summaries, the public roast feed, presence, circles, convoy state and the shared
speed-limit correction cache. It never holds raw GPS, routes or start/end places.

## Migrations

Apply in order by pasting each file into the SQL editor (Dashboard → SQL Editor → New query → Run).

| File | What | Status |
| --- | --- | --- |
| `migrations/0000_heartbeat.sql` | One-row table the daily keep-alive reads | Applied 2026-11-02 |
| `migrations/0001_init.sql` | The whole summaries-only schema: tables, RLS, `finalize_league_week`, the speed-limit override trigger, storage buckets, badge seed | Not yet applied; apply before the friends-and-leagues stage is installed on phones |
| `migrations/0002_presence_friends_account.sql` | Presence visible to accepted friends, global `location_hidden`, `delete_own_account()`, friends in `can_view` (ADR-018) | Not yet applied; apply right after 0001 |
| `migrations/0003_checkins.sql` | Feed post kind `checkin` | Not yet applied |
| `migrations/0004_crash_contacts.sql` | `crash_alerts.notify_user_ids` for emergency contacts outside your circles | Not yet applied; then redeploy `functions/push` |
| `migrations/0005_convoy_vote_withdraw.sql` | Delete policy on `convoy_stop_votes` so a member can withdraw a stop vote | Not yet applied |
| `migrations/0006_convoy_can_view.sql` | `can_view` also covers current co-members of a convoy, so the recap can read everyone's trip summaries (docs/10 §8) | Not yet applied; apply after 0001 |
| `migrations/0007_duels_challenges_seasons.sql` | Duels (`respond_duel`, `finalize_duel`, `pick_duel_badge`), group challenges (`finalize_group_challenge`), seasons + `season_results`, global leagues (`join_global_league`, `leave_global_league`, Monday `matchmake_global_leagues`), four `challenge_*` badges (docs/02 §12) | Not yet applied; apply after 0006 |

`0001_init.sql` is written to run once on a fresh project. It creates enum types and policies without `if not exists`, so re-running it fails loudly rather than half-applying. Later changes go in new numbered files that only add or alter.

All files are syntax-checked with `libpg_query` (via `pglast`, `py -m pip install pglast`) but the live project is the only place the full schema has been executed; if a statement fails in the editor, paste the error here and fix forward.

## Auth

Providers: Sign in with Apple and Google only. Email/password is turned off before the first external build. Configured in Dashboard → Authentication → Providers (needs the Apple Services ID and a Google OAuth client for bundle id `app.drivalry`; walkthrough comes with the friends stage).

## Keep-alive

`.github/workflows/supabase-keepalive.yml` runs daily, checks auth health and reads `heartbeat` through PostgREST. Needs the repo secrets `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
