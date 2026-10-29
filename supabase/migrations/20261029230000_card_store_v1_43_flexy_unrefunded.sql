-- v1.43 (owner 2026-10-29, «نفذ 5»): a shop's flexy that failed and whose charge did not come back reaches the bell.
-- Checked first (read only, 2026-10-29): 2 failed and 4 not sent, all refunded; nothing missing. This catches
-- the day it happens: a job failed / not sent for over 5 minutes whose wallet entry has no reversing entry.

create or replace function private.store_admin_flexy_unrefunded_impl()
returns table (count bigint, amount bigint)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query
  select count(*), coalesce(sum(j.charged), 0)::bigint
    from store.flexy_jobs j
   where j.status in ('failed', 'not_sent')
     and coalesce(j.finished_at, j.updated_at) < now() - interval '5 minutes'
     and j.entry_id is not null
     and not exists (select 1 from store.wallet_entries x where x.reverses_id = j.entry_id);
end;
$$;

create or replace function public.store_admin_flexy_unrefunded()
returns table (count bigint, amount bigint)
language sql as $$ select * from private.store_admin_flexy_unrefunded_impl() $$;

revoke all on function private.store_admin_flexy_unrefunded_impl() from public, anon, authenticated;
revoke all on function public.store_admin_flexy_unrefunded() from public, anon, authenticated;
grant execute on function private.store_admin_flexy_unrefunded_impl() to authenticated;
grant execute on function public.store_admin_flexy_unrefunded() to authenticated;
