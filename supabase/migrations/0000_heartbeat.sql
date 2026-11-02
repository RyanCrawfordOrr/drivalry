-- Tiny table the keep-alive workflow reads once a day so the free project
-- never pauses for inactivity (Supabase pauses on low *database* activity).
-- Safe to expose: it holds one integer and a timestamp.
create table if not exists public.heartbeat (
  id smallint primary key,
  touched_at timestamptz not null default now()
);

insert into public.heartbeat (id) values (1) on conflict (id) do nothing;

alter table public.heartbeat enable row level security;

drop policy if exists "heartbeat is readable by anyone" on public.heartbeat;
create policy "heartbeat is readable by anyone"
  on public.heartbeat for select using (true);
