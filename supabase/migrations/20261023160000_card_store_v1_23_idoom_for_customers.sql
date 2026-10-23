-- v1.23 — تعبئة إيدوم للزبائن (owner decision 2026-10-23, all four proposals accepted)
--  * Per-customer switch (store.customers.idoom_topup, off by default), set by the owner.
--  * Price: the customer's usual price for that card (store_buy_core), no service fee.
--  * The card is bought from the customer's balance when the request is made (balance checked at once),
--    and held by the job until the Rech-Doom phone submits it.
--  * Outcomes, automatic: success / likely_success → done; stopped before Valider → full refund and the
--    card back to stock (existing store_idoom_return_card); card already used → refund, then ONE automatic
--    retry with another card from the customer's balance (the used card is the shop's loss), or the refund
--    stays if no card / no balance; review → the owner decides (bell): done, or not done with a full refund.
--  * A request is refused while no Rech-Doom phone is online.
--  * The customer cannot cancel a first attempt; only the automatic second attempt while it still waits.
--  * The customer never sees the card code of a top-up order (he could use it before the phone and get the
--    automatic retry for free); those cards cannot be reported either.
-- Additive only: new columns, new functions, create or replace of existing ones (same signatures).
-- Admin jobs keep their behaviour; Rech-Doom (claim / take_code / report) keeps the same calls.

alter table store.customers add column idoom_topup boolean not null default false;
alter table store.idoom_jobs add column customer_id bigint references store.customers(id);
alter table store.idoom_jobs add column attempt int not null default 1;
-- A customer's order bought for an IDOOM top-up (both attempts): its card is never shown to him.
alter table store.orders add column idoom_line text;
create index on store.idoom_jobs (customer_id, id desc) where customer_id is not null;
-- created_by (uuid, not null) is the owner's id for his jobs; customer jobs carry this fixed marker
-- and the real buyer in customer_id.
comment on column store.idoom_jobs.customer_id is 'Customer who requested the top-up (null = owner job, paid by the shop account)';

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create function private.store_idoom_phone_online() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from store.executors e where e.active and e.last_seen_at > now() - interval '2 minutes');
$$;

-- A customer allowed to use the service (active account with the switch on); returns his id.
create function private.store_idoom_customer(p_token text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  if not exists (select 1 from store.customers c where c.id = v and c.idoom_topup and not c.is_shop) then
    raise exception 'IDOOM_NOT_ENABLED';
  end if;
  return v;
end;
$$;

-- Card used already, customer job: refund it (the card stays sold, never offered again), then one retry
-- with another card. Returns true when the job was queued again.
create function private.store_idoom_used_card_retry(p_job_id bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  e store.wallet_entries;
  b record;
begin
  select * into j from store.idoom_jobs where id = p_job_id for update;
  if j.customer_id is null or j.order_id is null then return false; end if;
  select * into e from store.wallet_entries w where w.order_id = j.order_id and w.kind = 'purchase';
  if found and not exists (select 1 from store.wallet_entries x where x.reverses_id = e.id) then
    -- the customer sees a general reason; the details stay in the job (owner only)
    perform private.store_post_entry(e.customer_id, 'purchase_refund', e.amount, 'IDOOM: فشل الشحن، أُعيد المبلغ', e.order_id, e.id, null, null);
  end if;
  update store.orders set status = 'refunded' where id = j.order_id;
  if j.attempt >= 2 then
    update store.idoom_jobs set reply = left('[استُرد المبلغ] ' || coalesce(reply, ''), 2000) where id = j.id;
    return false;
  end if;
  begin
    select * into b from private.store_buy_core(j.customer_id, j.product_id, 1, gen_random_uuid());
    update store.orders set idoom_line = j.line where id = b.order_id;
  exception when others then
    update store.idoom_jobs set reply = left('[استُرد المبلغ؛ لا بطاقة أخرى: ' || sqlerrm || '] ' || coalesce(reply, ''), 2000)
     where id = j.id;
    return false;
  end;
  update store.idoom_jobs
     set reply = left('[محاولة 1 بطلب ' || j.order_id || ': البطاقة كانت مستعملة، استُرد المبلغ] ' || coalesce(reply, ''), 2000),
         order_id = b.order_id, code_id = (select k.id from store.codes k where k.order_id = b.order_id),
         attempt = j.attempt + 1, status = 'queued', outcome = null, offer = null,
         executor_id = null, claimed_at = null, finished_at = null
   where id = j.id;
  return true;
end;
$$;

-- ---------------------------------------------------------------------
-- Customer
-- ---------------------------------------------------------------------
create function private.store_idoom_status_impl(p_token text)
returns table (enabled boolean, phone_online boolean)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return query select coalesce((select c.idoom_topup and not c.is_shop from store.customers c where c.id = v), false),
                      private.store_idoom_phone_online();
end;
$$;

-- Buy the card now from the customer's balance and queue the top-up. Idempotent on p_request_id.
create function private.store_idoom_create_impl(p_token text, p_product_id bigint, p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_idoom_customer(p_token);
  j store.idoom_jobs;
  b record;
  v_line text;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into j from store.idoom_jobs x where x.request_id = p_request_id;
  if found then
    if j.customer_id is distinct from v then raise exception 'REQUEST_ID_CONFLICT'; end if;
  else
    v_line := private.store_idoom_line(p_line);
    perform private.store_idoom_check_product(p_product_id, v_line);
    if not private.store_idoom_phone_online() then raise exception 'IDOOM_PHONE_OFFLINE'; end if;
    -- one at a time per line, a few at a time per customer
    if exists (select 1 from store.idoom_jobs x where x.customer_id = v and x.line = v_line and x.status in ('queued', 'claimed')) then
      raise exception 'IDOOM_LINE_BUSY';
    end if;
    if (select count(*) from store.idoom_jobs x where x.customer_id = v and x.status in ('queued', 'claimed')) >= 3
       or (select count(*) from store.idoom_jobs x where x.customer_id = v and x.created_at > now() - interval '1 hour') >= 10 then
      raise exception 'IDOOM_TOO_MANY';
    end if;
    select * into b from private.store_buy_core(v, p_product_id, 1, p_request_id);
    update store.orders set idoom_line = v_line where id = b.order_id;
    insert into store.idoom_jobs (line, product_id, order_id, code_id, request_id, created_by, customer_id)
    select v_line, p_product_id, b.order_id, k.id, p_request_id, '00000000-0000-0000-0000-000000000000'::uuid, v
    from store.codes k where k.order_id = b.order_id
    returning * into j;
  end if;
  return query select j.id, j.status;
end;
$$;

create function private.store_idoom_jobs_impl(p_token text, p_limit int, p_offset int)
returns table (job_id bigint, line text, product_name text, status text, offer text, charged_amount bigint,
               refunded boolean, attempt int, created_at timestamptz, finished_at timestamptz, total_count bigint)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select j.id, j.line, p.name, j.status, j.offer, o.charged_amount, coalesce(o.status = 'refunded', false), j.attempt,
         j.created_at, j.finished_at, count(*) over ()
  from store.idoom_jobs j
  join store.products p on p.id = j.product_id
  left join store.orders o on o.id = j.order_id
  where j.customer_id = v
  order by j.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- The customer can cancel only the automatic second attempt, while it waits for the phone (owner decision:
-- no cancel on the first attempt). Full refund, card back to stock.
create function private.store_idoom_cancel_impl(p_token text, p_job_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  v_status text;
begin
  update store.idoom_jobs x set status = 'cancelled', finished_at = now()
   where x.id = p_job_id and x.customer_id = v and x.status = 'queued' and x.attempt >= 2
  returning x.status into v_status;
  if v_status is null then raise exception 'NOT_CANCELLABLE'; end if;
  perform private.store_idoom_return_card(p_job_id);
  return v_status;
end;
$$;

-- Last known offer of a line, from this customer's own top-ups only.
create function private.store_idoom_line_info_impl(p_token text, p_line text)
returns table (offer text, checked_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  v_line text := private.store_idoom_line(p_line);
begin
  return query
  select j.offer, coalesce(j.finished_at, j.claimed_at)
  from store.idoom_jobs j
  where j.customer_id = v and j.line = v_line and j.offer is not null and j.status <> 'cancelled'
  order by coalesce(j.finished_at, j.claimed_at) desc nulls last, j.id desc
  limit 1;
end;
$$;

-- ---------------------------------------------------------------------
-- Owner
-- ---------------------------------------------------------------------
create function private.store_admin_set_idoom_topup_impl(p_customer_id bigint, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.customers c set idoom_topup = coalesce(p_enabled, false) where c.id = p_customer_id and not c.is_shop;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
end;
$$;

create function private.store_admin_idoom_topup_customers_impl() returns setof bigint
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select c.id from store.customers c where c.idoom_topup and not c.is_shop order by c.id;
end;
$$;

-- Jobs list with who asked (null = the owner).
create function private.store_admin_idoom_jobs_v3_impl(p_limit int)
returns table (id bigint, kind text, line text, product_name text, status text, outcome text, offer text, reply text,
               executor_name text, created_at timestamptz, finished_at timestamptz, customer_name text, attempt int)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query
  select j.id, j.kind, j.line, p.name, j.status, j.outcome, j.offer, j.reply, e.name, j.created_at, j.finished_at,
         c.name, j.attempt
  from store.idoom_jobs j
  left join store.products p on p.id = j.product_id
  left join store.executors e on e.id = j.executor_id
  left join store.customers c on c.id = j.customer_id
  order by j.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 200);
end;
$$;

-- Bell: customers' top-ups waiting for the owner's decision.
create function private.store_admin_idoom_review_count_impl() returns bigint
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return (select count(*) from store.idoom_jobs j where j.customer_id is not null and j.status = 'review');
end;
$$;

-- Owner decides a customer's job in review: done, or not done → full refund (the card stays sold:
-- it may have been submitted). Clears it from the bell.
create function private.store_admin_idoom_resolve_impl(p_job_id bigint, p_done boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  e store.wallet_entries;
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs x where x.id = p_job_id and x.customer_id is not null and x.status = 'review' for update;
  if not found then raise exception 'NOT_IN_REVIEW'; end if;
  if coalesce(p_done, false) then
    update store.idoom_jobs set status = 'success', reply = left('[قرار المحل: تمت] ' || coalesce(reply, ''), 2000) where id = j.id;
    return 'success';
  end if;
  select * into e from store.wallet_entries w where w.order_id = j.order_id and w.kind = 'purchase';
  if found and not exists (select 1 from store.wallet_entries x where x.reverses_id = e.id) then
    perform private.store_post_entry(e.customer_id, 'purchase_refund', e.amount, 'IDOOM: لم تتم التعبئة، أُعيد المبلغ', e.order_id, e.id, null, null);
  end if;
  update store.orders set status = 'refunded' where id = j.order_id;
  update store.idoom_jobs set status = 'failed', reply = left('[قرار المحل: لم تتم، استُرد المبلغ] ' || coalesce(reply, ''), 2000) where id = j.id;
  return 'failed';
end;
$$;

-- ---------------------------------------------------------------------
-- Existing functions, same signatures (create or replace)
-- ---------------------------------------------------------------------
-- Report: as before, plus the automatic retry of a customer's used card.
create or replace function private.store_exec_report_impl(p_token text, p_job_id bigint, p_outcome text, p_offer text, p_reply text)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  v_kind text;
  v_customer bigint;
  v_status text;
begin
  select kind, customer_id into v_kind, v_customer from store.idoom_jobs
   where id = p_job_id and executor_id = v_exec and status = 'claimed';
  if not found then raise exception 'JOB_NOT_CLAIMED'; end if;
  v_status := case
    when v_kind = 'lookup' then case when p_outcome = 'LOOKUP_OK' then 'looked_up' else 'failed' end
    when p_outcome = 'SUCCESS_TEXT' then 'success'
    when p_outcome = 'BLANK_AFTER_SUBMIT' then 'likely_success'
    when p_outcome = 'VOUCHER_USED' then 'used_card'
    when p_outcome = 'PRE_SUBMIT_FAILED' then 'failed'
    else 'review' end;
  update store.idoom_jobs
     set status = v_status, outcome = left(p_outcome, 40), offer = coalesce(left(p_offer, 120), offer),
         reply = left(p_reply, 2000), finished_at = now()
   where id = p_job_id;
  if v_kind = 'charge' and p_outcome = 'PRE_SUBMIT_FAILED' then
    perform private.store_idoom_return_card(p_job_id);
  elsif v_kind = 'charge' and v_status = 'used_card' and v_customer is not null then
    perform private.store_idoom_used_card_retry(p_job_id);
  end if;
  return v_status;
end;
$$;

-- Owner cancel: a customer's waiting job also gives the card back and refunds him
-- (owner jobs hold no card while queued, so nothing changes for them).
create or replace function private.store_admin_idoom_cancel_impl(p_job_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  perform private.store_require_admin();
  update store.idoom_jobs set status = 'cancelled', finished_at = now()
  where id = p_job_id and status = 'queued'
  returning status into v;
  if v is null then raise exception 'NOT_CANCELLABLE'; end if;
  perform private.store_idoom_return_card(p_job_id);
  return v;
end;
$$;

-- Owner retry with the same card: owner jobs only (a customer whose job stopped was refunded; he asks again).
create or replace function private.store_admin_idoom_retry_impl(p_job_id bigint, p_line text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  v_line text;
  v text;
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs
   where id = p_job_id and kind = 'charge' and status = 'failed' and outcome = 'PRE_SUBMIT_FAILED' and customer_id is null
   for update;
  if not found then raise exception 'NOT_RETRYABLE'; end if;
  v_line := private.store_idoom_line(coalesce(nullif(p_line, ''), j.line));
  perform private.store_idoom_check_product(j.product_id, v_line);
  update store.idoom_jobs
     set line = v_line,
         reply = left('[محاولة سابقة ' || line || ': ' || coalesce(outcome, '') || '] ' || coalesce(reply, ''), 2000),
         status = 'queued', outcome = null, offer = null, executor_id = null, claimed_at = null, finished_at = null
   where id = j.id
  returning status into v;
  return v;
end;
$$;

-- Customer codes: the card of an IDOOM top-up is never shown (he could use it before the phone).
create or replace function private.store_order_codes_impl(p_token text, p_order_id bigint)
returns table (code text, serial text, status text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v bigint := private.store_session_customer(p_token);
  v_line text;
begin
  select o.idoom_line into v_line from store.orders o where o.id = p_order_id and o.customer_id = v;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  return query
  select case when v_line is null then k.code else 'تعبئة إيدوم للخط ' || v_line end,
         case when v_line is null then k.serial end, k.status
  from store.codes k where k.order_id = p_order_id order by k.id;
end;
$$;

create or replace function private.store_order_codes_v2_impl(p_token text, p_order_id bigint)
returns table (code_id bigint, code text, serial text, status text, report_status text, report_reason text, can_report boolean)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
declare v_days int := (select s.report_days from store.settings s where s.id = 1);
begin
  if not exists (select 1 from store.orders o where o.id = p_order_id and o.customer_id = v) then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  return query
  select k.id,
         case when o.idoom_line is null then k.code else 'تعبئة إيدوم للخط ' || o.idoom_line end,
         case when o.idoom_line is null then k.serial end,
         k.status, r.status, r.reason,
         (o.idoom_line is null and r.id is null and k.status = 'sold' and o.status = 'done'
          and k.sold_at > now() - make_interval(days => v_days))
  from store.codes k join store.orders o on o.id = k.order_id
  left join store.card_reports r on r.code_id = k.id
  where k.order_id = p_order_id order by k.id;
end;
$$;

-- Reports: a top-up card is not the customer's card to report (its result is the job's status).
create or replace function private.store_report_code_impl(p_token text, p_code_id bigint, p_reason text, p_note text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  v_days int := (select s.report_days from store.settings s where s.id = 1);
  k record;
  v_id bigint;
begin
  if p_reason is null or p_reason not in ('used', 'not_found', 'rejected', 'other') then raise exception 'INVALID_REASON'; end if;
  select c.id, c.status, c.sold_at, o.status as order_status, o.idoom_line into k
  from store.codes c join store.orders o on o.id = c.order_id
  where c.id = p_code_id and o.customer_id = v
  for update of c;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if k.status <> 'sold' or k.order_status <> 'done' or k.idoom_line is not null then raise exception 'NOT_REPORTABLE'; end if;
  if k.sold_at <= now() - make_interval(days => v_days) then raise exception 'REPORT_WINDOW_CLOSED'; end if;
  if exists (select 1 from store.card_reports r where r.code_id = p_code_id) then raise exception 'ALREADY_REPORTED'; end if;
  insert into store.card_reports (code_id, customer_id, reason, note)
  values (p_code_id, v, p_reason, nullif(left(btrim(coalesce(p_note, '')), 500), '')) returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------
create function public.store_idoom_status(p_token text) returns table (enabled boolean, phone_online boolean)
language sql set search_path = '' as $$ select * from private.store_idoom_status_impl(p_token); $$;
create function public.store_idoom_create(p_token text, p_product_id bigint, p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language sql set search_path = '' as $$ select * from private.store_idoom_create_impl(p_token, p_product_id, p_line, p_request_id); $$;
create function public.store_idoom_jobs(p_token text, p_limit int, p_offset int)
returns table (job_id bigint, line text, product_name text, status text, offer text, charged_amount bigint,
               refunded boolean, attempt int, created_at timestamptz, finished_at timestamptz, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_idoom_jobs_impl(p_token, p_limit, p_offset); $$;
create function public.store_idoom_cancel(p_token text, p_job_id bigint) returns text
language sql set search_path = '' as $$ select private.store_idoom_cancel_impl(p_token, p_job_id); $$;
create function public.store_idoom_line_info(p_token text, p_line text) returns table (offer text, checked_at timestamptz)
language sql set search_path = '' as $$ select * from private.store_idoom_line_info_impl(p_token, p_line); $$;
create function public.store_admin_set_idoom_topup(p_customer_id bigint, p_enabled boolean) returns void
language sql set search_path = '' as $$ select private.store_admin_set_idoom_topup_impl(p_customer_id, p_enabled); $$;
create function public.store_admin_idoom_topup_customers() returns setof bigint
language sql set search_path = '' as $$ select * from private.store_admin_idoom_topup_customers_impl(); $$;
create function public.store_admin_idoom_jobs_v3(p_limit int default 30)
returns table (id bigint, kind text, line text, product_name text, status text, outcome text, offer text, reply text,
               executor_name text, created_at timestamptz, finished_at timestamptz, customer_name text, attempt int)
language sql set search_path = '' as $$ select * from private.store_admin_idoom_jobs_v3_impl(p_limit); $$;
create function public.store_admin_idoom_resolve(p_job_id bigint, p_done boolean) returns text
language sql set search_path = '' as $$ select private.store_admin_idoom_resolve_impl(p_job_id, p_done); $$;
create function public.store_admin_idoom_review_count() returns bigint
language sql set search_path = '' as $$ select private.store_admin_idoom_review_count_impl(); $$;

-- ---------------------------------------------------------------------
-- Grants: helpers private to the functions; the rest by the usual rule
-- ---------------------------------------------------------------------
revoke all on function private.store_idoom_phone_online() from public, anon, authenticated;
revoke all on function private.store_idoom_customer(text) from public, anon, authenticated;
revoke all on function private.store_idoom_used_card_retry(bigint) from public, anon, authenticated;
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_idoom_status_impl', 'store_idoom_status', 'store_idoom_create_impl', 'store_idoom_create',
                        'store_idoom_jobs_impl', 'store_idoom_jobs', 'store_idoom_cancel_impl', 'store_idoom_cancel',
                        'store_idoom_line_info_impl', 'store_idoom_line_info',
                        'store_admin_set_idoom_topup_impl', 'store_admin_set_idoom_topup',
                        'store_admin_idoom_topup_customers_impl', 'store_admin_idoom_topup_customers',
                        'store_admin_idoom_jobs_v3_impl', 'store_admin_idoom_jobs_v3',
                        'store_admin_idoom_review_count_impl', 'store_admin_idoom_review_count',
                        'store_admin_idoom_resolve_impl', 'store_admin_idoom_resolve')
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
end;
$$;
