-- v1.30 — switch Rech-Doom phones on/off from the admin page (owner request 2026-10-23 «نفذ»).
-- Jobs go to whichever active phone asks first, so a second phone left receiving takes them.
-- A disabled phone is refused by store_exec_id (INVALID_EXECUTOR) and gets no job.
-- A phone with a job still claimed cannot be disabled: it could no longer report the result.

create function private.store_admin_executor_set_active_impl(p_executor_id bigint, p_active boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v boolean;
begin
  perform private.store_require_admin();
  if not coalesce(p_active, true)
     and exists (select 1 from store.idoom_jobs j where j.executor_id = p_executor_id and j.status = 'claimed') then
    raise exception 'PHONE_BUSY';
  end if;
  update store.executors set active = coalesce(p_active, true)
  where id = p_executor_id
  returning active into v;
  if v is null then raise exception 'PHONE_NOT_FOUND'; end if;
  return v;
end;
$$;

create function public.store_admin_executor_set_active(p_executor_id bigint, p_active boolean) returns boolean
language sql set search_path = '' as $$ select private.store_admin_executor_set_active_impl(p_executor_id, p_active); $$;

revoke all on function private.store_admin_executor_set_active_impl(bigint, boolean) from public, anon, authenticated;
grant execute on function private.store_admin_executor_set_active_impl(bigint, boolean) to authenticated;
revoke all on function public.store_admin_executor_set_active(bigint, boolean) from public, anon, authenticated;
grant execute on function public.store_admin_executor_set_active(bigint, boolean) to authenticated;
