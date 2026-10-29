-- v1.42 (owner 2026-10-29, «نفذ 6»): Djezzy's smallest credit is 100 DA, refused before the shop is charged.
-- Flexy Core refuses under 100 to a Djezzy number since 2026-10-29; this function still let 40–99 through
-- (charged first, then refused and refunded). Ooredoo stays 10 and Mobilis 40, as in v1.39.
-- Only that line changes; the rest is v1.39's private.store_flexy_create_v2_impl as it is live.

create or replace function private.store_flexy_create_v2_impl(p_token text, p_kind text, p_phone text, p_amount integer, p_offer_code text, p_offer_label text, p_request_id uuid)
 returns table(job_id bigint, status text, core_key text, phone text, amount integer, created_at timestamp with time zone, reused boolean)
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    -- Djezzy's smallest credit is 100 DA (owner 2026-10-29)
    elsif left(v_phone, 2) = '07' then v_rate := c.flexy_rate_630_djezzy; v_min := 100;
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
$function$;
