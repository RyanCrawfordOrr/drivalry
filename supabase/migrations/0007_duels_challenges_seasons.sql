-- 0007: duels, group challenges, seasons, global leagues (docs/02 §12).
-- Apply after 0006.
--
-- Still summaries-only: every result here is computed from the
-- `trip_summaries` and `trip_events` rows phones already upload. Nothing
-- ranks by speed or distance: the duel metrics are XP, average Drive Score
-- and phone-free trips; the challenge goals are clean trips, phone-free
-- trips, average score and participation.

-- ---------------------------------------------------------------------------
-- Duels: one week, two friends, one metric (docs/02 §7, §12.1)
-- ---------------------------------------------------------------------------
create type duel_metric as enum ('xp','score_avg','phone_free');
create type duel_status as enum ('pending','active','declined','finished','expired');

create table duels (
  id uuid primary key,                            -- client-generated; creation is idempotent
  challenger_id uuid not null constraint duels_challenger_id_fkey references profiles(id) on delete cascade,
  opponent_id uuid not null constraint duels_opponent_id_fkey references profiles(id) on delete cascade,
  metric duel_metric not null,
  status duel_status not null default 'pending',
  created_at timestamptz not null default now(),
  starts_at timestamptz,                          -- set when the opponent accepts
  ends_at timestamptz,                            -- starts_at + 7 days
  finished_at timestamptz,
  challenger_value numeric(8,2),
  opponent_value numeric(8,2),
  challenger_trips int,
  opponent_trips int,
  winner_id uuid references profiles(id) on delete set null,   -- null while running, or a draw
  loser_badge_id text references badges(id),      -- the winner's pick; worn for seven days
  check (challenger_id <> opponent_id),
  check (starts_at is null or ends_at is null or ends_at > starts_at)
);
create index duels_challenger on duels (challenger_id, created_at desc);
create index duels_opponent on duels (opponent_id, created_at desc);

-- One driver's standing on a metric over a window. Mirrors `duelValue` in
-- the app (lib/data/repos/duels_repo.dart); keep the two in step.
--   xp          sum of XP over scored driver trips
--   score_avg   average Drive Score; under three trips it is forfeited (0)
--   phone_free  scored driver trips with no phone_handling event
-- Returns {"value": numeric, "trips": int}.
create or replace function duel_value(p_user uuid, p_metric duel_metric, p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_trips int;
  v_value numeric := 0;
begin
  select count(*)::int into v_trips
    from trip_summaries t
   where t.user_id = p_user and t.scored and not t.is_passenger
     and t.started_at >= p_from and t.started_at < p_to;
  if p_metric = 'xp' then
    select coalesce(sum(t.xp), 0) into v_value
      from trip_summaries t
     where t.user_id = p_user and t.scored and not t.is_passenger
       and t.started_at >= p_from and t.started_at < p_to;
  elsif p_metric = 'score_avg' then
    if v_trips >= 3 then
      select round(avg(t.score)::numeric, 2) into v_value
        from trip_summaries t
       where t.user_id = p_user and t.scored and not t.is_passenger
         and t.started_at >= p_from and t.started_at < p_to;
    end if;
  else
    select count(*) into v_value
      from trip_summaries t
     where t.user_id = p_user and t.scored and not t.is_passenger
       and t.started_at >= p_from and t.started_at < p_to
       and not exists (select 1 from trip_events e where e.trip_id = t.id and e.kind = 'phone_handling');
  end if;
  return jsonb_build_object('value', coalesce(v_value, 0), 'trips', v_trips);
end $$;
-- Internal: it reads other people's summaries, so phones may not call it.
revoke execute on function duel_value(uuid, duel_metric, timestamptz, timestamptz) from public, anon, authenticated;

-- The opponent answers. Accepting starts the week now. Idempotent for a
-- repeated identical answer; a different answer after the first raises P0006.
-- Returns the resulting status ('active', 'declined' or 'expired').
create or replace function respond_duel(p_duel_id uuid, p_accept boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  d duels%rowtype;
begin
  select * into d from duels where id = p_duel_id for update;
  if not found then raise exception 'unknown duel' using errcode = 'P0004'; end if;
  if d.opponent_id <> auth.uid() then raise exception 'not your duel to answer' using errcode = 'P0005'; end if;
  if d.status <> 'pending' then
    if (p_accept and d.status in ('active','finished')) or (not p_accept and d.status = 'declined') then
      return d.status::text;
    end if;
    if d.status = 'expired' then return 'expired'; end if;
    raise exception 'duel already answered' using errcode = 'P0006';
  end if;
  if d.created_at < now() - interval '7 days' then
    update duels set status = 'expired' where id = p_duel_id;
    return 'expired';
  end if;
  if p_accept then
    update duels set status = 'active', starts_at = now(), ends_at = now() + interval '7 days' where id = p_duel_id;
    return 'active';
  end if;
  update duels set status = 'declined' where id = p_duel_id;
  return 'declined';
end $$;

-- Settles a duel whose week is over. Either participant's phone may call it
-- (the daily cron is the backstop); idempotent. A tie has no winner and no
-- badge. Returns {"status","winner_id","challenger_value","opponent_value"}.
create or replace function finalize_duel(p_duel_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  d duels%rowtype;
  a jsonb;
  b jsonb;
  av numeric;
  bv numeric;
  w uuid;
begin
  select * into d from duels where id = p_duel_id for update;
  if not found then raise exception 'unknown duel' using errcode = 'P0004'; end if;
  if auth.uid() is not null and auth.uid() not in (d.challenger_id, d.opponent_id) then
    raise exception 'not your duel' using errcode = 'P0005';
  end if;
  if d.status = 'finished' then
    return jsonb_build_object('status', 'finished', 'winner_id', d.winner_id,
                              'challenger_value', d.challenger_value, 'opponent_value', d.opponent_value);
  end if;
  if d.status <> 'active' then raise exception 'duel is not running' using errcode = 'P0008'; end if;
  if d.ends_at > now() then raise exception 'duel not over yet' using errcode = 'P0003'; end if;
  a := duel_value(d.challenger_id, d.metric, d.starts_at, d.ends_at);
  b := duel_value(d.opponent_id, d.metric, d.starts_at, d.ends_at);
  av := (a->>'value')::numeric;
  bv := (b->>'value')::numeric;
  w := case when av > bv then d.challenger_id when bv > av then d.opponent_id else null end;
  update duels
     set status = 'finished', finished_at = now(), winner_id = w,
         challenger_value = av, opponent_value = bv,
         challenger_trips = (a->>'trips')::int, opponent_trips = (b->>'trips')::int
   where id = p_duel_id;
  return jsonb_build_object('status', 'finished', 'winner_id', w, 'challenger_value', av, 'opponent_value', bv);
end $$;

-- The winner picks the loser's seven-day badge from the fixed list. The
-- badge row is written here because `user_badges` only lets you insert your
-- own rows. Idempotent for the same pick.
create or replace function pick_duel_badge(p_duel_id uuid, p_badge_id text) returns void
language plpgsql security definer set search_path = public as $$
declare
  d duels%rowtype;
  loser uuid;
begin
  select * into d from duels where id = p_duel_id for update;
  if not found then raise exception 'unknown duel' using errcode = 'P0004'; end if;
  if d.status <> 'finished' or d.winner_id is null then raise exception 'no loser to badge' using errcode = 'P0009'; end if;
  if d.winner_id <> auth.uid() then raise exception 'only the winner picks' using errcode = 'P0005'; end if;
  if p_badge_id not in ('sunday_driver','lead_foot','butterfingers') then
    raise exception 'not a duel badge' using errcode = 'P0010';
  end if;
  if d.loser_badge_id is not null then
    if d.loser_badge_id = p_badge_id then return; end if;
    raise exception 'badge already chosen' using errcode = 'P0006';
  end if;
  loser := case when d.winner_id = d.challenger_id then d.opponent_id else d.challenger_id end;
  insert into user_badges (user_id, badge_id, awarded_at, expires_at)
  values (loser, p_badge_id, now(), now() + interval '7 days')
  on conflict (user_id, badge_id) do update set awarded_at = excluded.awarded_at, expires_at = excluded.expires_at;
  update duels set loser_badge_id = p_badge_id where id = p_duel_id;
end $$;

-- Daily backstop: expire unanswered challenges, settle finished weeks, hand
-- out the default badge when a winner has not picked within three days, and
-- forget old duels.
create or replace function finalize_due_duels() returns void
language plpgsql security definer set search_path = public as $$
declare
  d record;
begin
  update duels set status = 'expired' where status = 'pending' and created_at < now() - interval '7 days';
  for d in select id from duels where status = 'active' and ends_at <= now() loop
    begin
      perform finalize_duel(d.id);
    exception when others then
      raise notice 'finalize_duel(%) failed: %', d.id, sqlerrm;
    end;
  end loop;
  for d in
    select id, winner_id, challenger_id, opponent_id from duels
     where status = 'finished' and winner_id is not null and loser_badge_id is null
       and finished_at < now() - interval '3 days'
  loop
    insert into user_badges (user_id, badge_id, awarded_at, expires_at)
    values (case when d.winner_id = d.challenger_id then d.opponent_id else d.challenger_id end,
            'sunday_driver', now(), now() + interval '7 days')
    on conflict (user_id, badge_id) do update set awarded_at = excluded.awarded_at, expires_at = excluded.expires_at;
    update duels set loser_badge_id = 'sunday_driver' where id = d.id;
  end loop;
  delete from duels where status in ('declined','expired') and created_at < now() - interval '30 days';
  delete from duels where status = 'finished' and finished_at < now() - interval '90 days';
end $$;

alter table duels enable row level security;
create policy duels_select on duels for select to authenticated
  using (auth.uid() in (challenger_id, opponent_id));
create policy duels_insert on duels for insert to authenticated
  with check (challenger_id = auth.uid() and status = 'pending' and are_friends(auth.uid(), opponent_id));
-- Cancelling an unanswered challenge is a delete; everything else goes through the functions.
create policy duels_delete on duels for delete to authenticated
  using (challenger_id = auth.uid() and status = 'pending');

-- ---------------------------------------------------------------------------
-- Group challenges: one league, one goal, one or two weeks (docs/02 §12.2)
-- ---------------------------------------------------------------------------
create type challenge_goal as enum ('clean_trips','phone_free','score_avg','everyone_drives');

create table group_challenges (
  id uuid primary key,                            -- client-generated
  league_id uuid not null references leagues(id) on delete cascade,
  created_by uuid not null references profiles(id) on delete cascade,
  goal challenge_goal not null,
  target int not null check (target > 0),         -- trips, score, or trips per member (everyone_drives)
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'active' check (status in ('active','succeeded','failed')),
  value numeric(8,2),                             -- the league's result once finalised
  per_member jsonb,                               -- [{user_id, trips, clean, phone_free, score_avg}]
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (ends_at <= starts_at + interval '31 days')
);
-- One running challenge per league keeps the card simple.
create unique index group_challenges_one_active on group_challenges (league_id) where status = 'active';
create index group_challenges_league on group_challenges (league_id, starts_at desc);

-- Where a challenge stands, over the league's current members. Mirrors
-- `computeChallengeProgress` in the app (lib/data/repos/challenges_repo.dart).
--   clean_trips      trips scored 80+ (the clean-trip score) and not reckless, league total
--   phone_free       trips with no phone_handling event, league total
--   score_avg        average Drive Score over every member trip
--   everyone_drives  members with at least `target` trips; met when all have
-- Returns {"value","needed","target","members","met","per_member"}.
create or replace function challenge_progress(p_challenge_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c group_challenges%rowtype;
  v numeric := 0;
  members int;
  per jsonb;
  met boolean;
begin
  select * into c from group_challenges where id = p_challenge_id;
  if not found then raise exception 'unknown challenge' using errcode = 'P0004'; end if;
  select count(*) into members from league_members where league_id = c.league_id;
  with mine as (
    select m.user_id, t.id as trip_id, t.score, t.reckless,
           exists (select 1 from trip_events e where e.trip_id = t.id and e.kind = 'phone_handling') as phone
      from league_members m
      left join trip_summaries t
        on t.user_id = m.user_id and t.scored and not t.is_passenger
       and t.started_at >= c.starts_at and t.started_at < c.ends_at
     where m.league_id = c.league_id
  ), by_member as (
    select user_id,
           count(trip_id)::int as trips,
           (count(trip_id) filter (where score >= 80 and not reckless))::int as clean,
           (count(trip_id) filter (where not phone))::int as phone_free,
           sum(score)::numeric as score_sum
      from mine group by user_id
  )
  select jsonb_agg(jsonb_build_object(
           'user_id', user_id, 'trips', trips, 'clean', clean, 'phone_free', phone_free,
           'score_avg', case when trips > 0 then round(score_sum / trips, 1) end) order by user_id),
         case c.goal
           when 'clean_trips' then coalesce(sum(clean), 0)::numeric
           when 'phone_free' then coalesce(sum(phone_free), 0)::numeric
           when 'score_avg' then coalesce(round(sum(score_sum) / nullif(sum(trips), 0), 2), 0)::numeric
           else (count(*) filter (where trips >= c.target))::numeric
         end
    into per, v
    from by_member;
  v := coalesce(v, 0);
  met := case when c.goal = 'everyone_drives' then members > 0 and v >= members else v >= c.target end;
  return jsonb_build_object(
    'value', v,
    'needed', case when c.goal = 'everyone_drives' then members else c.target end,
    'target', c.target,
    'members', members,
    'met', met,
    'per_member', coalesce(per, '[]'::jsonb));
end $$;
revoke execute on function challenge_progress(uuid) from public, anon, authenticated;

-- Settles a challenge whose window closed. Any member's phone may call it;
-- idempotent. Success gives every current member the goal's badge.
create or replace function finalize_group_challenge(p_challenge_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c group_challenges%rowtype;
  p jsonb;
  s text;
begin
  select * into c from group_challenges where id = p_challenge_id for update;
  if not found then raise exception 'unknown challenge' using errcode = 'P0004'; end if;
  if auth.uid() is not null and not shares_league(c.league_id) then
    raise exception 'not a member' using errcode = 'P0005';
  end if;
  if c.status <> 'active' then
    return jsonb_build_object('status', c.status, 'value', c.value, 'per_member', c.per_member);
  end if;
  if c.ends_at > now() then raise exception 'challenge not over yet' using errcode = 'P0003'; end if;
  p := challenge_progress(p_challenge_id);
  s := case when (p->>'met')::boolean then 'succeeded' else 'failed' end;
  update group_challenges
     set status = s, value = (p->>'value')::numeric, per_member = p->'per_member', finalized_at = now()
   where id = p_challenge_id;
  if s = 'succeeded' then
    insert into user_badges (user_id, badge_id)
    select m.user_id, 'challenge_' || c.goal::text from league_members m where m.league_id = c.league_id
    on conflict (user_id, badge_id) do nothing;
  end if;
  return jsonb_build_object('status', s, 'value', p->'value', 'per_member', p->'per_member');
end $$;

create or replace function finalize_due_group_challenges() returns void
language plpgsql security definer set search_path = public as $$
declare
  c record;
begin
  for c in select id from group_challenges where status = 'active' and ends_at <= now() loop
    begin
      perform finalize_group_challenge(c.id);
    exception when others then
      raise notice 'finalize_group_challenge(%) failed: %', c.id, sqlerrm;
    end;
  end loop;
  delete from group_challenges where status <> 'active' and finalized_at < now() - interval '180 days';
end $$;

alter table group_challenges enable row level security;
create policy group_challenges_select on group_challenges for select to authenticated
  using (shares_league(league_id));
-- Friend leagues only: a global league is rebuilt every Monday, so a
-- challenge there would outlive its members.
create policy group_challenges_insert on group_challenges for insert to authenticated
  with check (created_by = auth.uid() and shares_league(league_id) and status = 'active'
              and exists (select 1 from leagues l where l.id = league_id and l.kind = 'friend'));
create policy group_challenges_delete on group_challenges for delete to authenticated
  using (created_by = auth.uid() and status = 'active');

insert into badges (id, name, description, category) values
  ('challenge_clean_trips',     'Clean Sweep',         'Your league hit its clean-trips challenge.',              'social'),
  ('challenge_phone_free',      'Hands Off, Together', 'Your league hit its phone-free challenge.',               'social'),
  ('challenge_score_avg',       'Class Act',           'Your league averaged its target Drive Score.',            'social'),
  ('challenge_everyone_drives', 'Full House',          'Everyone in your league showed up for the challenge.',    'social')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Seasons: quarters, with each driver's summary uploaded by their phone (§12.3)
-- ---------------------------------------------------------------------------
create table seasons (
  id text primary key,                            -- '2026-q4'
  number int not null unique,
  name text not null,
  starts_on date not null,
  ends_on date not null,                          -- inclusive
  check (ends_on > starts_on)
);
insert into seasons (id, number, name, starts_on, ends_on) values
  ('2026-q4', 1, 'Season 1', '2026-10-01', '2026-12-31'),
  ('2027-q1', 2, 'Season 2', '2027-01-01', '2027-03-31'),
  ('2027-q2', 3, 'Season 3', '2027-04-01', '2027-06-30'),
  ('2027-q3', 4, 'Season 4', '2027-07-01', '2027-09-30'),
  ('2027-q4', 5, 'Season 5', '2027-10-01', '2027-12-31')
on conflict (id) do nothing;

-- Written by the phone when a season ends, from its own trips (outbox kind
-- `season_result`). Counts and averages only; no places, no routes.
create table season_results (
  season_id text not null references seasons(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  trips int not null default 0 check (trips >= 0),
  xp int not null default 0 check (xp >= 0),
  score_avg numeric(5,2) check (score_avg between 0 and 100),
  clean_trips int not null default 0 check (clean_trips >= 0),
  phone_free_trips int not null default 0 check (phone_free_trips >= 0),
  best_score smallint check (best_score between 0 and 100),
  best_tier league_tier,
  duels_won int not null default 0 check (duels_won >= 0),
  duels_lost int not null default 0 check (duels_lost >= 0),
  wrapped jsonb,                                  -- the phone's Season Wrapped card, small
  updated_at timestamptz not null default now(),
  primary key (season_id, user_id)
);

alter table seasons enable row level security;
alter table season_results enable row level security;
create policy seasons_select on seasons for select to authenticated using (true);
create policy season_results_select on season_results for select to authenticated using (can_view(user_id));
create policy season_results_insert on season_results for insert to authenticated with check (user_id = auth.uid());
create policy season_results_update on season_results for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Global leagues: matchmade every Monday by tier and rating (docs/02 §7, §12.4)
-- ---------------------------------------------------------------------------
-- Global leagues have no owner. Every `created_by = auth.uid()` policy on
-- leagues and league_members is then false for them, so nobody edits,
-- deletes or hand-invites into a global league; the functions below do it.
alter table leagues alter column created_by drop not null;
alter table leagues add column global_tier league_tier;      -- set only on kind = 'global'
-- Set on a global league when Monday's matchmaking replaced it. Closed
-- tables keep their members, their `league_weeks` rows and any running group
-- challenge; they are pruned after 60 days once nothing live points at them.
alter table leagues add column closed_at timestamptz;
create index leagues_global_open on leagues (global_tier, created_at) where kind = 'global' and closed_at is null;

-- Who is in the global pool, and the tier they carry from week to week
-- (memberships are rebuilt every Monday, so the tier cannot live there).
create table global_league_players (
  user_id uuid primary key references profiles(id) on delete cascade,
  tier league_tier not null default 'learner',
  active boolean not null default true,           -- false after leaving or four idle weeks
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table global_league_players enable row level security;
create policy global_league_players_select on global_league_players for select to authenticated
  using (user_id = auth.uid());

-- Invite codes only open friend leagues now; global ones are matchmade.
create or replace function join_league(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  l leagues%rowtype;
  members int;
begin
  select * into l from leagues where invite_code = lower(code) and kind = 'friend';
  if not found then raise exception 'invalid invite code' using errcode = 'P0001'; end if;
  select count(*) into members from league_members where league_id = l.id;
  if members >= l.max_members then raise exception 'league is full' using errcode = 'P0002'; end if;
  insert into league_members (league_id, user_id) values (l.id, auth.uid()) on conflict do nothing;
  return l.id;
end $$;

-- Joins the pool and seats the caller at once: the current global league at
-- their tier with room, else a fresh one. Monday's matchmaking reshuffles
-- everyone anyway. Returns the league id; idempotent.
create or replace function join_global_league() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  p global_league_players%rowtype;
  existing uuid;
  target uuid;
  n int;
begin
  if me is null then raise exception 'not signed in' using errcode = 'P0005'; end if;
  insert into global_league_players (user_id) values (me)
  on conflict (user_id) do update set active = true, updated_at = now()
  returning * into p;
  select m.league_id into existing
    from league_members m join leagues l on l.id = m.league_id
   where m.user_id = me and l.kind = 'global' and l.closed_at is null
   limit 1;
  if existing is not null then return existing; end if;
  select l.id into target
    from leagues l
   where l.kind = 'global' and l.closed_at is null and l.global_tier = p.tier
     and (select count(*) from league_members m where m.league_id = l.id) < l.max_members
   order by l.created_at
   limit 1;
  if target is null then
    select count(*) + 1 into n from leagues
     where kind = 'global' and closed_at is null and global_tier = p.tier;
    insert into leagues (name, kind, created_by, global_tier)
    values ('Global ' || initcap(p.tier::text) || ' ' || n, 'global', null, p.tier)
    returning id into target;
  end if;
  insert into league_members (league_id, user_id, tier) values (target, me, p.tier) on conflict do nothing;
  return target;
end $$;

-- Leaves this week's global league and the pool. Rejoin any time; the tier
-- is kept.
create or replace function leave_global_league() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from league_members m using leagues l
   where l.id = m.league_id and l.kind = 'global' and l.closed_at is null and m.user_id = auth.uid();
  update global_league_players set active = false, updated_at = now() where user_id = auth.uid();
end $$;

-- Monday 06:10 UTC, after finalize_all_leagues (06:00) has moved tiers:
-- carry the new tiers to the pool, drop idle players, close last week's
-- tables and rebuild the leagues per tier in even groups of at most 30
-- ordered by Driver Rating. Closing (not deleting) keeps each table's
-- `league_weeks` row readable to its members, so the week badges can be
-- awarded whenever the phone next looks, and lets a group challenge that
-- was running there finish on schedule. Closed tables are pruned after 60
-- days once no active challenge references them.
create or replace function matchmake_global_leagues() returns void
language plpgsql security definer set search_path = public as $$
declare
  t record;
  grp record;
  n_leagues int;
  lid uuid;
begin
  update global_league_players p set tier = m.tier, updated_at = now()
    from league_members m join leagues l on l.id = m.league_id
   where l.kind = 'global' and l.closed_at is null and m.user_id = p.user_id;

  update global_league_players p set active = false, updated_at = now()
   where p.active and p.joined_at < now() - interval '28 days'
     and not exists (select 1 from trip_summaries s
                      where s.user_id = p.user_id and s.scored and s.started_at >= now() - interval '28 days');

  update leagues set closed_at = now() where kind = 'global' and closed_at is null;
  delete from leagues l
   where l.kind = 'global' and l.closed_at < now() - interval '60 days'
     and not exists (select 1 from group_challenges g where g.league_id = l.id and g.status = 'active');

  for t in select tier, count(*)::int as players from global_league_players where active group by tier loop
    n_leagues := ceil(t.players / 30.0)::int;
    for grp in
      with ranked as (
        select p.user_id,
               ntile(n_leagues) over (order by pr.driver_rating desc nulls last, random()) as bucket
          from global_league_players p join profiles pr on pr.id = p.user_id
         where p.active and p.tier = t.tier
      )
      select bucket, array_agg(user_id) as members from ranked group by bucket order by bucket
    loop
      insert into leagues (name, kind, created_by, global_tier)
      values ('Global ' || initcap(t.tier::text) || ' ' || grp.bucket, 'global', null, t.tier)
      returning id into lid;
      insert into league_members (league_id, user_id, tier)
      select lid, u, t.tier from unnest(grp.members) as u;
    end loop;
  end loop;
end $$;

-- pg_cron, as in 0001: skipped with a notice when the extension is missing.
do $$
begin
  perform cron.schedule('matchmake-global-leagues', '10 6 * * 1', 'select public.matchmake_global_leagues()');
  perform cron.schedule('finalize-duels', '20 6 * * *', 'select public.finalize_due_duels()');
  perform cron.schedule('finalize-group-challenges', '25 6 * * *', 'select public.finalize_due_group_challenges()');
exception when others then
  raise notice 'pg_cron not available: %', sqlerrm;
end $$;
