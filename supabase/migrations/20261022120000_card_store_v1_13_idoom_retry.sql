-- v1.13: IDOOM fixed lines are exactly 9 digits (My IDOOM's field takes 9: a 10th digit is cut,
-- which made the phone stop safely before Valider). A charge that stopped before Valider can be
-- re-queued with the same card (it was never submitted), optionally with a corrected line.

create or replace function private.store_idoom_line(p_line text) returns text
language plpgsql immutable set search_path = '' as $$
declare v text := regexp_replace(coalesce(p_line, ''), '[^0-9]', '', 'g');
begin
  if v !~ '^0[0-9]{8}$' then raise exception 'INVALID_LINE'; end if;
  return v;
end;
$$;

create or replace function private.store_admin_idoom_create_impl(p_product_id bigint, p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  b record;
  v_line text;
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs where request_id = p_request_id;
  if not found then
    v_line := private.store_idoom_line(p_line);
    select * into b from private.store_buy_core(private.store_shop_id(), p_product_id, 1, p_request_id);
    insert into store.idoom_jobs (line, product_id, order_id, code_id, request_id, created_by)
    select v_line, p_product_id, b.order_id, k.id, p_request_id, auth.uid()
    from store.codes k where k.order_id = b.order_id
    returning * into j;
  end if;
  return query select j.id, j.status;
end;
$$;

create or replace function private.store_admin_idoom_lookup_impl(p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare j store.idoom_jobs;
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs where request_id = p_request_id;
  if not found then
    insert into store.idoom_jobs (kind, line, request_id, created_by)
    values ('lookup', private.store_idoom_line(p_line), p_request_id, auth.uid())
    returning * into j;
  end if;
  return query select j.id, j.status;
end;
$$;

-- Re-queue a charge that stopped before Valider, same card. Previous attempt kept in reply.
create function private.store_admin_idoom_retry_impl(p_job_id bigint, p_line text) returns text
language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  perform private.store_require_admin();
  update store.idoom_jobs
     set line = private.store_idoom_line(coalesce(nullif(p_line, ''), line)),
         reply = left('[محاولة سابقة ' || line || ': ' || coalesce(outcome, '') || '] ' || coalesce(reply, ''), 2000),
         status = 'queued', outcome = null, offer = null, executor_id = null, claimed_at = null, finished_at = null
   where id = p_job_id and kind = 'charge' and status = 'failed' and outcome = 'PRE_SUBMIT_FAILED'
  returning status into v;
  if v is null then raise exception 'NOT_RETRYABLE'; end if;
  return v;
end;
$$;
create function public.store_admin_idoom_retry(p_job_id bigint, p_line text) returns text
language sql set search_path = '' as $$ select private.store_admin_idoom_retry_impl(p_job_id, p_line); $$;

revoke all on function private.store_idoom_line(text) from public, anon, authenticated;
revoke all on function private.store_admin_idoom_retry_impl(bigint, text) from public, anon, authenticated;
grant execute on function private.store_admin_idoom_retry_impl(bigint, text) to authenticated;
revoke all on function public.store_admin_idoom_retry(bigint, text) from public, anon, authenticated;
grant execute on function public.store_admin_idoom_retry(bigint, text) to authenticated;
