-- v1.12: IDOOM offer lookup before top-up. A lookup job carries no card: the phone opens
-- My IDOOM, types the line, reads "Offre" and reports it; nothing is bought.

alter table store.idoom_jobs
  add column kind text not null default 'charge' check (kind in ('charge', 'lookup')),
  alter column product_id drop not null,
  alter column order_id drop not null,
  alter column code_id drop not null,
  drop constraint idoom_jobs_status_check,
  add constraint idoom_jobs_status_check check (status in
    ('queued', 'claimed', 'success', 'likely_success', 'used_card', 'failed', 'review', 'cancelled', 'looked_up')),
  add constraint idoom_jobs_kind_shape check (
    (kind = 'charge' and product_id is not null and order_id is not null and code_id is not null) or
    (kind = 'lookup' and product_id is null and order_id is null and code_id is null));

create function private.store_admin_idoom_lookup_impl(p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  v_line text := regexp_replace(coalesce(p_line, ''), '[^0-9]', '', 'g');
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs where request_id = p_request_id;
  if not found then
    if v_line !~ '^0[0-9]{8,9}$' then raise exception 'INVALID_LINE'; end if;
    insert into store.idoom_jobs (kind, line, request_id, created_by)
    values ('lookup', v_line, p_request_id, auth.uid())
    returning * into j;
  end if;
  return query select j.id, j.status;
end;
$$;

-- Return types change, so the list and claim get _v2 versions next to the old ones (no drops).
-- The old claim (Rech-Doom 0.6.0) keeps working but never hands out lookup jobs.
create or replace function private.store_exec_claim_impl(p_token text)
returns table (job_id bigint, line text, code text)
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  j store.idoom_jobs;
begin
  if exists (select 1 from store.idoom_jobs x where x.executor_id = v_exec and x.status = 'claimed') then
    return;
  end if;
  select * into j from store.idoom_jobs x where x.status = 'queued' and x.kind = 'charge' order by x.id limit 1 for update skip locked;
  if not found then return; end if;
  update store.idoom_jobs set status = 'claimed', executor_id = v_exec, claimed_at = now() where id = j.id;
  return query select j.id, j.line, k.code from store.codes k where k.id = j.code_id;
end;
$$;

create function private.store_exec_claim_v2_impl(p_token text)
returns table (job_id bigint, kind text, line text, code text)
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  j store.idoom_jobs;
begin
  if exists (select 1 from store.idoom_jobs x where x.executor_id = v_exec and x.status = 'claimed') then
    return;
  end if;
  select * into j from store.idoom_jobs x where x.status = 'queued' order by x.id limit 1 for update skip locked;
  if not found then return; end if;
  update store.idoom_jobs set status = 'claimed', executor_id = v_exec, claimed_at = now() where id = j.id;
  return query select j.id, j.kind, j.line, (select k.code from store.codes k where k.id = j.code_id);
end;
$$;

create function private.store_admin_idoom_jobs_v2_impl(p_limit int)
returns table (id bigint, kind text, line text, product_name text, status text, outcome text, offer text, reply text,
               executor_name text, created_at timestamptz, finished_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query
  select j.id, j.kind, j.line, p.name, j.status, j.outcome, j.offer, j.reply, e.name, j.created_at, j.finished_at
  from store.idoom_jobs j
  left join store.products p on p.id = j.product_id
  left join store.executors e on e.id = j.executor_id
  order by j.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 200);
end;
$$;

-- Lookup outcome: LOOKUP_OK → looked_up (offer kept); anything else → failed. Charges as before.
create or replace function private.store_exec_report_impl(p_token text, p_job_id bigint, p_outcome text, p_offer text, p_reply text)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  v_kind text;
  v_status text;
begin
  select kind into v_kind from store.idoom_jobs where id = p_job_id and executor_id = v_exec and status = 'claimed';
  if not found then raise exception 'JOB_NOT_CLAIMED'; end if;
  v_status := case
    when v_kind = 'lookup' then case when p_outcome = 'LOOKUP_OK' then 'looked_up' else 'failed' end
    when p_outcome = 'SUCCESS_TEXT' then 'success'
    when p_outcome = 'BLANK_AFTER_SUBMIT' then 'likely_success'
    when p_outcome = 'VOUCHER_USED' then 'used_card'
    when p_outcome = 'PRE_SUBMIT_FAILED' then 'failed'
    else 'review' end;
  update store.idoom_jobs
     set status = v_status, outcome = left(p_outcome, 40), offer = left(p_offer, 120),
         reply = left(p_reply, 2000), finished_at = now()
   where id = p_job_id;
  return v_status;
end;
$$;

create function public.store_admin_idoom_lookup(p_line text, p_request_id uuid) returns table (job_id bigint, status text)
language sql set search_path = '' as $$ select * from private.store_admin_idoom_lookup_impl(p_line, p_request_id); $$;
create function public.store_admin_idoom_jobs_v2(p_limit int default 30)
returns table (id bigint, kind text, line text, product_name text, status text, outcome text, offer text, reply text,
               executor_name text, created_at timestamptz, finished_at timestamptz)
language sql set search_path = '' as $$ select * from private.store_admin_idoom_jobs_v2_impl(p_limit); $$;
create function public.store_exec_claim_v2(p_token text) returns table (job_id bigint, kind text, line text, code text)
language sql set search_path = '' as $$ select * from private.store_exec_claim_v2_impl(p_token); $$;

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
