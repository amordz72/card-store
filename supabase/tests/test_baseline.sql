-- Minimal Supabase-like baseline for local testing only
create role anon nologin;
create role authenticated nologin;
create schema extensions;
create extension pgcrypto schema extensions;
grant usage on schema extensions to anon, authenticated;
create schema auth;
grant usage on schema auth to anon, authenticated;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated;
create schema private;
grant usage on schema private to anon, authenticated;
-- Supabase-like default: new functions in public are executable by API roles
alter default privileges in schema public grant execute on functions to anon, authenticated;
