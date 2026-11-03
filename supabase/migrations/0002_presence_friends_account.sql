-- Drivalry: friends see each other on the map, a global "hide my location"
-- switch, and account deletion. Apply after 0001_init.sql.
--
-- ADR-018 (docs/00-decisions.md): the Drive tab carries a live map of
-- friends and circle members. Location is visible to accepted friends and to
-- circle members, precise, unless the owner hides in that circle or flips the
-- global switch below.

alter table profiles
  add column if not exists location_hidden boolean not null default false;

drop policy if exists presence_select on presence;
create policy presence_select on presence for select to authenticated
  using (
    user_id = auth.uid()
    or (
      not exists (select 1 from profiles p where p.id = presence.user_id and p.location_hidden)
      and (
        are_friends(auth.uid(), presence.user_id)
        or exists (
          select 1 from circle_members a join circle_members b using (circle_id)
          where a.user_id = auth.uid() and b.user_id = presence.user_id and b.hiding = false)
      )
    )
  );

-- Trip cards and posts were already visible through shared leagues and
-- circles; friends count as a group too, so a friend with no league yet still
-- sees your roasts.
create or replace function can_view(author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select author = auth.uid()
     or are_friends(auth.uid(), author)
     or exists (select 1 from league_members a join league_members b using (league_id)
                 where a.user_id = auth.uid() and b.user_id = author and b.hiding = false)
     or exists (select 1 from circle_members a join circle_members b using (circle_id)
                 where a.user_id = auth.uid() and b.user_id = author and b.hiding = false)
$$;

-- Account deletion from the app (App Store requirement). Cascades through
-- every table that references profiles.
create or replace function delete_own_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = 'P0001';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function delete_own_account() from public;
grant execute on function delete_own_account() to authenticated;

-- Handle lookup for "add friend by handle": exact, case-insensitive.
create index if not exists profiles_handle_lower on profiles (lower(handle));
