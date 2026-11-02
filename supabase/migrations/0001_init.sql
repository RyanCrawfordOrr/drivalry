-- Drivalry — initial schema
-- Postgres 15+ with PostGIS. Designed for Supabase (auth.users, RLS, Realtime).
-- Units: metres, seconds, m/s. Positions are geography(Point, 4326).

create extension if not exists postgis;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type share_level as enum ('precise', 'neighborhood', 'driving_only', 'ghost');
create type road_class as enum ('motorway','trunk','primary','secondary','tertiary','residential','service','unclassified','unknown');
create type event_kind as enum ('speeding','harsh_brake','harsh_accel','hard_corner','phone_handling','idling','high_speed_cruise');
create type severity as enum ('minor','moderate','major','severe','reckless');
create type intensity as enum ('gentle','sassy','savage');
create type league_tier as enum ('learner','bronze','silver','gold','platinum','diamond','chauffeur');
create type convoy_status as enum ('planning','active','ended');
create type stop_category as enum ('gas','food','restroom','photo','lodging','other');

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  handle text unique not null check (handle ~ '^[a-z0-9_]{3,20}$'),
  display_name text not null,
  avatar_url text,
  units text not null default 'mph' check (units in ('mph','kmh')),
  roast_intensity intensity not null default 'sassy',
  live_cues boolean not null default false,
  driver_rating numeric(5,2),            -- rolling 30-day weighted average, null until 5 trips
  tier league_tier not null default 'learner',
  clean_streak int not null default 0,
  phone_free_streak_days int not null default 0,
  is_pro boolean not null default false,
  created_at timestamptz not null default now()
);

create table vehicles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  make text, model text, year int,
  bluetooth_names text[] not null default '{}',
  never_track boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Circles (Life360-style groups) and places
-- ---------------------------------------------------------------------------
create table circles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references profiles(id),
  mean_mode boolean not null default false,
  invite_code text unique not null default encode(gen_random_bytes(6), 'hex'),
  created_at timestamptz not null default now()
);

create table circle_members (
  circle_id uuid not null references circles(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  share_level share_level not null default 'driving_only',
  mean_mode_opt_in boolean not null default false,
  show_trip_scores boolean not null default true,
  show_trip_routes boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);

create table places (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  label text not null,                   -- Home, Work, Gym
  location geography(point, 4326) not null,
  radius_m int not null default 150,
  created_at timestamptz not null default now()
);

create table place_alerts (
  place_id uuid not null references places(id) on delete cascade,
  watcher_id uuid not null references profiles(id) on delete cascade,  -- who gets notified
  on_arrive boolean not null default true,
  on_leave boolean not null default false,
  primary key (place_id, watcher_id)
);

-- One row per user: latest position only. Coarsened column is derived server-side.
create table presence (
  user_id uuid primary key references profiles(id) on delete cascade,
  location geography(point, 4326),
  coarse_location geography(point, 4326),  -- snapped to ~1 km grid
  speed_mps real,
  heading_deg real,
  is_driving boolean not null default false,
  active_trip_id uuid,
  battery_pct smallint,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Trips
-- ---------------------------------------------------------------------------
create table trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  vehicle_id uuid references vehicles(id) on delete set null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  start_location geography(point, 4326) not null,
  end_location geography(point, 4326) not null,
  start_label text, end_label text,      -- "Home", "Work", reverse-geocoded otherwise
  distance_m real not null,
  moving_time_s real not null,
  total_time_s real not null,
  max_speed_mps real not null,
  night_fraction real not null default 0,
  weather text check (weather in ('clear','rain','snow')),
  is_passenger boolean not null default false,
  route geography(linestring, 4326),      -- map-matched polyline
  processed_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index trips_user_started on trips(user_id, started_at desc);
create index trips_route_gix on trips using gist(route);

-- Raw 1 Hz samples, compressed per trip. Short retention (see docs/05).
create table trip_samples (
  trip_id uuid primary key references trips(id) on delete cascade,
  -- delta-encoded int arrays: t (ms), lat/lon (1e-6 deg), speed (cm/s), accuracy (m), heading (deg)
  payload bytea not null,
  sample_count int not null,
  expires_at timestamptz not null default now() + interval '30 days'
);

create table trip_segments (
  id bigserial primary key,
  trip_id uuid not null references trips(id) on delete cascade,
  from_idx int not null, to_idx int not null,
  osm_way_id bigint,
  road_name text,
  road_class road_class not null default 'unknown',
  speed_limit_mps real,                   -- null = unknown
  limit_confidence real not null default 0 check (limit_confidence between 0 and 1),
  limit_source text,                      -- 'osm','tomtom','here','default'
  geom geography(linestring, 4326)
);
create index trip_segments_trip on trip_segments(trip_id);

create table trip_events (
  id bigserial primary key,
  trip_id uuid not null references trips(id) on delete cascade,
  kind event_kind not null,
  severity severity not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_s real not null,
  location geography(point, 4326) not null,
  detail jsonb not null default '{}',     -- SpeedingDetail / MotionDetail / PhoneDetail ...
  is_observation boolean not null default false  -- low-confidence speeding: shown, not scored
);
create index trip_events_trip on trip_events(trip_id);

create table trip_scores (
  trip_id uuid primary key references trips(id) on delete cascade,
  scored boolean not null,
  unscored_reason text check (unscored_reason in ('too_short','passenger')),
  score smallint not null check (score between 0 and 100),
  speed_penalty real not null, smoothness_penalty real not null,
  attention_penalty real not null, efficiency_penalty real not null,
  reckless boolean not null default false,
  flags text[] not null default '{}',
  xp int not null default 0,
  seconds_over_limit real not null default 0,
  seconds_known_limit real not null default 0,
  time_saved_by_speeding_s real not null default 0,
  headline text not null,
  lines text[] not null default '{}',
  engine_version text not null,
  scored_at timestamptz not null default now()
);

create table speed_limit_flags (
  id bigserial primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  osm_way_id bigint not null,
  reported_limit_mps real,
  trip_event_id bigint references trip_events(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, osm_way_id)
);

-- ---------------------------------------------------------------------------
-- Leagues
-- ---------------------------------------------------------------------------
create table leagues (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null check (kind in ('friends','global')),
  created_by uuid references profiles(id),
  mean_mode boolean not null default false,
  invite_code text unique default encode(gen_random_bytes(6), 'hex'),
  created_at timestamptz not null default now()
);

create table league_members (
  league_id uuid not null references leagues(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  tier league_tier not null default 'learner',
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);

-- One row per member per ISO week; xp is incremented by the trip processor.
create table league_weeks (
  league_id uuid not null references leagues(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  week_start date not null,              -- Monday, user-local
  xp int not null default 0,
  trips int not null default 0,
  reckless_trips int not null default 0,
  final_rank int,
  outcome text check (outcome in ('promoted','stayed','demoted')),
  primary key (league_id, user_id, week_start)
);

create table duels (
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references profiles(id),
  opponent_id uuid not null references profiles(id),
  metric text not null check (metric in ('xp','avg_score','phone_free_trips')),
  week_start date not null,
  winner_id uuid references profiles(id),
  loser_badge text,
  accepted boolean not null default false
);

-- ---------------------------------------------------------------------------
-- Badges
-- ---------------------------------------------------------------------------
create table badges (
  key text primary key,                   -- 'smooth_operator', 'lead_foot'
  name text not null,
  description text not null,
  dishonorable boolean not null default false,
  tiers int not null default 1
);

create table user_badges (
  user_id uuid not null references profiles(id) on delete cascade,
  badge_key text not null references badges(key),
  tier int not null default 1,
  earned_at timestamptz not null default now(),
  expires_at timestamptz,                 -- dishonorable badges show for 7 days
  primary key (user_id, badge_key, tier)
);

-- ---------------------------------------------------------------------------
-- Convoys
-- ---------------------------------------------------------------------------
create table convoys (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  leader_id uuid not null references profiles(id),
  status convoy_status not null default 'planning',
  destination geography(point, 4326),
  destination_label text,
  invite_code text unique not null default encode(gen_random_bytes(4), 'hex'),
  livekit_room text,
  started_at timestamptz, ended_at timestamptz,
  created_at timestamptz not null default now()
);

create table convoy_members (
  convoy_id uuid not null references convoys(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  vehicle_id uuid references vehicles(id),
  role text not null default 'driver' check (role in ('driver','passenger')),
  joined_at timestamptz not null default now(),
  primary key (convoy_id, user_id)
);

-- High-frequency positions while a convoy is active; 30-day retention for the recap.
create table convoy_positions (
  convoy_id uuid not null references convoys(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  at timestamptz not null,
  location geography(point, 4326) not null,
  speed_mps real,
  primary key (convoy_id, user_id, at)
);

create table convoy_stops (
  id uuid primary key default gen_random_uuid(),
  convoy_id uuid not null references convoys(id) on delete cascade,
  proposed_by uuid not null references profiles(id),
  category stop_category not null,
  name text not null,
  location geography(point, 4326) not null,
  google_place_id text,
  detour_s int,
  status text not null default 'proposed' check (status in ('proposed','accepted','rejected','visited')),
  created_at timestamptz not null default now()
);

create table convoy_stop_votes (
  stop_id uuid not null references convoy_stops(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  vote smallint not null check (vote in (-1, 1)),
  primary key (stop_id, user_id)
);

create table convoy_expenses (
  id uuid primary key default gen_random_uuid(),
  convoy_id uuid not null references convoys(id) on delete cascade,
  paid_by uuid not null references profiles(id),
  category text not null check (category in ('gas','toll','food','lodging','other')),
  amount_cents int not null check (amount_cents > 0),
  currency char(3) not null default 'USD',
  split_with uuid[] not null,
  note text,
  created_at timestamptz not null default now()
);

create table convoy_photos (
  id uuid primary key default gen_random_uuid(),
  convoy_id uuid not null references convoys(id) on delete cascade,
  user_id uuid not null references profiles(id),
  storage_path text not null,
  taken_at timestamptz not null,
  location geography(point, 4326),
  stop_id uuid references convoy_stops(id)
);

-- ---------------------------------------------------------------------------
-- Feed
-- ---------------------------------------------------------------------------
create table feed_posts (
  id uuid primary key default gen_random_uuid(),
  scope_kind text not null check (scope_kind in ('circle','league')),
  scope_id uuid not null,
  author_id uuid references profiles(id) on delete set null,
  kind text not null check (kind in ('trip','badge','league_result','wall_of_shame','convoy_recap','duel')),
  ref_id uuid,
  body text,
  created_at timestamptz not null default now()
);
create index feed_scope on feed_posts(scope_kind, scope_id, created_at desc);

create table feed_reactions (
  post_id uuid not null references feed_posts(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  emoji text not null,
  primary key (post_id, user_id, emoji)
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- True when the two users share at least one circle.
create or replace function shares_circle(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from circle_members x join circle_members y on x.circle_id = y.circle_id
    where x.user_id = a and y.user_id = b
  );
$$;

-- The most permissive share level `viewer` has from `subject` across shared circles.
create or replace function share_level_for(viewer uuid, subject uuid) returns share_level
language sql stable security definer set search_path = public as $$
  select coalesce((
    select s.share_level
    from circle_members s join circle_members v on s.circle_id = v.circle_id
    where s.user_id = subject and v.user_id = viewer
    order by array_position(array['precise','neighborhood','driving_only','ghost']::share_level[], s.share_level)
    limit 1
  ), 'ghost');
$$;

-- What a viewer may see of everyone who shares a circle with them.
create or replace view visible_presence as
select
  p.user_id,
  share_level_for(auth.uid(), p.user_id) as level,
  case share_level_for(auth.uid(), p.user_id)
    when 'precise' then p.location
    when 'neighborhood' then p.coarse_location
    when 'driving_only' then case when p.is_driving then p.location end
    else null
  end as location,
  p.is_driving, p.speed_mps, p.heading_deg, p.battery_pct, p.updated_at
from presence p
where p.user_id <> auth.uid() and share_level_for(auth.uid(), p.user_id) <> 'ghost';

-- Coarsen presence on write.
create or replace function presence_coarsen() returns trigger language plpgsql as $$
begin
  if new.location is not null then
    new.coarse_location := st_snaptogrid(new.location::geometry, 0.01)::geography; -- ~1 km
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger presence_coarsen_trg before insert or update on presence
for each row execute function presence_coarsen();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table profiles enable row level security;
alter table vehicles enable row level security;
alter table circles enable row level security;
alter table circle_members enable row level security;
alter table places enable row level security;
alter table place_alerts enable row level security;
alter table presence enable row level security;
alter table trips enable row level security;
alter table trip_samples enable row level security;
alter table trip_segments enable row level security;
alter table trip_events enable row level security;
alter table trip_scores enable row level security;
alter table speed_limit_flags enable row level security;
alter table leagues enable row level security;
alter table league_members enable row level security;
alter table league_weeks enable row level security;
alter table duels enable row level security;
alter table badges enable row level security;
alter table user_badges enable row level security;
alter table convoys enable row level security;
alter table convoy_members enable row level security;
alter table convoy_positions enable row level security;
alter table convoy_stops enable row level security;
alter table convoy_stop_votes enable row level security;
alter table convoy_expenses enable row level security;
alter table convoy_photos enable row level security;
alter table feed_posts enable row level security;
alter table feed_reactions enable row level security;

-- Profiles: read anyone you share a circle or league with; write only yourself.
create policy profiles_read on profiles for select using (
  id = auth.uid() or shares_circle(auth.uid(), id)
  or exists (select 1 from league_members a join league_members b on a.league_id = b.league_id
             where a.user_id = auth.uid() and b.user_id = profiles.id)
);
create policy profiles_write on profiles for all using (id = auth.uid()) with check (id = auth.uid());

create policy vehicles_own on vehicles for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy circles_member_read on circles for select using (
  exists (select 1 from circle_members m where m.circle_id = circles.id and m.user_id = auth.uid())
);
create policy circles_create on circles for insert with check (created_by = auth.uid());
create policy circles_update on circles for update using (created_by = auth.uid());

create policy circle_members_read on circle_members for select using (
  exists (select 1 from circle_members m where m.circle_id = circle_members.circle_id and m.user_id = auth.uid())
);
create policy circle_members_self on circle_members for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy places_own on places for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy place_alerts_rw on place_alerts for all using (
  watcher_id = auth.uid() or exists (select 1 from places p where p.id = place_id and p.owner_id = auth.uid())
);

-- Presence: write your own row; read through the visible_presence view only.
create policy presence_self on presence for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Trips: owner has full access; circle members with show_trip_scores may read summaries.
create policy trips_owner on trips for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy trips_circle_read on trips for select using (
  deleted_at is null and exists (
    select 1 from circle_members s join circle_members v on s.circle_id = v.circle_id
    where s.user_id = trips.user_id and v.user_id = auth.uid() and s.show_trip_scores
  )
);
create policy trip_samples_owner on trip_samples for all using (
  exists (select 1 from trips t where t.id = trip_id and t.user_id = auth.uid())
);
create policy trip_segments_read on trip_segments for select using (
  exists (select 1 from trips t where t.id = trip_id and (t.user_id = auth.uid()
    or exists (select 1 from circle_members s join circle_members v on s.circle_id = v.circle_id
               where s.user_id = t.user_id and v.user_id = auth.uid() and s.show_trip_routes)))
);
create policy trip_events_read on trip_events for select using (
  exists (select 1 from trips t where t.id = trip_id and (t.user_id = auth.uid()
    or exists (select 1 from circle_members s join circle_members v on s.circle_id = v.circle_id
               where s.user_id = t.user_id and v.user_id = auth.uid() and s.show_trip_scores)))
);
create policy trip_scores_read on trip_scores for select using (
  exists (select 1 from trips t where t.id = trip_id and (t.user_id = auth.uid()
    or exists (select 1 from circle_members s join circle_members v on s.circle_id = v.circle_id
               where s.user_id = t.user_id and v.user_id = auth.uid() and s.show_trip_scores)))
);
-- Segments, events and scores are written by the trip processor using the service role.

create policy speed_limit_flags_own on speed_limit_flags for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy leagues_member_read on leagues for select using (
  exists (select 1 from league_members m where m.league_id = leagues.id and m.user_id = auth.uid())
);
create policy leagues_create on leagues for insert with check (created_by = auth.uid());
create policy league_members_read on league_members for select using (
  exists (select 1 from league_members m where m.league_id = league_members.league_id and m.user_id = auth.uid())
);
create policy league_members_self on league_members for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy league_weeks_read on league_weeks for select using (
  exists (select 1 from league_members m where m.league_id = league_weeks.league_id and m.user_id = auth.uid())
);
create policy duels_parties on duels for all using (challenger_id = auth.uid() or opponent_id = auth.uid());

create policy badges_public on badges for select using (true);
create policy user_badges_read on user_badges for select using (
  user_id = auth.uid() or shares_circle(auth.uid(), user_id)
);

create policy convoys_member on convoys for select using (
  exists (select 1 from convoy_members m where m.convoy_id = convoys.id and m.user_id = auth.uid())
);
create policy convoys_create on convoys for insert with check (leader_id = auth.uid());
create policy convoys_leader_update on convoys for update using (leader_id = auth.uid());
create policy convoy_members_read on convoy_members for select using (
  exists (select 1 from convoy_members m where m.convoy_id = convoy_members.convoy_id and m.user_id = auth.uid())
);
create policy convoy_members_self on convoy_members for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy convoy_positions_member on convoy_positions for select using (
  exists (select 1 from convoy_members m where m.convoy_id = convoy_positions.convoy_id and m.user_id = auth.uid())
);
create policy convoy_positions_self on convoy_positions for insert with check (user_id = auth.uid());
create policy convoy_stops_member on convoy_stops for all using (
  exists (select 1 from convoy_members m where m.convoy_id = convoy_stops.convoy_id and m.user_id = auth.uid())
);
create policy convoy_stop_votes_member on convoy_stop_votes for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy convoy_expenses_member on convoy_expenses for all using (
  exists (select 1 from convoy_members m where m.convoy_id = convoy_expenses.convoy_id and m.user_id = auth.uid())
);
create policy convoy_photos_member on convoy_photos for all using (
  exists (select 1 from convoy_members m where m.convoy_id = convoy_photos.convoy_id and m.user_id = auth.uid())
);

create policy feed_read on feed_posts for select using (
  (scope_kind = 'circle' and exists (select 1 from circle_members m where m.circle_id = scope_id and m.user_id = auth.uid()))
  or (scope_kind = 'league' and exists (select 1 from league_members m where m.league_id = scope_id and m.user_id = auth.uid()))
);
create policy feed_reactions_rw on feed_reactions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Seed badges
-- ---------------------------------------------------------------------------
insert into badges (key, name, description, dishonorable, tiers) values
  ('smooth_operator', 'Smooth Operator', 'Trips with zero smoothness events', false, 3),
  ('zen_master', 'Zen Master', '25 consecutive trips scoring 90+', false, 1),
  ('phone_down', 'Phone Down', 'Days with zero phone-handling events', false, 3),
  ('grandma_mode', 'Grandma Mode', 'A 20 km+ trip with zero events', false, 1),
  ('rain_dancer', 'Rain Dancer', '10 trips in rain scoring 85+', false, 1),
  ('night_shift', 'Night Shift', '10 night trips scoring 85+', false, 1),
  ('reformed', 'Reformed', 'Driver Rating up 15+ points in 30 days', false, 1),
  ('hypermiler', 'Hypermiler', '10 trips over 30 km with zero efficiency penalty', false, 1),
  ('state_collector', 'State Collector', 'States or provinces visited', false, 3),
  ('county_line', 'County Line', 'Counties visited', false, 3),
  ('century_club', 'Century Club', 'A single trip of 100+ miles scored 70+', false, 1),
  ('summit', 'Summit', 'Altitude reached on a trip', false, 3),
  ('far_from_home', 'Far From Home', 'Distance from home', false, 3),
  ('groundhog', 'Groundhog', 'Same route 50 times', false, 1),
  ('convoy_captain', 'Convoy Captain', 'Convoys led', false, 3),
  ('road_trip_legend', 'Road Trip Legend', 'A convoy of 500+ miles', false, 1),
  ('wingman', 'Wingman', 'Passenger on 10 friends'' trips', false, 1),
  ('clean_crew', 'Clean Crew', 'Circle completed a group challenge', false, 1),
  ('snitch', 'Snitch', '10 confirmed speed-limit corrections', false, 1),
  ('lead_foot', 'Lead Foot', 'A reckless trip', true, 1),
  ('butterfingers', 'Butterfingers', '5 phone-handling episodes in a week', true, 1),
  ('whack_a_mole', 'Whack-a-Mole', '10 harsh brakes in one trip', true, 1),
  ('sunday_driver', 'Sunday Driver', 'Lost a duel', true, 1);
