-- =====================================================================
-- Card Store v1.9 — turning the app lock off (owner decision 2026-10-21)
--  * The account holder can turn his own lock off.
--  * The owner can turn a customer's lock off (forgotten PIN, or on request).
--  The row is kept and flagged (no delete); setting a new PIN turns it on again.
-- =====================================================================

alter table store.lock_pins add column disabled boolean not null default false;

create or replace function private.store_pin_set(p_key text, p_pin text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_pin_valid(p_pin);
  insert into store.lock_pins (owner_key, pin_hash) values (p_key, extensions.crypt(p_pin, extensions.gen_salt('bf', 10)))
  on conflict (owner_key) do update set pin_hash = excluded.pin_hash, failed = 0, disabled = false, updated_at = now();
end;
$$;

create or replace function private.store_pin_check(p_key text, p_pin text) returns text
language plpgsql security definer set search_path = '' as $$
declare r store.lock_pins;
begin
  select * into r from store.lock_pins where owner_key = p_key for update;
  if not found or r.disabled then return 'no_pin'; end if;
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

create function private.store_pin_off(p_key text) returns void
language sql security definer set search_path = '' as $$
  update store.lock_pins set disabled = true, failed = 0, updated_at = now() where owner_key = p_key;
$$;

create or replace function private.store_lock_status_impl(p_token text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return exists (select 1 from store.lock_pins where owner_key = 'c:' || v and not disabled);
end;
$$;

create or replace function private.store_admin_lock_status_impl() returns boolean
language plpgsql security definer set search_path = '' as $$
declare a uuid := private.store_require_admin();
begin
  return exists (select 1 from store.lock_pins where owner_key = 'a:' || a and not disabled);
end;
$$;

create function private.store_lock_off_impl(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  perform private.store_pin_off('c:' || v);
end;
$$;

create function private.store_admin_lock_off_impl() returns void
language plpgsql security definer set search_path = '' as $$
declare a uuid := private.store_require_admin();
begin
  perform private.store_pin_off('a:' || a);
end;
$$;

-- returns true when the customer had a lock that is now off
create function private.store_admin_customer_lock_off_impl(p_customer_id bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
declare had boolean;
begin
  perform private.store_require_admin();
  select exists (select 1 from store.lock_pins where owner_key = 'c:' || p_customer_id and not disabled) into had;
  perform private.store_pin_off('c:' || p_customer_id);
  return had;
end;
$$;

create function public.store_lock_off(p_token text) returns void
language sql set search_path = '' as $$ select private.store_lock_off_impl(p_token); $$;
create function public.store_admin_lock_off() returns void
language sql set search_path = '' as $$ select private.store_admin_lock_off_impl(); $$;
create function public.store_admin_customer_lock_off(p_customer_id bigint) returns boolean
language sql set search_path = '' as $$ select private.store_admin_customer_lock_off_impl(p_customer_id); $$;

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
