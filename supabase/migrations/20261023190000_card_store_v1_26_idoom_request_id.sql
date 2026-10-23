-- v1.26 — fix: a customer could read his IDOOM top-up card before the phone used it (found 2026-10-23)
-- v1.23 bought the card with the customer's own request id. store_buy is idempotent on that id, so
-- calling store_buy again with it returned the order and its card code; he could redeem it himself and
-- still get the automatic second attempt.
--  1. New customer top-ups buy the card with an internal request id (idempotency stays on the job's id).
--  2. store_buy refuses any request id that belongs to a top-up: its job (IDOOM or game), or its order
--     (IDOOM line or player id), which also covers the orders created before this fix.
-- Same signatures (create or replace): nothing removed, grants kept.

create or replace function private.store_buy_impl(p_token text, p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  -- a request id that belongs to a top-up (its job, or its order before this fix) is never a purchase
  if exists (select 1 from store.orders o where o.request_id = p_request_id
             and (o.idoom_line is not null or o.player_id is not null))
     or exists (select 1 from store.idoom_jobs j where j.request_id = p_request_id)
     or exists (select 1 from store.game_orders g where g.request_id = p_request_id) then
    raise exception 'REQUEST_ID_CONFLICT';
  end if;
  return query select * from private.store_buy_core(v, p_product_id, p_qty, p_request_id);
end;
$$;

create or replace function private.store_idoom_create_impl(p_token text, p_product_id bigint, p_line text, p_request_id uuid)
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
    -- own request id for the purchase: the customer's id must never lead back to the card (store_buy replay)
    select * into b from private.store_buy_core(v, p_product_id, 1, gen_random_uuid());
    update store.orders set idoom_line = v_line where id = b.order_id;
    insert into store.idoom_jobs (line, product_id, order_id, code_id, request_id, created_by, customer_id)
    select v_line, p_product_id, b.order_id, k.id, p_request_id, '00000000-0000-0000-0000-000000000000'::uuid, v
    from store.codes k where k.order_id = b.order_id
    returning * into j;
  end if;
  return query select j.id, j.status;
end;
$$;
