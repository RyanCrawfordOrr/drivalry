-- 0009: invite codes could not be generated from inside the league functions.
--
-- `gen_invite_code()` (0001) calls `gen_random_bytes`, which belongs to the
-- pgcrypto extension. Supabase installs extensions in the `extensions`
-- schema, and the function set no search_path of its own, so it inherited the
-- caller's. Every security-definer function in this project pins
-- `search_path = public`, so `join_global_league()` and
-- `matchmake_global_leagues()` failed on `insert into leagues` with
-- "function gen_random_bytes(integer) does not exist" (the global league's
-- Join button did nothing but show an error, and Monday's matchmaking would
-- have failed the same way). Direct inserts from the app only worked where
-- the connecting role happened to have `extensions` on its path.
--
-- Fix: name the schema and pin an empty search_path, so the generator works
-- from any caller. `encode` and `lower` are pg_catalog, always visible.
-- Idempotent.

create or replace function gen_invite_code() returns text
language sql volatile set search_path = '' as $$
  select lower(encode(extensions.gen_random_bytes(4), 'hex'))
$$;
