-- 0006: convoy members can see each other's trip summaries.
--
-- The recap (docs/10 §8) reads members' `trip_summaries` for the convoy
-- window through `can_view`. 0002's version covered the author, friends,
-- league peers and circle peers; two strangers who shared a convoy got
-- nothing, so Smoothest and Lead Foot came out empty for them.
--
-- Same body as 0002 plus one branch: current members (`left_at is null`) of a
-- convoy the viewer is also a current member of. Leaving a convoy ends the
-- visibility both ways; deleting the convoy cascades the memberships away.
-- Idempotent.

create or replace function can_view(author uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select author = auth.uid()
     or are_friends(auth.uid(), author)
     or exists (select 1 from league_members a join league_members b using (league_id)
                 where a.user_id = auth.uid() and b.user_id = author and b.hiding = false)
     or exists (select 1 from circle_members a join circle_members b using (circle_id)
                 where a.user_id = auth.uid() and b.user_id = author and b.hiding = false)
     or exists (select 1 from convoy_members a join convoy_members b using (convoy_id)
                 where a.user_id = auth.uid() and b.user_id = author
                   and a.left_at is null and b.left_at is null)
$$;
