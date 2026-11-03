-- Drivalry: crash alerts can name extra recipients. Apply after 0003.
--
-- An emergency contact who uses Drivalry but shares no circle with the driver
-- is linked on the phone (EmergencyContacts.userId) and listed here so the
-- push Edge Function reaches them too. Still never an automatic call.

alter table crash_alerts
  add column if not exists notify_user_ids uuid[] not null default '{}';

-- Trust boundary: the list is client-supplied, so only the driver's accepted
-- friends survive. Anyone else is dropped silently before the row is written,
-- which means a signed-in user cannot push a "possible crash" alert to
-- strangers or grant them read access to the row.
create or replace function filter_crash_alert_recipients() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.notify_user_ids := coalesce(
    (select array_agg(u)
       from unnest(new.notify_user_ids) as u
      where u <> new.user_id and are_friends(new.user_id, u)),
    '{}'::uuid[]);
  return new;
end $$;

drop trigger if exists crash_alerts_filter_recipients on crash_alerts;
create trigger crash_alerts_filter_recipients
  before insert or update of notify_user_ids on crash_alerts
  for each row execute function filter_crash_alert_recipients();

-- A named recipient may read the alert even without a shared circle.
drop policy if exists crash_alerts_select on crash_alerts;
create policy crash_alerts_select on crash_alerts for select to authenticated
  using (user_id = auth.uid()
    or auth.uid() = any (notify_user_ids)
    or exists (
      select 1 from circle_members a join circle_members b using (circle_id)
      where a.user_id = auth.uid() and b.user_id = crash_alerts.user_id));
