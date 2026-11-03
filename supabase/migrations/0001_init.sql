-- Drivalry: cloud schema (summaries only). Rewritten 2026-11-02 for the local-first
-- architecture in docs/03-architecture.md §8. Nothing in here holds a route, a GPS
-- sample, or a start/end place. Phones upload trip summaries and events with road
-- names; everything social is derived from those.
--
-- Apply after 0000_heartbeat.sql in the Supabase SQL editor. Postgres 15+.
-- Units: metres, seconds, m/s. Timestamps are timestamptz.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type league_tier as enum ('learner','bronze','silver','gold','platinum','diamond','chauffeur');
create type league_kind as enum ('friend','global');
create type friendship_status as enum ('pending','accepted','blocked');
create type post_kind as enum ('trip','badge','league','convoy','shame');
create type convoy_status as enum ('planning','active','ended');
create type convoy_role as enum ('leader','member');
create type stop_status as enum ('proposed','accepted','rejected','done');
create type push_platform as enum ('ios','android');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- A short, URL-safe invite code.
create or replace function gen_invite_code() returns text
language sql volatile as $$
  select lower(encode(gen_random_bytes(4), 'hex'))
$$;

-- ---------------------------------------------------------------------------
-- Profiles (one per auth user; created by trigger)
-- ---------------------------------------------------------------------------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  handle text unique not null check (handle ~ '^[a-z0-9_]{3,20}$'),
  display_name text not null check (char_length(display_name) between 1 and 40),
  avatar_path text,                               -- storage object path in bucket `avatars`
  units text not null default 'auto' check (units in ('auto','mph','kmh')),
  driver_rating numeric(5,2),                     -- rolling 30-day weighted average, null until 5 scored trips
  passenger_marked_count int not null default 0,  -- visible to groups; honor system
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger profiles_updated before update on profiles for each row execute function set_updated_at();

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  base text;
  candidate text;
  n int := 0;
begin
  base := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'preferred_username',
                                          new.raw_user_meta_data->>'name',
                                          split_part(new.email, '@', 1),
                                          'driver'), '[^a-z0-9_]', '', 'g'));
  if char_length(base) < 3 then base := 'driver'; end if;
  base := left(base, 14);
  candidate := base;
  while exists (select 1 from profiles where handle = candidate) loop
    n := n + 1;
    candidate := base || '_' || to_char(floor(random() * 9000 + 1000)::int, 'FM0000');
    exit when n > 20;
  end loop;
  insert into profiles (id, handle, display_name)
  values (new.id, candidate, coalesce(new.raw_user_meta_data->>'full_name',
                                      new.raw_user_meta_data->>'name',
                                      candidate));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- Friendships
-- ---------------------------------------------------------------------------
create table friendships (
  requester_id uuid not null references profiles(id) on delete cascade,
  addressee_id uuid not null references profiles(id) on delete cascade,
  status friendship_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create index friendships_addressee on friendships (addressee_id, status);

create or replace function are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  )
$$;

-- ---------------------------------------------------------------------------
-- Leagues
-- ---------------------------------------------------------------------------
create table leagues (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  kind league_kind not null default 'friend',
  created_by uuid not null references profiles(id) on delete cascade,
  invite_code text unique not null default gen_invite_code(),
  max_members int not null default 30 check (max_members between 2 and 30),
  created_at timestamptz not null default now()
);

create table league_members (
  league_id uuid not null references leagues(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  tier league_tier not null default 'learner',
  hiding boolean not null default false,          -- visible to the whole league
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
create index league_members_user on league_members (user_id);

create table league_weeks (
  league_id uuid not null references leagues(id) on delete cascade,
  week_start date not null,                       -- the member's local Monday, as sent by the phone
  standings jsonb not null,                       -- [{user_id, xp, trips, rating, rank, tier_before, tier_after}]
  finalized_at timestamptz not null default now(),
  primary key (league_id, week_start)
);

-- ---------------------------------------------------------------------------
-- Circles (Life360 layer)
-- ---------------------------------------------------------------------------
create table circles (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  created_by uuid not null references profiles(id) on delete cascade,
  invite_code text unique not null default gen_invite_code(),
  created_at timestamptz not null default now()
);

create table circle_members (
  circle_id uuid not null references circles(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  hiding boolean not null default false,          -- no presence, no posts to this circle; the circle sees the flag
  joined_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);
create index circle_members_user on circle_members (user_id);

-- Shared-group visibility: can the caller see `author`'s trips, posts and badges?
-- True for yourself, and for anyone you share a league or circle with where they
-- are not hiding in that group.
create or replace function can_view(author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select author = auth.uid()
     or exists (select 1 from league_members a join league_members b using (league_id)
                 where a.user_id = auth.uid() and b.user_id = author and b.hiding = false)
     or exists (select 1 from circle_members a join circle_members b using (circle_id)
                 where a.user_id = auth.uid() and b.user_id = author and b.hiding = false)
$$;

create or replace function shares_league(l uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from league_members where league_id = l and user_id = auth.uid())
$$;

create or replace function shares_circle(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from circle_members where circle_id = c and user_id = auth.uid())
$$;

-- ---------------------------------------------------------------------------
-- Trip summaries and events (docs/03 §3.6). No coordinates anywhere.
-- ---------------------------------------------------------------------------
create table trip_summaries (
  id uuid primary key,                            -- client-generated; uploads are idempotent
  user_id uuid not null references profiles(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  distance_m int not null check (distance_m >= 0),
  moving_s int not null check (moving_s >= 0),
  scored boolean not null,
  unscored_reason text,
  score smallint check (score between 0 and 100),
  components jsonb,                               -- {speed, smoothness, attention, efficiency}
  reckless boolean not null default false,
  xp int not null default 0 check (xp >= 0),
  credited_km numeric(6,2) not null default 0,
  is_passenger boolean not null default false,
  vehicle_label text,
  pack_region text,
  pack_version text,
  limit_coverage real check (limit_coverage between 0 and 1),
  night_fraction real check (night_fraction between 0 and 1),
  weather text check (weather in ('clear','rain','snow')),
  roast jsonb,                                    -- {templateId, slots, text, tone}
  created_at timestamptz not null default now(),
  check (ended_at >= started_at)
);
create index trip_summaries_user_time on trip_summaries (user_id, started_at desc);

create table trip_events (
  id bigint generated always as identity primary key,
  trip_id uuid not null references trip_summaries(id) on delete cascade,
  kind text not null,                             -- speeding | harsh_brake | harsh_accel | hard_corner | phone_handling | idling | high_speed_cruise
  severity text,                                  -- minor | moderate | major | severe | reckless
  offset_s int not null check (offset_s >= 0),
  duration_s int not null default 0 check (duration_s >= 0),
  over_mps real,
  road_name text,
  way_id bigint
);
create index trip_events_trip on trip_events (trip_id);

-- ---------------------------------------------------------------------------
-- Feed
-- ---------------------------------------------------------------------------
create table feed_posts (
  id uuid primary key,                            -- client-generated
  author_id uuid not null references profiles(id) on delete cascade,
  kind post_kind not null,
  trip_id uuid references trip_summaries(id) on delete cascade,
  body jsonb not null default '{}'::jsonb,        -- trip: {score, roast}; badge: {badge_id}; league: {league_id, week_start, rank}; ...
  created_at timestamptz not null default now()
);
create index feed_posts_author_time on feed_posts (author_id, created_at desc);
create index feed_posts_time on feed_posts (created_at desc);

create table feed_reactions (
  post_id uuid not null references feed_posts(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  kind text not null check (kind in ('fire','clap','laugh','skull','clown','snitch')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id, kind)
);

create table feed_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references feed_posts(id) on delete cascade,
  author_id uuid not null references profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 280),
  created_at timestamptz not null default now()
);
create index feed_comments_post on feed_comments (post_id, created_at);

-- ---------------------------------------------------------------------------
-- Badges
-- ---------------------------------------------------------------------------
create table badges (
  id text primary key,                            -- e.g. 'first_trip', 'clean_streak_5'
  name text not null,
  description text not null,
  category text not null                          -- safety | exploration | social | season | shame
);

create table user_badges (
  user_id uuid not null references profiles(id) on delete cascade,
  badge_id text not null references badges(id) on delete cascade,
  awarded_at timestamptz not null default now(),
  expires_at timestamptz,                         -- duel loser badges last 7 days
  primary key (user_id, badge_id)
);

-- ---------------------------------------------------------------------------
-- Presence (one row per user, overwritten) and crash alerts
-- ---------------------------------------------------------------------------
create table presence (
  user_id uuid primary key references profiles(id) on delete cascade,
  lat double precision not null,
  lon double precision not null,
  speed real,
  heading real,
  battery real check (battery between 0 and 1),
  driving boolean not null default false,
  updated_at timestamptz not null default now()
);

create table crash_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  lat double precision not null,
  lon double precision not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index crash_alerts_time on crash_alerts (created_at desc);

-- ---------------------------------------------------------------------------
-- Convoys
-- ---------------------------------------------------------------------------
create table convoys (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  created_by uuid not null references profiles(id) on delete cascade,
  status convoy_status not null default 'planning',
  destination jsonb,                              -- {name, lat, lon, placeId}
  invite_code text unique not null default gen_invite_code(),
  max_cars int not null default 6 check (max_cars between 2 and 6),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz
);

create table convoy_members (
  convoy_id uuid not null references convoys(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role convoy_role not null default 'member',
  car_label text,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (convoy_id, user_id)
);

create table convoy_stops (
  id uuid primary key default gen_random_uuid(),
  convoy_id uuid not null references convoys(id) on delete cascade,
  proposed_by uuid not null references profiles(id) on delete cascade,
  category text not null check (category in ('gas','food','restroom','photo','lodging','charging','other')),
  name text not null,
  lat double precision not null,
  lon double precision not null,
  place_id text,
  status stop_status not null default 'proposed',
  created_at timestamptz not null default now()
);
create index convoy_stops_convoy on convoy_stops (convoy_id, created_at);

create table convoy_stop_votes (
  stop_id uuid not null references convoy_stops(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  vote smallint not null check (vote in (-1, 1)),
  created_at timestamptz not null default now(),
  primary key (stop_id, user_id)
);

create table convoy_expenses (
  id uuid primary key default gen_random_uuid(),
  convoy_id uuid not null references convoys(id) on delete cascade,
  payer_id uuid not null references profiles(id) on delete cascade,
  amount_cents int not null check (amount_cents > 0),
  currency char(3) not null default 'USD',
  category text not null check (category in ('gas','tolls','food','lodging','other')),
  note text check (char_length(note) <= 140),
  created_at timestamptz not null default now()
);

create table convoy_photos (
  id uuid primary key default gen_random_uuid(),
  convoy_id uuid not null references convoys(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  stop_id uuid references convoy_stops(id) on delete set null,
  storage_path text not null,                     -- bucket `convoy-photos`
  taken_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Shared speed-limit corrections (docs/03 §4.4)
-- ---------------------------------------------------------------------------
create table speed_limit_flags (
  id bigint generated always as identity primary key,
  way_id bigint not null,
  region text not null,
  suggested_value int not null check (suggested_value between 5 and 160),
  suggested_mph boolean not null,
  suggested_mps real not null,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (way_id, user_id)
);
create index speed_limit_flags_way on speed_limit_flags (way_id);

create table speed_limit_overrides (
  way_id bigint primary key,
  region text not null,
  limit_value int not null,
  limit_mph boolean not null,
  limit_mps real not null,
  confidence real not null default 0.85,
  flag_count int not null default 2,
  updated_at timestamptz not null default now()
);
create index speed_limit_overrides_region on speed_limit_overrides (region, updated_at);

-- Two distinct users flagging the same way with the same value create or refresh an override.
create or replace function apply_speed_limit_flag() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  agreeing int;
begin
  select count(distinct user_id) into agreeing
  from speed_limit_flags
  where way_id = new.way_id
    and suggested_mph = new.suggested_mph
    and suggested_value = new.suggested_value;
  if agreeing >= 2 then
    insert into speed_limit_overrides (way_id, region, limit_value, limit_mph, limit_mps, flag_count, updated_at)
    values (new.way_id, new.region, new.suggested_value, new.suggested_mph, new.suggested_mps, agreeing, now())
    on conflict (way_id) do update
      set region = excluded.region,
          limit_value = excluded.limit_value,
          limit_mph = excluded.limit_mph,
          limit_mps = excluded.limit_mps,
          flag_count = excluded.flag_count,
          updated_at = now();
  end if;
  return new;
end $$;

create trigger speed_limit_flag_applied
  after insert on speed_limit_flags
  for each row execute function apply_speed_limit_flag();

-- ---------------------------------------------------------------------------
-- Push tokens
-- ---------------------------------------------------------------------------
create table push_tokens (
  token text primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  platform push_platform not null,
  device_label text,
  updated_at timestamptz not null default now()
);
create index push_tokens_user on push_tokens (user_id);

-- ---------------------------------------------------------------------------
-- Joining by invite code (security definer so the code can be checked without
-- exposing the table to non-members)
-- ---------------------------------------------------------------------------
create or replace function join_league(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  l leagues%rowtype;
  members int;
begin
  select * into l from leagues where invite_code = lower(code);
  if not found then raise exception 'invalid invite code' using errcode = 'P0001'; end if;
  select count(*) into members from league_members where league_id = l.id;
  if members >= l.max_members then raise exception 'league is full' using errcode = 'P0002'; end if;
  insert into league_members (league_id, user_id) values (l.id, auth.uid()) on conflict do nothing;
  return l.id;
end $$;

create or replace function join_circle(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  c circles%rowtype;
begin
  select * into c from circles where invite_code = lower(code);
  if not found then raise exception 'invalid invite code' using errcode = 'P0001'; end if;
  insert into circle_members (circle_id, user_id) values (c.id, auth.uid()) on conflict do nothing;
  return c.id;
end $$;

create or replace function join_convoy(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v convoys%rowtype;
  cars int;
begin
  select * into v from convoys where invite_code = lower(code) and status <> 'ended';
  if not found then raise exception 'invalid invite code' using errcode = 'P0001'; end if;
  select count(*) into cars from convoy_members where convoy_id = v.id and left_at is null;
  if cars >= v.max_cars then raise exception 'convoy is full' using errcode = 'P0002'; end if;
  insert into convoy_members (convoy_id, user_id) values (v.id, auth.uid())
    on conflict (convoy_id, user_id) do update set left_at = null;
  return v.id;
end $$;

-- ---------------------------------------------------------------------------
-- League rollover. Idempotent; any member's phone may call it after the week
-- ends; pg_cron calls it Monday 06:00 UTC as a backstop.
-- ---------------------------------------------------------------------------
create or replace function finalize_league_week(p_league_id uuid, p_week_start date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_existing jsonb;
  tiers text[] := array['learner','bronze','silver','gold','platinum','diamond','chauffeur'];
  rec record;
  total int;
  idx int;
  new_tier text;
  v_standings jsonb := '[]'::jsonb;
begin
  -- serialise per league
  perform 1 from leagues where id = p_league_id for update;
  if not found then raise exception 'unknown league'; end if;

  select w.standings into v_existing from league_weeks w where w.league_id = p_league_id and w.week_start = p_week_start;
  if v_existing is not null then return v_existing; end if;

  if p_week_start + 7 > current_date then
    raise exception 'week not over yet' using errcode = 'P0003';
  end if;

  select count(*) into total from league_members where league_id = p_league_id;

  for rec in
    select m.user_id, m.tier,
           coalesce(sum(t.xp), 0)::int as xp,
           count(t.id)::int as trips,
           p.driver_rating,
           row_number() over (order by coalesce(sum(t.xp), 0) desc, p.driver_rating desc nulls last, m.user_id) as rank
    from league_members m
    join profiles p on p.id = m.user_id
    left join trip_summaries t
      on t.user_id = m.user_id and t.scored and not t.is_passenger
     and t.started_at >= p_week_start::timestamptz
     and t.started_at <  (p_week_start + 7)::timestamptz
    where m.league_id = p_league_id
    group by m.user_id, m.tier, p.driver_rating
  loop
    idx := array_position(tiers, rec.tier::text);
    new_tier := rec.tier::text;
    if rec.trips = 0 then
      if idx > 1 then new_tier := tiers[idx - 1]; end if;                 -- did not drive: demote
    elsif rec.rank <= 5 and total > 5 and idx < array_length(tiers, 1) then
      new_tier := tiers[idx + 1];                                          -- top 5 promote
    elsif rec.rank > total - 5 and total > 5 and idx > 1 then
      new_tier := tiers[idx - 1];                                          -- bottom 5 demote
    end if;
    -- Learner floor: bottom 3 in learner cannot demote (already handled by idx > 1).
    update league_members set tier = new_tier::league_tier where league_id = p_league_id and user_id = rec.user_id;
    v_standings := v_standings || jsonb_build_object(
      'user_id', rec.user_id, 'xp', rec.xp, 'trips', rec.trips, 'rating', rec.driver_rating,
      'rank', rec.rank, 'tier_before', rec.tier, 'tier_after', new_tier);
  end loop;

  insert into league_weeks (league_id, week_start, standings) values (p_league_id, p_week_start, v_standings);
  return v_standings;
end $$;

-- Backstop: finalise last week for every league (UTC Mondays).
create or replace function finalize_all_leagues() returns void
language plpgsql security definer set search_path = public as $$
declare
  l record;
  wk date := (date_trunc('week', now() at time zone 'utc') - interval '7 days')::date;
begin
  for l in select id from leagues loop
    begin
      perform finalize_league_week(l.id, wk);
    exception when others then
      -- one bad league must not stop the rest
      raise notice 'finalize_league_week(%) failed: %', l.id, sqlerrm;
    end;
  end loop;
end $$;

-- Retention (docs/03 §10)
create or replace function prune_cloud() returns void
language sql security definer set search_path = public as $$
  delete from feed_posts where created_at < now() - interval '90 days';
  delete from crash_alerts where created_at < now() - interval '24 hours';
  delete from convoy_photos where created_at < now() - interval '30 days';
  delete from convoys where status = 'ended' and ended_at < now() - interval '30 days';
  delete from user_badges where expires_at is not null and expires_at < now();
  -- trip_events older than a year are reduced to score-only summaries
  delete from trip_events e using trip_summaries t where e.trip_id = t.id and t.started_at < now() - interval '1 year';
$$;

-- pg_cron is available on Supabase; if the extension is not enabled yet the
-- schedules are skipped and can be added later from the dashboard.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('finalize-leagues', '0 6 * * 1', 'select public.finalize_all_leagues()');
  perform cron.schedule('prune-cloud', '30 4 * * *', 'select public.prune_cloud()');
exception when others then
  raise notice 'pg_cron not available: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- Driver rating: recomputed on each summary insert (30-day, credited-km weighted)
-- ---------------------------------------------------------------------------
create or replace function refresh_driver_rating() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r numeric;
  n int;
begin
  select sum(score * greatest(credited_km, 0.5)) / nullif(sum(greatest(credited_km, 0.5)), 0), count(*)
    into r, n
  from trip_summaries
  where user_id = new.user_id and scored and not is_passenger
    and started_at >= now() - interval '30 days';
  update profiles set driver_rating = case when n >= 5 then round(r, 2) else null end where id = new.user_id;
  if new.is_passenger then
    update profiles set passenger_marked_count = passenger_marked_count + 1 where id = new.user_id;
  end if;
  return new;
end $$;

create trigger trip_summary_rating after insert on trip_summaries
  for each row execute function refresh_driver_rating();

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table profiles enable row level security;
alter table friendships enable row level security;
alter table leagues enable row level security;
alter table league_members enable row level security;
alter table league_weeks enable row level security;
alter table circles enable row level security;
alter table circle_members enable row level security;
alter table trip_summaries enable row level security;
alter table trip_events enable row level security;
alter table feed_posts enable row level security;
alter table feed_reactions enable row level security;
alter table feed_comments enable row level security;
alter table badges enable row level security;
alter table user_badges enable row level security;
alter table presence enable row level security;
alter table crash_alerts enable row level security;
alter table convoys enable row level security;
alter table convoy_members enable row level security;
alter table convoy_stops enable row level security;
alter table convoy_stop_votes enable row level security;
alter table convoy_expenses enable row level security;
alter table convoy_photos enable row level security;
alter table speed_limit_flags enable row level security;
alter table speed_limit_overrides enable row level security;
alter table push_tokens enable row level security;

-- profiles: anyone signed in can look a handle up (to add friends); only you edit yours
create policy profiles_select on profiles for select to authenticated using (true);
create policy profiles_update on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- friendships
create policy friendships_select on friendships for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy friendships_insert on friendships for insert to authenticated
  with check (requester_id = auth.uid() and status = 'pending');
create policy friendships_update on friendships for update to authenticated
  using (addressee_id = auth.uid() or requester_id = auth.uid())
  with check (addressee_id = auth.uid() or requester_id = auth.uid());
create policy friendships_delete on friendships for delete to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- leagues
create policy leagues_select on leagues for select to authenticated using (shares_league(id));
create policy leagues_insert on leagues for insert to authenticated with check (created_by = auth.uid());
create policy leagues_update on leagues for update to authenticated using (created_by = auth.uid());
create policy leagues_delete on leagues for delete to authenticated using (created_by = auth.uid());

create policy league_members_select on league_members for select to authenticated using (shares_league(league_id));
create policy league_members_insert on league_members for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from leagues where id = league_id and created_by = auth.uid()));
create policy league_members_update on league_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy league_members_delete on league_members for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from leagues where id = league_id and created_by = auth.uid()));

create policy league_weeks_select on league_weeks for select to authenticated using (shares_league(league_id));

-- circles
create policy circles_select on circles for select to authenticated using (shares_circle(id));
create policy circles_insert on circles for insert to authenticated with check (created_by = auth.uid());
create policy circles_update on circles for update to authenticated using (created_by = auth.uid());
create policy circles_delete on circles for delete to authenticated using (created_by = auth.uid());

create policy circle_members_select on circle_members for select to authenticated using (shares_circle(circle_id));
create policy circle_members_insert on circle_members for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from circles where id = circle_id and created_by = auth.uid()));
create policy circle_members_update on circle_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy circle_members_delete on circle_members for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from circles where id = circle_id and created_by = auth.uid()));

-- trips: write your own; read what your groups are allowed to see
create policy trip_summaries_select on trip_summaries for select to authenticated using (can_view(user_id));
create policy trip_summaries_insert on trip_summaries for insert to authenticated with check (user_id = auth.uid());
create policy trip_summaries_update on trip_summaries for update to authenticated using (user_id = auth.uid());
create policy trip_summaries_delete on trip_summaries for delete to authenticated using (user_id = auth.uid());

create policy trip_events_select on trip_events for select to authenticated
  using (exists (select 1 from trip_summaries t where t.id = trip_id and can_view(t.user_id)));
create policy trip_events_insert on trip_events for insert to authenticated
  with check (exists (select 1 from trip_summaries t where t.id = trip_id and t.user_id = auth.uid()));
create policy trip_events_delete on trip_events for delete to authenticated
  using (exists (select 1 from trip_summaries t where t.id = trip_id and t.user_id = auth.uid()));

-- feed
create policy feed_posts_select on feed_posts for select to authenticated using (can_view(author_id));
create policy feed_posts_insert on feed_posts for insert to authenticated with check (author_id = auth.uid());
create policy feed_posts_delete on feed_posts for delete to authenticated using (author_id = auth.uid());

create policy feed_reactions_select on feed_reactions for select to authenticated
  using (exists (select 1 from feed_posts p where p.id = post_id and can_view(p.author_id)));
create policy feed_reactions_insert on feed_reactions for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from feed_posts p where p.id = post_id and can_view(p.author_id)));
create policy feed_reactions_delete on feed_reactions for delete to authenticated using (user_id = auth.uid());

create policy feed_comments_select on feed_comments for select to authenticated
  using (exists (select 1 from feed_posts p where p.id = post_id and can_view(p.author_id)));
create policy feed_comments_insert on feed_comments for insert to authenticated
  with check (author_id = auth.uid() and exists (select 1 from feed_posts p where p.id = post_id and can_view(p.author_id)));
create policy feed_comments_delete on feed_comments for delete to authenticated
  using (author_id = auth.uid() or exists (select 1 from feed_posts p where p.id = post_id and p.author_id = auth.uid()));

-- badges
create policy badges_select on badges for select to authenticated using (true);
create policy user_badges_select on user_badges for select to authenticated using (can_view(user_id));
create policy user_badges_insert on user_badges for insert to authenticated with check (user_id = auth.uid());

-- presence: only circle members, only when not hiding in that circle
create policy presence_select on presence for select to authenticated
  using (user_id = auth.uid() or exists (
    select 1 from circle_members a join circle_members b using (circle_id)
    where a.user_id = auth.uid() and b.user_id = presence.user_id and b.hiding = false));
create policy presence_upsert on presence for insert to authenticated with check (user_id = auth.uid());
create policy presence_update on presence for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy presence_delete on presence for delete to authenticated using (user_id = auth.uid());

-- crash alerts: safety beats hiding; every circle member sees them
create policy crash_alerts_select on crash_alerts for select to authenticated
  using (user_id = auth.uid() or exists (
    select 1 from circle_members a join circle_members b using (circle_id)
    where a.user_id = auth.uid() and b.user_id = crash_alerts.user_id));
create policy crash_alerts_insert on crash_alerts for insert to authenticated with check (user_id = auth.uid());
create policy crash_alerts_update on crash_alerts for update to authenticated using (user_id = auth.uid());

-- convoys: members only
create or replace function in_convoy(v uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from convoy_members where convoy_id = v and user_id = auth.uid() and left_at is null)
$$;

create policy convoys_select on convoys for select to authenticated using (in_convoy(id) or created_by = auth.uid());
create policy convoys_insert on convoys for insert to authenticated with check (created_by = auth.uid());
create policy convoys_update on convoys for update to authenticated using (created_by = auth.uid());

create policy convoy_members_select on convoy_members for select to authenticated using (in_convoy(convoy_id));
create policy convoy_members_insert on convoy_members for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from convoys where id = convoy_id and created_by = auth.uid()));
create policy convoy_members_update on convoy_members for update to authenticated using (user_id = auth.uid());

create policy convoy_stops_select on convoy_stops for select to authenticated using (in_convoy(convoy_id));
create policy convoy_stops_insert on convoy_stops for insert to authenticated with check (proposed_by = auth.uid() and in_convoy(convoy_id));
create policy convoy_stops_update on convoy_stops for update to authenticated using (in_convoy(convoy_id));

create policy convoy_stop_votes_select on convoy_stop_votes for select to authenticated
  using (exists (select 1 from convoy_stops s where s.id = stop_id and in_convoy(s.convoy_id)));
create policy convoy_stop_votes_upsert on convoy_stop_votes for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from convoy_stops s where s.id = stop_id and in_convoy(s.convoy_id)));
create policy convoy_stop_votes_update on convoy_stop_votes for update to authenticated using (user_id = auth.uid());

create policy convoy_expenses_select on convoy_expenses for select to authenticated using (in_convoy(convoy_id));
create policy convoy_expenses_insert on convoy_expenses for insert to authenticated with check (payer_id = auth.uid() and in_convoy(convoy_id));
create policy convoy_expenses_delete on convoy_expenses for delete to authenticated using (payer_id = auth.uid());

create policy convoy_photos_select on convoy_photos for select to authenticated using (in_convoy(convoy_id));
create policy convoy_photos_insert on convoy_photos for insert to authenticated with check (user_id = auth.uid() and in_convoy(convoy_id));
create policy convoy_photos_delete on convoy_photos for delete to authenticated using (user_id = auth.uid());

-- speed limits: anyone signed in may flag; everyone reads the overrides
create policy speed_limit_flags_select on speed_limit_flags for select to authenticated using (user_id = auth.uid());
create policy speed_limit_flags_insert on speed_limit_flags for insert to authenticated with check (user_id = auth.uid());
create policy speed_limit_flags_delete on speed_limit_flags for delete to authenticated using (user_id = auth.uid());
create policy speed_limit_overrides_select on speed_limit_overrides for select to authenticated using (true);

-- push tokens
create policy push_tokens_all on push_tokens for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Realtime: Postgres Changes for the few tables a screen watches. Convoy
-- signaling and positions use Broadcast channels and need no DDL.
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table presence;
alter publication supabase_realtime add table convoy_members;
alter publication supabase_realtime add table convoy_stops;
alter publication supabase_realtime add table convoy_stop_votes;
alter publication supabase_realtime add table crash_alerts;

-- ---------------------------------------------------------------------------
-- Storage buckets: small avatars (public read) and convoy photos (members only)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 102400, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('convoy-photos', 'convoy-photos', false, 204800, array['image/jpeg','image/webp'])
on conflict (id) do nothing;

create policy avatars_read on storage.objects for select to public using (bucket_id = 'avatars');
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- convoy photo paths are <convoy_id>/<file>
create policy convoy_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'convoy-photos' and in_convoy(((storage.foldername(name))[1])::uuid));
create policy convoy_photos_write on storage.objects for insert to authenticated
  with check (bucket_id = 'convoy-photos' and in_convoy(((storage.foldername(name))[1])::uuid));
create policy convoy_photos_remove on storage.objects for delete to authenticated
  using (bucket_id = 'convoy-photos' and owner_id = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- Seed: the first badges (definitions only; awards come from phones)
-- ---------------------------------------------------------------------------
insert into badges (id, name, description, category) values
  ('first_trip',        'First Trip',        'Your first scored drive.',                                   'safety'),
  ('clean_5',           'Five Clean',        'Five scored trips in a row at 80 or better, none reckless.', 'safety'),
  ('clean_20',          'Twenty Clean',      'Twenty clean trips in a row.',                               'safety'),
  ('phone_free_10',     'Hands Off',         'Ten trips in a row without touching the phone.',             'safety'),
  ('perfect_100',       'Flawless',          'A trip scored 100.',                                         'safety'),
  ('night_owl',         'Night Owl',         'Ten night trips scored 85 or better.',                       'safety'),
  ('rain_or_shine',     'Rain or Shine',     'Five rainy trips scored 85 or better.',                      'safety'),
  ('three_states',      'Border Hopper',     'Drove in three states or provinces.',                        'exploration'),
  ('ten_states',        'Road Scholar',      'Drove in ten states or provinces.',                          'exploration'),
  ('high_altitude',     'Thin Air',          'A trip above 2,500 m.',                                      'exploration'),
  ('first_friend',      'Plus One',          'Added a friend.',                                            'social'),
  ('league_week',       'Regular',           'Finished a league week.',                                    'social'),
  ('promoted',          'Moving Up',         'Promoted at a Sunday rollover.',                             'social'),
  ('convoy_first',      'Wagon Train',       'Finished a convoy.',                                         'social'),
  ('snitch',            'Snitch',            'A speed-limit fix you flagged was confirmed.',               'social'),
  ('sunday_driver',     'Sunday Driver',     'Lost a duel. Seven days.',                                   'shame'),
  ('lead_foot',         'Lead Foot',         'Lost a duel. Seven days.',                                   'shame'),
  ('butterfingers',     'Butterfingers',     'Lost a duel. Seven days.',                                   'shame'),
  ('wall_of_shame',     'Wall of Shame',     'A reckless trip, posted to your groups.',                    'shame'),
  ('season_1',          'Season One',        'Drove through the first season.',                            'season')
on conflict (id) do nothing;
