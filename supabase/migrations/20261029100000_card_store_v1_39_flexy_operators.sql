-- card-store v1.39: ordinary credit for shops on Djezzy (07) and Ooredoo (05), beside Mobilis (06).
-- Owner 2026-10-29 («افتح فليكسي عادي جازي واريدو للمحلات»): the shop pays from its balance as for
-- Mobilis, with a rate PER OPERATOR per shop («لكل متعامل نسبة»); credit for all the shops; offers on
-- these operators stay closed (phase 2, after the Djezzy catalog).
--
-- * customers: flexy_rate_630_djezzy / flexy_rate_630_ooredoo (null = that operator is closed for the shop).
-- * settings: the two defaults, copied on the first enable like the others; plus a fill function that
--   gives a rate to every enabled shop that has none, so the owner opens an operator in one press.
-- * store_flexy_phone_v2 accepts 05/06/07; store_flexy_create_v2 picks the rate by the prefix, takes
--   10 DA at least on Ooredoo (40 elsewhere), and refuses an offer to a non-Mobilis number
--   (FLEXY_OFFER_OPERATOR_NOT_READY). The job's kind stays '630' (= ordinary credit); the Edge function
--   picks the Flexy Core key by the prefix.
-- * status_v2 / customers_v2 / settings_v2 / set_*_v2 carry the new values. The v1 functions stay as
--   they are (nothing dropped; the Edge function and the UI move to _v2).

alter table store.customers add column if not exists flexy_rate_630_djezzy numeric(5,2)
  check (flexy_rate_630_djezzy >= 0 and flexy_rate_630_djezzy < 100);
alter table store.customers add column if not exists flexy_rate_630_ooredoo numeric(5,2)
  check (flexy_rate_630_ooredoo >= 0 and flexy_rate_630_ooredoo < 100);
alter table store.settings add column if not exists flexy_default_rate_630_djezzy numeric(5,2)
  check (flexy_default_rate_630_djezzy >= 0 and flexy_default_rate_630_djezzy < 100);
alter table store.settings add column if not exists flexy_default_rate_630_ooredoo numeric(5,2)
  check (flexy_default_rate_630_ooredoo >= 0 and flexy_default_rate_630_ooredoo < 100);
comment on column store.customers.flexy_rate_630_djezzy is 'Shop margin % on Djezzy ordinary credit; null = Djezzy closed for this shop.';
comment on column store.customers.flexy_rate_630_ooredoo is 'Shop margin % on Ooredoo ordinary credit; null = Ooredoo closed for this shop.';

-- Any Algerian mobile: 05 (Ooredoo), 06 (Mobilis), 07 (Djezzy).
create or replace function private.store_flexy_phone_v2(p_phone text) returns text
language plpgsql immutable set search_path = '' as $$
declare v text := pg_catalog.regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
begin
  if left(v, 3) = '213' and length(v) = 12 then v := '0' || substr(v, 4); end if;
  if v !~ '^0[567][0-9]{8}$' then raise exception 'FLEXY_PHONE_NOT_MOBILE'; end if;
  return v;
end;
$$;

create or replace function private.store_flexy_create_v2_impl(p_token text, p_kind text, p_phone text, p_amount int,
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
    -- The rate of the number's operator; none = the operator is not open for this shop.
    if left(v_phone, 2) = '06' then v_rate := c.flexy_rate_630;
    elsif left(v_phone, 2) = '07' then v_rate := c.flexy_rate_630_djezzy;
    else v_rate := c.flexy_rate_630_ooredoo; v_min := 10;
    end if;
    if v_rate is null then raise exception 'FLEXY_OPERATOR_NOT_OPEN'; end if;
  elsif p_kind = 'offer' then
    if left(v_phone, 2) <> '06' then raise exception 'FLEXY_OFFER_OPERATOR_NOT_READY'; end if;
    v_label := btrim(coalesce(p_offer_label, ''));
    -- The price is the name's last number; nothing else is accepted.
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
create or replace function public.store_flexy_create_v2(p_token text, p_kind text, p_phone text, p_amount int,
                                                        p_offer_code text, p_offer_label text, p_request_id uuid)
returns table (job_id bigint, status text, core_key text, phone text, amount int, created_at timestamptz, reused boolean)
language sql as $$ select * from private.store_flexy_create_v2_impl(p_token, p_kind, p_phone, p_amount, p_offer_code, p_offer_label, p_request_id) $$;

-- The shop's status, with the operators open for it (a rate set): the screen sends to those only.
create or replace function private.store_flexy_status_v2_impl(p_token text)
returns table (enabled boolean, open boolean, max_amount int, offers boolean, djezzy boolean, ooredoo boolean)
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
                      c.flexy_rate_offer is not null,
                      c.flexy_rate_630_djezzy is not null,
                      c.flexy_rate_630_ooredoo is not null;
end;
$$;
create or replace function public.store_flexy_status_v2(p_token text)
returns table (enabled boolean, open boolean, max_amount int, offers boolean, djezzy boolean, ooredoo boolean)
language sql as $$ select * from private.store_flexy_status_v2_impl(p_token) $$;

-- Owner: the defaults, now with the two operators.
create or replace function private.store_admin_flexy_settings_v2_impl()
returns table (open boolean, default_rate_630 numeric, default_rate_offer numeric, default_max int,
               default_rate_630_djezzy numeric, default_rate_630_ooredoo numeric)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select s.flexy_open, s.flexy_default_rate_630, s.flexy_default_rate_offer, s.flexy_default_max,
                      s.flexy_default_rate_630_djezzy, s.flexy_default_rate_630_ooredoo
  from store.settings s where s.id = 1;
end;
$$;
create or replace function public.store_admin_flexy_settings_v2()
returns table (open boolean, default_rate_630 numeric, default_rate_offer numeric, default_max int,
               default_rate_630_djezzy numeric, default_rate_630_ooredoo numeric)
language sql as $$ select * from private.store_admin_flexy_settings_v2_impl() $$;

create or replace function private.store_admin_set_flexy_settings_v2_impl(p_open boolean, p_rate_630 numeric, p_rate_offer numeric, p_max int,
                                                                          p_rate_630_djezzy numeric, p_rate_630_ooredoo numeric)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.settings s
     set flexy_open = coalesce(p_open, s.flexy_open),
         flexy_default_rate_630 = coalesce(p_rate_630, s.flexy_default_rate_630),
         flexy_default_rate_offer = coalesce(p_rate_offer, s.flexy_default_rate_offer),
         flexy_default_max = coalesce(p_max, s.flexy_default_max),
         flexy_default_rate_630_djezzy = coalesce(p_rate_630_djezzy, s.flexy_default_rate_630_djezzy),
         flexy_default_rate_630_ooredoo = coalesce(p_rate_630_ooredoo, s.flexy_default_rate_630_ooredoo),
         updated_at = now()
   where s.id = 1;
end;
$$;
create or replace function public.store_admin_set_flexy_settings_v2(p_open boolean, p_rate_630 numeric, p_rate_offer numeric, p_max int,
                                                                    p_rate_630_djezzy numeric, p_rate_630_ooredoo numeric)
returns void language sql as $$ select private.store_admin_set_flexy_settings_v2_impl(p_open, p_rate_630, p_rate_offer, p_max, p_rate_630_djezzy, p_rate_630_ooredoo) $$;

-- «نسب المحلات» with the operators' rates.
create or replace function private.store_admin_flexy_customers_v2_impl()
returns table (customer_id bigint, name text, enabled boolean, role text, rate_630 numeric, rate_offer numeric, max_amount int,
               rate_630_djezzy numeric, rate_630_ooredoo numeric)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select c.id, c.name, c.flexy_enabled, c.flexy_role, c.flexy_rate_630, c.flexy_rate_offer, c.flexy_max,
                      c.flexy_rate_630_djezzy, c.flexy_rate_630_ooredoo
  from store.customers c where not c.is_shop order by c.name;
end;
$$;
create or replace function public.store_admin_flexy_customers_v2()
returns table (customer_id bigint, name text, enabled boolean, role text, rate_630 numeric, rate_offer numeric, max_amount int,
               rate_630_djezzy numeric, rate_630_ooredoo numeric)
language sql as $$ select * from private.store_admin_flexy_customers_v2_impl() $$;

-- Null leaves a value as it is; the first enable copies the defaults still empty (the operators' too).
create or replace function private.store_admin_set_customer_flexy_v2_impl(p_customer_id bigint, p_enabled boolean, p_role text,
                                                                         p_rate_630 numeric, p_rate_offer numeric, p_max int,
                                                                         p_rate_630_djezzy numeric, p_rate_630_ooredoo numeric)
returns void
language plpgsql security definer set search_path = '' as $$
declare s store.settings;
begin
  perform private.store_require_admin();
  select * into s from store.settings x where x.id = 1;
  update store.customers c
     set flexy_enabled = coalesce(p_enabled, c.flexy_enabled),
         flexy_role = coalesce(p_role, c.flexy_role),
         flexy_rate_630 = coalesce(p_rate_630, c.flexy_rate_630,
                                   case when coalesce(p_enabled, false) then s.flexy_default_rate_630 end),
         flexy_rate_offer = coalesce(p_rate_offer, c.flexy_rate_offer,
                                     case when coalesce(p_enabled, false) then s.flexy_default_rate_offer end),
         flexy_max = coalesce(p_max, c.flexy_max, case when coalesce(p_enabled, false) then s.flexy_default_max end),
         flexy_rate_630_djezzy = coalesce(p_rate_630_djezzy, c.flexy_rate_630_djezzy,
                                          case when coalesce(p_enabled, false) then s.flexy_default_rate_630_djezzy end),
         flexy_rate_630_ooredoo = coalesce(p_rate_630_ooredoo, c.flexy_rate_630_ooredoo,
                                           case when coalesce(p_enabled, false) then s.flexy_default_rate_630_ooredoo end)
   where c.id = p_customer_id and not c.is_shop;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
end;
$$;
create or replace function public.store_admin_set_customer_flexy_v2(p_customer_id bigint, p_enabled boolean, p_role text,
                                                                    p_rate_630 numeric, p_rate_offer numeric, p_max int,
                                                                    p_rate_630_djezzy numeric, p_rate_630_ooredoo numeric)
returns void language sql as $$ select private.store_admin_set_customer_flexy_v2_impl(p_customer_id, p_enabled, p_role, p_rate_630, p_rate_offer, p_max, p_rate_630_djezzy, p_rate_630_ooredoo) $$;

-- Opening an operator for every enabled shop at once: the given rate goes to each enabled shop that has
-- none for it (a shop with its own rate keeps it). Returns how many shops got it.
create or replace function private.store_admin_flexy_fill_operator_rate_impl(p_operator text, p_rate numeric)
returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.store_require_admin();
  if p_rate is null or p_rate < 0 or p_rate >= 100 then raise exception 'FLEXY_BAD_REQUEST'; end if;
  if p_operator = 'djezzy' then
    update store.customers c set flexy_rate_630_djezzy = p_rate where c.flexy_enabled and not c.is_shop and c.flexy_rate_630_djezzy is null;
  elsif p_operator = 'ooredoo' then
    update store.customers c set flexy_rate_630_ooredoo = p_rate where c.flexy_enabled and not c.is_shop and c.flexy_rate_630_ooredoo is null;
  else
    raise exception 'FLEXY_BAD_REQUEST';
  end if;
  get diagnostics n = row_count;
  return n;
end;
$$;
create or replace function public.store_admin_flexy_fill_operator_rate(p_operator text, p_rate numeric)
returns int language sql as $$ select private.store_admin_flexy_fill_operator_rate_impl(p_operator, p_rate) $$;

-- Grants, as v1.33: shop reads to anon/authenticated, owner to authenticated, create to the service role only.
revoke all on function private.store_flexy_phone_v2(text) from public, anon, authenticated;
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_flexy_create_v2_impl', 'store_flexy_create_v2',
                        'store_flexy_status_v2_impl', 'store_flexy_status_v2',
                        'store_admin_flexy_settings_v2_impl', 'store_admin_flexy_settings_v2',
                        'store_admin_set_flexy_settings_v2_impl', 'store_admin_set_flexy_settings_v2',
                        'store_admin_flexy_customers_v2_impl', 'store_admin_flexy_customers_v2',
                        'store_admin_set_customer_flexy_v2_impl', 'store_admin_set_customer_flexy_v2',
                        'store_admin_flexy_fill_operator_rate_impl', 'store_admin_flexy_fill_operator_rate')
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
