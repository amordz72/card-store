-- card-store v1.38: the SIM that ran each shop Flexy row, for the owner (SHOP-OPS-SIM-AND-BALANCE step 1).
-- Flexy Core keeps the SIM by the app's key (store.flexy_jobs.core_key); the owner's page reads the keys
-- of the rows it shows here, then asks flexy-api (/v1/owner/app-operations). Owner only, read only.

create function private.store_admin_flexy_keys_impl(p_job_ids bigint[])
returns table (job_id bigint, core_key text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select j.id, j.core_key from store.flexy_jobs j where j.id = any (coalesce(p_job_ids, '{}')) order by j.id limit 100;
end;
$$;

create function public.store_admin_flexy_keys(p_job_ids bigint[])
returns table (job_id bigint, core_key text)
language sql set search_path = '' as $$
  select * from private.store_admin_flexy_keys_impl(p_job_ids);
$$;

revoke all on function private.store_admin_flexy_keys_impl(bigint[]) from public, anon, authenticated;
revoke all on function public.store_admin_flexy_keys(bigint[]) from public, anon, authenticated;
grant execute on function private.store_admin_flexy_keys_impl(bigint[]) to authenticated;
grant execute on function public.store_admin_flexy_keys(bigint[]) to authenticated;
