-- 0008: block people and report content (App Store Guideline 1.2 and Play UGC
-- policy: user-generated content needs a report mechanism and a way to block
-- abusive users).
--
-- Blocking is one table, both directions count. A block ends the friendship
-- and any pending request, stops the blocked person from sending a new
-- request, and takes both people out of each other's feed, comments,
-- reactions and live-location map even if they still share a league, circle
-- or convoy. Reports are rows the owner reads in the dashboard
-- (docs/11-owner-setup.md Part 17); the reporter's phone hides the content
-- at once. Idempotent.

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------
create table if not exists user_blocks (
  blocker_id uuid not null references profiles(id) on delete cascade,
  blocked_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists user_blocks_blocked on user_blocks (blocked_id);

alter table user_blocks enable row level security;

drop policy if exists user_blocks_select on user_blocks;
create policy user_blocks_select on user_blocks for select to authenticated
  using (blocker_id = auth.uid());
drop policy if exists user_blocks_insert on user_blocks;
create policy user_blocks_insert on user_blocks for insert to authenticated
  with check (blocker_id = auth.uid());
drop policy if exists user_blocks_delete on user_blocks;
create policy user_blocks_delete on user_blocks for delete to authenticated
  using (blocker_id = auth.uid());

-- True when either person has blocked the other.
create or replace function is_blocked_between(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from user_blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  )
$$;

-- A new block deletes the friendship or pending request in both directions.
create or replace function apply_user_block() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from friendships
  where (requester_id = new.blocker_id and addressee_id = new.blocked_id)
     or (requester_id = new.blocked_id and addressee_id = new.blocker_id);
  return new;
end $$;

drop trigger if exists on_user_block on user_blocks;
create trigger on_user_block
  after insert on user_blocks
  for each row execute function apply_user_block();

-- can_view: the 0006 body, plus "unless one of us blocked the other".
create or replace function can_view(author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select author = auth.uid()
     or (
       not is_blocked_between(auth.uid(), author)
       and (
         are_friends(auth.uid(), author)
         or exists (select 1 from league_members a join league_members b using (league_id)
                     where a.user_id = auth.uid() and b.user_id = author and b.hiding = false)
         or exists (select 1 from circle_members a join circle_members b using (circle_id)
                     where a.user_id = auth.uid() and b.user_id = author and b.hiding = false)
         or exists (select 1 from convoy_members a join convoy_members b using (convoy_id)
                     where a.user_id = auth.uid() and b.user_id = author
                       and a.left_at is null and b.left_at is null)
       )
     )
$$;

-- A blocked person cannot send a friend request.
drop policy if exists friendships_insert on friendships;
create policy friendships_insert on friendships for insert to authenticated
  with check (
    requester_id = auth.uid()
    and status = 'pending'
    and not is_blocked_between(requester_id, addressee_id)
  );

-- Comments and reactions by someone you blocked stay out of posts you can
-- still see (a shared league, for example).
drop policy if exists feed_comments_select on feed_comments;
create policy feed_comments_select on feed_comments for select to authenticated
  using (
    not is_blocked_between(auth.uid(), author_id)
    and exists (select 1 from feed_posts p where p.id = post_id and can_view(p.author_id))
  );

drop policy if exists feed_reactions_select on feed_reactions;
create policy feed_reactions_select on feed_reactions for select to authenticated
  using (
    not is_blocked_between(auth.uid(), user_id)
    and exists (select 1 from feed_posts p where p.id = post_id and can_view(p.author_id))
  );

-- Live location: the 0002 body, plus the block check.
drop policy if exists presence_select on presence;
create policy presence_select on presence for select to authenticated
  using (
    user_id = auth.uid()
    or (
      not is_blocked_between(auth.uid(), presence.user_id)
      and not exists (select 1 from profiles p where p.id = presence.user_id and p.location_hidden)
      and (
        are_friends(auth.uid(), presence.user_id)
        or exists (
          select 1 from circle_members a join circle_members b using (circle_id)
          where a.user_id = auth.uid() and b.user_id = presence.user_id and b.hiding = false)
      )
    )
  );

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------
create table if not exists content_reports (
  id uuid primary key,                            -- client-generated; retries are idempotent
  reporter_id uuid not null references profiles(id) on delete cascade,
  reported_user_id uuid references profiles(id) on delete set null,
  post_id uuid references feed_posts(id) on delete set null,
  comment_id uuid references feed_comments(id) on delete set null,
  reason text not null check (reason in ('abusive', 'not_driving', 'spam', 'other')),
  details text check (char_length(details) <= 500),
  snapshot jsonb not null default '{}'::jsonb,    -- the text as the reporter saw it, kept after the content is deleted
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned')),
  created_at timestamptz not null default now(),
  check (post_id is not null or comment_id is not null or reported_user_id is not null)
);
create index if not exists content_reports_open on content_reports (status, created_at desc);

alter table content_reports enable row level security;

drop policy if exists content_reports_select on content_reports;
create policy content_reports_select on content_reports for select to authenticated
  using (reporter_id = auth.uid());
drop policy if exists content_reports_insert on content_reports;
create policy content_reports_insert on content_reports for insert to authenticated
  with check (reporter_id = auth.uid());
