-- card-store v1.41: «تحديد» in «فليكسي المحلات» (owner 2026-10-29, mockup agreed, «نفذ»).
-- The owner selects shops (e.g. all traders) and sets, per service, «سماح / منع» and a rate, saved
-- at once for all of them; then adjusts one shop with the same window.
--
-- * «منع» is a FLAG per shop per service (flexy_block_*), apart from the rate: the rate stays and
--   comes back with «سماح». A shop without a rate stays closed even when allowed (no rate = no sale).
-- * store_flexy_create_v3 refuses a blocked service (FLEXY_SERVICE_BLOCKED); status_v3 tells the shop
--   screen which operators it may send to; customers_v3 shows the flags.
-- * store_admin_flexy_bulk applies rate / block / enabled / max to a list of shops in one call.
-- Nothing dropped; v2 functions stay as they are.

alter table store.customers add column if not exists flexy_block_630 boolean not null default false;
alter table store.customers add column if not exists flexy_block_offer boolean not null default false;
alter table store.customers add column if not exists flexy_block_ooredoo boolean not null default false;
alter table store.customers add column if not exists flexy_block_djezzy boolean not null default false;

create or replace function private.store_flexy_create_v3_impl(p_token text, p_kind text, p_phone text, p_amount int,
                                                              p_offer_code text, p_offer_label text, p_request_id uuid)
returns table (job_id bigint, status text, core_key text, phone text, amount int, created_at timestamptz, reused boolean)
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  c store.customers;
  s store.settings;
  j store.flexy_jobs;
  e store.wallet_entries;
  v_phone text;
  v_rate numeric;
  v_block boolean;
  v_min int := 40;
  v_charge bigint;
  v_label text;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into j from store.flexy_jobs x where x.request_id = p_request_id;
  if found then
    if j.customer_id is distinct from v then raise exception 'REQUEST_ID_CONFLICT'; end if;
    return query select j.id, j.status, j.core_key, j.phone, j.amount, j.created_at, true;
    return;
  end if;

  select * into c from store.customers x where x.id = v;
  select * into s from store.settings x where x.id = 1;
  if not c.flexy_enabled or c.is_shop then raise exception 'FLEXY_NOT_ENABLED'; end if;
  if not s.flexy_open then raise exception 'FLEXY_CLOSED'; end if;
  v_phone := private.store_flexy_phone_v2(p_phone);
  if p_kind = '630' then
    if p_offer_code is not null or p_offer_label is not null then raise exception 'FLEXY_BAD_REQUEST'; end if;
    if left(v_phone, 2) = '06' then v_rate := c.flexy_rate_630; v_block := c.flexy_block_630;
    elsif left(v_phone, 2) = '07' then v_rate := c.flexy_rate_630_djezzy; v_block := c.flexy_block_djezzy;
    else v_rate := c.flexy_rate_630_ooredoo; v_block := c.flexy_block_ooredoo; v_min := 10;
    end if;
    if v_block then raise exception 'FLEXY_SERVICE_BLOCKED'; end if;
    if v_rate is null then raise exception 'FLEXY_OPERATOR_NOT_OPEN'; end if;
  elsif p_kind = 'offer' then
    if left(v_phone, 2) <> '06' then raise exception 'FLEXY_OFFER_OPERATOR_NOT_READY'; end if;
    if c.flexy_block_offer then raise exception 'FLEXY_SERVICE_BLOCKED'; end if;
    v_label := btrim(coalesce(p_offer_label, ''));
    if v_label !~ '^[A-Za-z][A-Za-z ]{1,30} [0-9]{2,5}$' or p_amount is null
       or substring(v_label from '([0-9]+)$')::int <> p_amount then
      raise exception 'FLEXY_OFFER_INVALID';
    end if;
    v_rate := c.flexy_rate_offer;
    if v_rate is null then raise exception 'FLEXY_RATE_MISSING'; end if;
  else
    raise exception 'FLEXY_BAD_REQUEST';
  end if;
  if p_amount is null or p_amount < v_min or p_amount > coalesce(c.flexy_max, s.flexy_default_max) then
    raise exception 'FLEXY_AMOUNT_OUT_OF_RANGE';
  end if;

  perform 1 from store.customers x where x.id = v for update;
  if exists (select 1 from store.flexy_jobs x where x.phone = v_phone and x.status in ('queued', 'sent')) then
    raise exception 'FLEXY_PHONE_BUSY';
  end if;
  if (select count(*) from store.flexy_jobs x where x.customer_id = v and x.status in ('queued', 'sent')) >= 3
     or (select count(*) from store.flexy_jobs x where x.customer_id = v and x.created_at > now() - interval '1 hour') >= 30 then
    raise exception 'FLEXY_TOO_MANY';
  end if;

  v_charge := p_amount - round(p_amount * v_rate / 100);
  e := private.store_post_entry(v, 'flexy', v_charge,
         case when p_kind = 'offer' then 'عرض ' || v_label || ' إلى ' || v_phone
              else 'فليكسي ' || p_amount || ' دج إلى ' || v_phone end,
         null, null, null, null);
  insert into store.flexy_jobs (customer_id, request_id, core_key, kind, phone, amount, offer_code, offer_label, charged, entry_id)
  values (v, p_request_id, 'cs_' || replace(p_request_id::text, '-', ''), p_kind, v_phone, p_amount,
          v_label, v_label, v_charge, e.id)
  returning * into j;
  return query select j.id, j.status, j.core_key, j.phone, j.amount, j.created_at, false;
end;
$$;
create or replace function public.store_flexy_create_v3(p_token text, p_kind text, p_phone text, p_amount int,
                                                        p_offer_code text, p_offer_label text, p_request_id uuid)
returns table (job_id bigint, status text, core_key text, phone text, amount int, created_at timestamptz, reused boolean)
language sql as $$ select * from private.store_flexy_create_v3_impl(p_token, p_kind, p_phone, p_amount, p_offer_code, p_offer_label, p_request_id) $$;

-- The shop's status: a service is open for it when it has a rate and is not blocked.
create or replace function private.store_flexy_status_v3_impl(p_token text)
returns table (enabled boolean, open boolean, max_amount int, offers boolean, mobilis boolean, djezzy boolean, ooredoo boolean)
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  c store.customers;
  s store.settings;
begin
  select * into c from store.customers x where x.id = v;
  select * into s from store.settings x where x.id = 1;
  return query select c.flexy_enabled and not c.is_shop,
                      coalesce(s.flexy_open, false),
                      coalesce(c.flexy_max, s.flexy_default_max),
                      c.flexy_rate_offer is not null and not c.flexy_block_offer,
                      c.flexy_rate_630 is not null and not c.flexy_block_630,
                      c.flexy_rate_630_djezzy is not null and not c.flexy_block_djezzy,
                      c.flexy_rate_630_ooredoo is not null and not c.flexy_block_ooredoo;
end;
$$;
create or replace function public.store_flexy_status_v3(p_token text)
returns table (enabled boolean, open boolean, max_amount int, offers boolean, mobilis boolean, djezzy boolean, ooredoo boolean)
language sql as $$ select * from private.store_flexy_status_v3_impl(p_token) $$;

-- «نسب المحلات» with the block flags.
create or replace function private.store_admin_flexy_customers_v3_impl()
returns table (customer_id bigint, name text, enabled boolean, role text, rate_630 numeric, rate_offer numeric, max_amount int,
               rate_630_djezzy numeric, rate_630_ooredoo numeric,
               block_630 boolean, block_offer boolean, block_ooredoo boolean, block_djezzy boolean)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select c.id, c.name, c.flexy_enabled, c.flexy_role, c.flexy_rate_630, c.flexy_rate_offer, c.flexy_max,
                      c.flexy_rate_630_djezzy, c.flexy_rate_630_ooredoo,
                      c.flexy_block_630, c.flexy_block_offer, c.flexy_block_ooredoo, c.flexy_block_djezzy
  from store.customers c where not c.is_shop order by c.flexy_enabled desc, c.name;
end;
$$;
create or replace function public.store_admin_flexy_customers_v3()
returns table (customer_id bigint, name text, enabled boolean, role text, rate_630 numeric, rate_offer numeric, max_amount int,
               rate_630_djezzy numeric, rate_630_ooredoo numeric,
               block_630 boolean, block_offer boolean, block_ooredoo boolean, block_djezzy boolean)
language sql as $$ select * from private.store_admin_flexy_customers_v3_impl() $$;

-- One change for a list of shops (the selection, or one shop). Exactly one of:
--   p_service + p_rate            → that service's rate (p_rate null clears it = closed)
--   p_service + p_block           → that service's «منع» (true) / «سماح» (false), the rate kept
--   p_enabled                     → enable (copies the empty defaults, as set_customer does) / disable
--   p_max                         → the largest amount
-- Returns how many shops were changed.
create or replace function private.store_admin_flexy_bulk_impl(p_ids bigint[], p_service text, p_rate numeric, p_block boolean,
                                                               p_enabled boolean, p_max int, p_role text)
returns int
language plpgsql security definer set search_path = '' as $$
declare
  s store.settings;
  n int := 0;
begin
  perform private.store_require_admin();
  if p_ids is null or cardinality(p_ids) = 0 or cardinality(p_ids) > 500 then raise exception 'FLEXY_BAD_REQUEST'; end if;
  if p_rate is not null and (p_rate < 0 or p_rate >= 100) then raise exception 'FLEXY_BAD_REQUEST'; end if;
  if p_service is not null and p_service not in ('mobilis', 'offer', 'ooredoo', 'djezzy') then raise exception 'FLEXY_BAD_REQUEST'; end if;
  select * into s from store.settings x where x.id = 1;

  if p_service is not null and p_block is not null then
    update store.customers c
       set flexy_block_630 = case when p_service = 'mobilis' then p_block else c.flexy_block_630 end,
           flexy_block_offer = case when p_service = 'offer' then p_block else c.flexy_block_offer end,
           flexy_block_ooredoo = case when p_service = 'ooredoo' then p_block else c.flexy_block_ooredoo end,
           flexy_block_djezzy = case when p_service = 'djezzy' then p_block else c.flexy_block_djezzy end
     where c.id = any (p_ids) and not c.is_shop;
  elsif p_service is not null then
    update store.customers c
       set flexy_rate_630 = case when p_service = 'mobilis' then p_rate else c.flexy_rate_630 end,
           flexy_rate_offer = case when p_service = 'offer' then p_rate else c.flexy_rate_offer end,
           flexy_rate_630_ooredoo = case when p_service = 'ooredoo' then p_rate else c.flexy_rate_630_ooredoo end,
           flexy_rate_630_djezzy = case when p_service = 'djezzy' then p_rate else c.flexy_rate_630_djezzy end
     where c.id = any (p_ids) and not c.is_shop;
  elsif p_enabled is not null then
    update store.customers c
       set flexy_enabled = p_enabled,
           flexy_rate_630 = coalesce(c.flexy_rate_630, case when p_enabled then s.flexy_default_rate_630 end),
           flexy_rate_offer = coalesce(c.flexy_rate_offer, case when p_enabled then s.flexy_default_rate_offer end),
           flexy_rate_630_djezzy = coalesce(c.flexy_rate_630_djezzy, case when p_enabled then s.flexy_default_rate_630_djezzy end),
           flexy_rate_630_ooredoo = coalesce(c.flexy_rate_630_ooredoo, case when p_enabled then s.flexy_default_rate_630_ooredoo end),
           flexy_max = coalesce(c.flexy_max, case when p_enabled then s.flexy_default_max end)
     where c.id = any (p_ids) and not c.is_shop;
  elsif p_max is not null then
    if p_max < 10 then raise exception 'FLEXY_BAD_REQUEST'; end if;
    update store.customers c set flexy_max = p_max where c.id = any (p_ids) and not c.is_shop;
  elsif p_role is not null then
    if p_role not in ('trader', 'wholesale') then raise exception 'FLEXY_BAD_REQUEST'; end if;
    update store.customers c set flexy_role = p_role where c.id = any (p_ids) and not c.is_shop;
  else
    raise exception 'FLEXY_BAD_REQUEST';
  end if;
  get diagnostics n = row_count;
  return n;
end;
$$;
create or replace function public.store_admin_flexy_bulk(p_ids bigint[], p_service text default null, p_rate numeric default null,
                                                         p_block boolean default null, p_enabled boolean default null,
                                                         p_max int default null, p_role text default null)
returns int language sql as $$ select private.store_admin_flexy_bulk_impl(p_ids, p_service, p_rate, p_block, p_enabled, p_max, p_role) $$;

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_flexy_create_v3_impl', 'store_flexy_create_v3',
                        'store_flexy_status_v3_impl', 'store_flexy_status_v3',
                        'store_admin_flexy_customers_v3_impl', 'store_admin_flexy_customers_v3',
                        'store_admin_flexy_bulk_impl', 'store_admin_flexy_bulk')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.name like 'store\_flexy\_create%' then
      execute format('grant execute on function %s to service_role', f.sig);
    elsif f.name like 'store\_admin\_%' then
      execute format('grant execute on function %s to authenticated', f.sig);
    else
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end;
$$;
