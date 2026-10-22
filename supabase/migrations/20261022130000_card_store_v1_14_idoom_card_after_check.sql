-- v1.14: the card is taken only after the line is checked. «شحن» queues a job with the product
-- only; the phone checks the line in My IDOOM, then asks for the code (store_exec_take_code) and
-- only then is one card bought for the shop. Any stop before Valider returns the card to stock
-- (it was never submitted nor seen) and refunds the shop.
-- Lookups are limited to protect the phone from My IDOOM blocks: a line checked in the last
-- 15 minutes reuses that result; at most 3 checks per line and 20 per account per hour.

alter table store.idoom_jobs drop constraint idoom_jobs_kind_shape;
alter table store.idoom_jobs add constraint idoom_jobs_kind_shape check (
  (kind = 'charge' and product_id is not null) or
  (kind = 'lookup' and product_id is null and order_id is null and code_id is null));

-- Card back to stock + shop refund; the job keeps the refunded order for history.
create or replace function private.store_idoom_return_card(p_job_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  e store.wallet_entries;
begin
  select * into j from store.idoom_jobs where id = p_job_id for update;
  if j.code_id is null then return; end if;
  select * into e from store.wallet_entries w where w.order_id = j.order_id and w.kind = 'purchase';
  if found and not exists (select 1 from store.wallet_entries x where x.reverses_id = e.id) then
    perform private.store_post_entry(e.customer_id, 'purchase_refund', e.amount, 'IDOOM: البطاقة لم تُرسل', e.order_id, e.id, null, null);
  end if;
  update store.orders set status = 'refunded' where id = j.order_id;
  update store.codes set status = 'available', order_id = null, sold_at = null where id = j.code_id and status = 'sold';
  update store.idoom_jobs
     set code_id = null, reply = left('[أُرجعت البطاقة إلى المخزن] ' || coalesce(reply, ''), 2000)
   where id = j.id;
end;
$$;

create or replace function private.store_admin_idoom_create_impl(p_product_id bigint, p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare j store.idoom_jobs;
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs where request_id = p_request_id;
  if not found then
    if not exists (select 1 from store.products p join store.brands b on b.id = p.brand_id
                   where p.id = p_product_id and p.active and b.active) then
      raise exception 'PRODUCT_NOT_FOUND';
    end if;
    if not exists (select 1 from store.codes k where k.product_id = p_product_id and k.status = 'available') then
      raise exception 'OUT_OF_STOCK';
    end if;
    insert into store.idoom_jobs (line, product_id, request_id, created_by)
    values (private.store_idoom_line(p_line), p_product_id, p_request_id, auth.uid())
    returning * into j;
  end if;
  return query select j.id, j.status;
end;
$$;

create or replace function private.store_admin_idoom_lookup_impl(p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  v_line text;
  v_admin uuid := private.store_require_admin();
begin
  select * into j from store.idoom_jobs where request_id = p_request_id;
  if not found then
    v_line := private.store_idoom_line(p_line);
    -- reuse a pending check or a fresh result for the same line
    select * into j from store.idoom_jobs x
     where x.kind = 'lookup' and x.line = v_line
       and (x.status in ('queued', 'claimed') or (x.status = 'looked_up' and x.finished_at > now() - interval '15 minutes'))
     order by x.id desc limit 1;
    if not found then
      if (select count(*) from store.idoom_jobs x where x.kind = 'lookup' and x.line = v_line
            and x.created_at > now() - interval '1 hour') >= 3 then
        raise exception 'RATE_LIMIT_LINE';
      end if;
      if (select count(*) from store.idoom_jobs x where x.kind = 'lookup' and x.created_by = v_admin
            and x.created_at > now() - interval '1 hour') >= 20 then
        raise exception 'RATE_LIMIT_ACCOUNT';
      end if;
      insert into store.idoom_jobs (kind, line, request_id, created_by)
      values ('lookup', v_line, p_request_id, v_admin)
      returning * into j;
    end if;
  end if;
  return query select j.id, j.status;
end;
$$;

-- Phone, after reading the offer for the same line: buy one card now and get its code.
-- Idempotent per job while the card is held (a repeated call returns the same code).
create function private.store_exec_take_code_impl(p_token text, p_job_id bigint, p_offer text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  j store.idoom_jobs;
  b record;
  v_code text;
begin
  select * into j from store.idoom_jobs
   where id = p_job_id and executor_id = v_exec and status = 'claimed' and kind = 'charge' for update;
  if not found then raise exception 'JOB_NOT_CLAIMED'; end if;
  if j.code_id is null then
    select * into b from private.store_buy_core(private.store_shop_id(), j.product_id, 1, gen_random_uuid());
    update store.idoom_jobs
       set order_id = b.order_id, offer = left(p_offer, 120),
           code_id = (select k.id from store.codes k where k.order_id = b.order_id)
     where id = j.id
    returning * into j;
  end if;
  select k.code into v_code from store.codes k where k.id = j.code_id;
  return v_code;
end;
$$;

-- Report: a charge stopped before Valider gives its card back.
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
     set status = v_status, outcome = left(p_outcome, 40), offer = coalesce(left(p_offer, 120), offer),
         reply = left(p_reply, 2000), finished_at = now()
   where id = p_job_id;
  if v_kind = 'charge' and p_outcome = 'PRE_SUBMIT_FAILED' then
    perform private.store_idoom_return_card(p_job_id);
  end if;
  return v_status;
end;
$$;

-- Admin: phones and when each last contacted the store.
create function private.store_admin_executors_impl()
returns table (id bigint, name text, active boolean, last_seen_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select e.id, e.name, e.active, e.last_seen_at from store.executors e order by e.last_seen_at desc nulls last, e.id desc;
end;
$$;

create function public.store_exec_take_code(p_token text, p_job_id bigint, p_offer text) returns text
language sql set search_path = '' as $$ select private.store_exec_take_code_impl(p_token, p_job_id, p_offer); $$;
create function public.store_admin_executors()
returns table (id bigint, name text, active boolean, last_seen_at timestamptz)
language sql set search_path = '' as $$ select * from private.store_admin_executors_impl(); $$;

revoke all on function private.store_idoom_return_card(bigint) from public, anon, authenticated;
revoke all on function private.store_exec_take_code_impl(text, bigint, text) from public, anon, authenticated;
grant execute on function private.store_exec_take_code_impl(text, bigint, text) to anon, authenticated;
revoke all on function public.store_exec_take_code(text, bigint, text) from public, anon, authenticated;
grant execute on function public.store_exec_take_code(text, bigint, text) to anon, authenticated;
revoke all on function private.store_admin_executors_impl() from public, anon, authenticated;
grant execute on function private.store_admin_executors_impl() to authenticated;
revoke all on function public.store_admin_executors() from public, anon, authenticated;
grant execute on function public.store_admin_executors() to authenticated;
