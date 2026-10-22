-- v1.11: IDOOM direct top-up through the Android executor app Rech-Doom (amordz72/Rech-Doom).
-- The admin requests a top-up; the shop account buys one code through the normal ledger
-- (store_buy_core), and the phone claims the job, types it in My IDOOM and reports the raw reply.
-- The phone is transport only: the outcome mapping and every state change live here.

create table store.executors (
  id bigint generated always as identity primary key,
  name text not null check (length(btrim(name)) between 1 and 60),
  token_hash text not null unique,
  active boolean not null default true,
  last_seen_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now()
);

create table store.idoom_jobs (
  id bigint generated always as identity primary key,
  line text not null check (line ~ '^0[0-9]{8,9}$'),
  product_id bigint not null references store.products(id),
  order_id bigint not null references store.orders(id),
  code_id bigint not null unique references store.codes(id),
  status text not null default 'queued' check (status in
    ('queued', 'claimed', 'success', 'likely_success', 'used_card', 'failed', 'review', 'cancelled')),
  executor_id bigint references store.executors(id),
  outcome text,
  offer text,
  reply text,
  request_id uuid not null unique,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  finished_at timestamptz
);
create index idoom_jobs_queue on store.idoom_jobs (id) where status = 'queued';
create index on store.idoom_jobs (created_at desc);

-- Admin: buy one code for the shop and queue the top-up. Idempotent on p_request_id.
create function private.store_admin_idoom_create_impl(p_product_id bigint, p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  b record;
  v_line text := regexp_replace(coalesce(p_line, ''), '[^0-9]', '', 'g');
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs where request_id = p_request_id;
  if not found then
    if v_line !~ '^0[0-9]{8,9}$' then raise exception 'INVALID_LINE'; end if;
    select * into b from private.store_buy_core(private.store_shop_id(), p_product_id, 1, p_request_id);
    insert into store.idoom_jobs (line, product_id, order_id, code_id, request_id, created_by)
    select v_line, p_product_id, b.order_id, k.id, p_request_id, auth.uid()
    from store.codes k where k.order_id = b.order_id
    returning * into j;
  end if;
  return query select j.id, j.status;
end;
$$;

create function private.store_admin_idoom_jobs_impl(p_limit int)
returns table (id bigint, line text, product_name text, status text, outcome text, offer text, reply text,
               executor_name text, created_at timestamptz, finished_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query
  select j.id, j.line, p.name, j.status, j.outcome, j.offer, j.reply, e.name, j.created_at, j.finished_at
  from store.idoom_jobs j
  join store.products p on p.id = j.product_id
  left join store.executors e on e.id = j.executor_id
  order by j.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 200);
end;
$$;

-- Admin: cancel a job the phone has not claimed yet (its order stays; reverse it with the usual tools).
create function private.store_admin_idoom_cancel_impl(p_job_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  perform private.store_require_admin();
  update store.idoom_jobs set status = 'cancelled', finished_at = now()
  where id = p_job_id and status = 'queued'
  returning status into v;
  if v is null then raise exception 'NOT_CANCELLABLE'; end if;
  return v;
end;
$$;

-- Admin: create a phone executor. The token is returned once; only its hash is stored.
create function private.store_admin_executor_create_impl(p_name text)
returns table (executor_id bigint, token text)
language plpgsql security definer set search_path = '' as $$
declare
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id bigint;
begin
  perform private.store_require_admin();
  insert into store.executors (name, token_hash, created_by)
  values (btrim(p_name), encode(extensions.digest(v_token, 'sha256'), 'hex'), auth.uid())
  returning id into v_id;
  return query select v_id, v_token;
end;
$$;

create function private.store_exec_id(p_token text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v bigint;
begin
  update store.executors set last_seen_at = now()
  where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex') and active
  returning id into v;
  if v is null then raise exception 'INVALID_EXECUTOR'; end if;
  return v;
end;
$$;

-- Phone: take the oldest queued job. A phone with a job still claimed gets nothing:
-- an unfinished job is never handed out twice (no blind retry after Valider).
create function private.store_exec_claim_impl(p_token text)
returns table (job_id bigint, line text, code text)
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
  return query select j.id, j.line, k.code from store.codes k where k.id = j.code_id;
end;
$$;

-- Phone: report the raw outcome. Mapping (observed 2026-10-22):
--   SUCCESS_TEXT → success; BLANK_AFTER_SUBMIT (empty screen after Valider) → likely_success;
--   VOUCHER_USED ("Carte déjà utilisée !") → used_card (the code stays sold: never offered again);
--   PRE_SUBMIT_FAILED (stopped before Valider) → failed; anything else → review.
create function private.store_exec_report_impl(p_token text, p_job_id bigint, p_outcome text, p_offer text, p_reply text)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  v_status text := case p_outcome
    when 'SUCCESS_TEXT' then 'success'
    when 'BLANK_AFTER_SUBMIT' then 'likely_success'
    when 'VOUCHER_USED' then 'used_card'
    when 'PRE_SUBMIT_FAILED' then 'failed'
    else 'review' end;
begin
  update store.idoom_jobs
     set status = v_status, outcome = left(p_outcome, 40), offer = left(p_offer, 120),
         reply = left(p_reply, 2000), finished_at = now()
   where id = p_job_id and executor_id = v_exec and status = 'claimed';
  if not found then raise exception 'JOB_NOT_CLAIMED'; end if;
  return v_status;
end;
$$;

create function public.store_admin_idoom_create(p_product_id bigint, p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language sql set search_path = '' as $$ select * from private.store_admin_idoom_create_impl(p_product_id, p_line, p_request_id); $$;
create function public.store_admin_idoom_jobs(p_limit int default 30)
returns table (id bigint, line text, product_name text, status text, outcome text, offer text, reply text,
               executor_name text, created_at timestamptz, finished_at timestamptz)
language sql set search_path = '' as $$ select * from private.store_admin_idoom_jobs_impl(p_limit); $$;
create function public.store_admin_idoom_cancel(p_job_id bigint) returns text
language sql set search_path = '' as $$ select private.store_admin_idoom_cancel_impl(p_job_id); $$;
create function public.store_admin_executor_create(p_name text) returns table (executor_id bigint, token text)
language sql set search_path = '' as $$ select * from private.store_admin_executor_create_impl(p_name); $$;
create function public.store_exec_claim(p_token text) returns table (job_id bigint, line text, code text)
language sql set search_path = '' as $$ select * from private.store_exec_claim_impl(p_token); $$;
create function public.store_exec_report(p_token text, p_job_id bigint, p_outcome text, p_offer text, p_reply text)
returns text
language sql set search_path = '' as $$ select private.store_exec_report_impl(p_token, p_job_id, p_outcome, p_offer, p_reply); $$;

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
