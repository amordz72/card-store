-- =====================================================================
-- Card Store v1.8 — device lock PIN (owner decision 2026-10-21)
--  * Each account (customer or owner) may set a 4–6 digit PIN that unlocks the app
--    after a period without use. Fingerprint/face unlock is done by the device (WebAuthn)
--    and never reaches the server; the PIN is the fallback.
--  * The PIN is stored bcrypt-hashed. Checks return a status (not an exception) so the
--    failure counter is kept: after 5 wrong PINs the customer's sessions are revoked
--    and the app signs the owner out.
-- Additive only.
-- =====================================================================

create table store.lock_pins (
  owner_key text primary key,          -- 'c:<customer id>' or 'a:<auth user id>'
  pin_hash text not null,
  failed int not null default 0,
  updated_at timestamptz not null default now()
);
alter table store.lock_pins enable row level security;
revoke all on store.lock_pins from public, anon, authenticated;

create function private.store_pin_valid(p_pin text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then raise exception 'INVALID_PIN'; end if;
end;
$$;

create function private.store_pin_set(p_key text, p_pin text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_pin_valid(p_pin);
  insert into store.lock_pins (owner_key, pin_hash) values (p_key, extensions.crypt(p_pin, extensions.gen_salt('bf', 10)))
  on conflict (owner_key) do update set pin_hash = excluded.pin_hash, failed = 0, updated_at = now();
end;
$$;

-- 'ok' | 'wrong' | 'locked_out' (5th wrong attempt) | 'no_pin'
create function private.store_pin_check(p_key text, p_pin text) returns text
language plpgsql security definer set search_path = '' as $$
declare r store.lock_pins;
begin
  select * into r from store.lock_pins where owner_key = p_key for update;
  if not found then return 'no_pin'; end if;
  if p_pin is not null and r.pin_hash = extensions.crypt(p_pin, r.pin_hash) then
    update store.lock_pins set failed = 0 where owner_key = p_key;
    return 'ok';
  end if;
  if r.failed + 1 >= 5 then
    update store.lock_pins set failed = 0 where owner_key = p_key;
    return 'locked_out';
  end if;
  update store.lock_pins set failed = r.failed + 1 where owner_key = p_key;
  return 'wrong';
end;
$$;

-- customer
create function private.store_lock_status_impl(p_token text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return exists (select 1 from store.lock_pins where owner_key = 'c:' || v);
end;
$$;

create function private.store_set_pin_impl(p_token text, p_pin text) returns void
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  perform private.store_pin_set('c:' || v, p_pin);
end;
$$;

create function private.store_check_pin_impl(p_token text, p_pin text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  s text := private.store_pin_check('c:' || v, p_pin);
begin
  if s = 'locked_out' then
    update store.customer_sessions set revoked_at = now() where customer_id = v and revoked_at is null;
  end if;
  return s;
end;
$$;

-- owner
create function private.store_admin_lock_status_impl() returns boolean
language plpgsql security definer set search_path = '' as $$
declare a uuid := private.store_require_admin();
begin
  return exists (select 1 from store.lock_pins where owner_key = 'a:' || a);
end;
$$;

create function private.store_admin_set_pin_impl(p_pin text) returns void
language plpgsql security definer set search_path = '' as $$
declare a uuid := private.store_require_admin();
begin
  perform private.store_pin_set('a:' || a, p_pin);
end;
$$;

create function private.store_admin_check_pin_impl(p_pin text) returns text
language plpgsql security definer set search_path = '' as $$
declare a uuid := private.store_require_admin();
begin
  return private.store_pin_check('a:' || a, p_pin);
end;
$$;

create function public.store_lock_status(p_token text) returns boolean
language sql set search_path = '' as $$ select private.store_lock_status_impl(p_token); $$;
create function public.store_set_pin(p_token text, p_pin text) returns void
language sql set search_path = '' as $$ select private.store_set_pin_impl(p_token, p_pin); $$;
create function public.store_check_pin(p_token text, p_pin text) returns text
language sql set search_path = '' as $$ select private.store_check_pin_impl(p_token, p_pin); $$;
create function public.store_admin_lock_status() returns boolean
language sql set search_path = '' as $$ select private.store_admin_lock_status_impl(); $$;
create function public.store_admin_set_pin(p_pin text) returns void
language sql set search_path = '' as $$ select private.store_admin_set_pin_impl(p_pin); $$;
create function public.store_admin_check_pin(p_pin text) returns text
language sql set search_path = '' as $$ select private.store_admin_check_pin_impl(p_pin); $$;

-- Grants (same rule as before)
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname in ('private', 'public') and p.proname like 'store\_%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.name like 'store\_admin\_%' then
      if f.sch = 'public' or f.name like '%\_impl' then
        execute format('grant execute on function %s to authenticated', f.sig);
      end if;
    elsif f.name like '%\_impl' or f.sch = 'public' then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
