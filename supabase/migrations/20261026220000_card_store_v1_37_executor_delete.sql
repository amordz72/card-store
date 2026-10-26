-- v1.37 — delete old Rech-Doom phones from the admin list (owner request 2026-10-26).
-- Only a disabled phone can be deleted. Past IDOOM jobs keep pointing at it (store.idoom_jobs.executor_id),
-- so the row stays: it is marked deleted, hidden from the list, can never be enabled again,
-- and its token is replaced by a value no token can hash to, so the phone is refused for good.

alter table store.executors add column deleted_at timestamptz;

create function private.store_admin_executor_delete_impl(p_executor_id bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_active boolean;
begin
  perform private.store_require_admin();
  select e.active into v_active from store.executors e
  where e.id = p_executor_id and e.deleted_at is null
  for update;
  if not found then raise exception 'PHONE_NOT_FOUND'; end if;
  if v_active then raise exception 'PHONE_ACTIVE'; end if;
  if exists (select 1 from store.idoom_jobs j where j.executor_id = p_executor_id and j.status = 'claimed') then
    raise exception 'PHONE_BUSY';
  end if;
  update store.executors
  set deleted_at = now(),
      token_hash = 'deleted:' || id || ':' || encode(extensions.gen_random_bytes(16), 'hex')
  where id = p_executor_id;
  return true;
end;
$$;

create function public.store_admin_executor_delete(p_executor_id bigint) returns boolean
language sql set search_path = '' as $$ select private.store_admin_executor_delete_impl(p_executor_id); $$;

revoke all on function private.store_admin_executor_delete_impl(bigint) from public, anon, authenticated;
grant execute on function private.store_admin_executor_delete_impl(bigint) to authenticated;
revoke all on function public.store_admin_executor_delete(bigint) from public, anon, authenticated;
grant execute on function public.store_admin_executor_delete(bigint) to authenticated;

-- The list hides deleted phones (same columns and order as v1.14).
create or replace function private.store_admin_executors_impl()
returns table (id bigint, name text, active boolean, last_seen_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select e.id, e.name, e.active, e.last_seen_at from store.executors e
  where e.deleted_at is null
  order by e.last_seen_at desc nulls last, e.id desc;
end;
$$;

-- A deleted phone cannot be switched back on (same body as v1.30, plus deleted_at is null).
create or replace function private.store_admin_executor_set_active_impl(p_executor_id bigint, p_active boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v boolean;
begin
  perform private.store_require_admin();
  if not coalesce(p_active, true)
     and exists (select 1 from store.idoom_jobs j where j.executor_id = p_executor_id and j.status = 'claimed') then
    raise exception 'PHONE_BUSY';
  end if;
  update store.executors set active = coalesce(p_active, true)
  where id = p_executor_id and deleted_at is null
  returning active into v;
  if v is null then raise exception 'PHONE_NOT_FOUND'; end if;
  return v;
end;
$$;
