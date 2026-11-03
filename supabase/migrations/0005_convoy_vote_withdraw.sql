-- 0005: let a member withdraw a stop vote.
--
-- `convoy_stop_votes.vote` is constrained to -1 or 1, so "no opinion" is the
-- absence of a row. The app deletes its own row to withdraw; 0001 had insert
-- and update policies but no delete policy, so that delete silently did
-- nothing. Idempotent.

drop policy if exists convoy_stop_votes_delete on convoy_stop_votes;
create policy convoy_stop_votes_delete on convoy_stop_votes
  for delete to authenticated using (user_id = auth.uid());
