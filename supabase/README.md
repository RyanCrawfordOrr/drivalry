# Supabase

Free-tier project `drivalry`. Holds accounts, handles, friends, leagues, trip
summaries, the public roast feed, coarse presence, circles, convoy signaling
and the shared speed-limit cache. It never holds raw GPS.

`migrations/0001_init.sql` was written before the local-first decision and
still contains `trip_samples` and `trip_segments`. It is revised, trimmed to
summaries only, and applied in the friends-and-leagues stage. Only `migrations/0000_heartbeat.sql` is meant to be applied now (paste it into
the SQL editor); the rest of the schema is not applied to the live project yet. Keep-alive: `.github/workflows/supabase-keepalive.yml`.
