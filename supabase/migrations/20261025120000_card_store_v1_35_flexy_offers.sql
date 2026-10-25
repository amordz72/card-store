-- card-store v1.35: shop offers (Mobilis Sama / PixX, sent by Flexy Core through *665*).
--
-- * store_flexy_create accepts kind 'offer': the shop's offers rate, the offer's name kept as
--   offer_code and offer_label. The price is the number at the end of the name ("Sama Mix 100"):
--   the database refuses any amount that is not that number, so a browser cannot pay 100 for 2000.
-- * The open-jobs lists (shop refresh, minute sweep) now say each job's kind and offer (_v2), so a
--   job re-sent after a lost answer is sent again as what it is, never as ordinary credit.

create or replace function private.store_flexy_create_impl(p_token text, p_kind text, p_phone text, p_amount int,
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
  if p_kind = '630' then
    if p_offer_code is not null or p_offer_label is not null then raise exception 'FLEXY_BAD_REQUEST'; end if;
    v_rate := c.flexy_rate_630;
  elsif p_kind = 'offer' then
    v_label := btrim(coalesce(p_offer_label, ''));
    -- The price is the name's last number; nothing else is accepted.
    if v_label !~ '^[A-Za-z][A-Za-z ]{1,30} [0-9]{2,5}$' or p_amount is null
       or substring(v_label from '([0-9]+)$')::int <> p_amount then
      raise exception 'FLEXY_OFFER_INVALID';
    end if;
    v_rate := c.flexy_rate_offer;
  else
    raise exception 'FLEXY_BAD_REQUEST';
  end if;
  if v_rate is null then raise exception 'FLEXY_RATE_MISSING'; end if;
  v_phone := private.store_flexy_phone(p_phone);
  if p_amount is null or p_amount < 40 or p_amount > coalesce(c.flexy_max, s.flexy_default_max) then
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

-- Open jobs with their kind and offer: new functions (_v2) beside the old ones, so nothing is
-- dropped (store-flexy calls only the _v2 ones; the old ones stay unused).
create or replace function private.store_flexy_open_jobs_v2_impl(p_customer_token text)
returns table (job_id bigint, core_key text, status text, phone text, amount int, created_at timestamptz,
               kind text, offer_label text)
language plpgsql security definer set search_path = '' as $$
declare v bigint := case when p_customer_token is null then null else private.store_session_customer(p_customer_token) end;
begin
  return query
  select j.id, j.core_key, j.status, j.phone, j.amount, j.created_at, j.kind, j.offer_label from store.flexy_jobs j
  where j.status in ('queued', 'sent') and (v is null or j.customer_id = v)
  order by j.id
  limit 50;
end;
$$;
create or replace function public.store_flexy_open_jobs_v2(p_customer_token text default null)
returns table (job_id bigint, core_key text, status text, phone text, amount int, created_at timestamptz,
               kind text, offer_label text)
language sql as $$ select * from private.store_flexy_open_jobs_v2_impl(p_customer_token) $$;

create or replace function private.store_flexy_sweep_jobs_v2_impl(p_secret text)
returns table (job_id bigint, core_key text, status text, phone text, amount int, created_at timestamptz,
               kind text, offer_label text)
language plpgsql security definer set search_path = '' as $$
declare v_secret text;
begin
  select d.decrypted_secret into v_secret from vault.decrypted_secrets d where d.name = 'store_flexy_sweep_secret';
  if v_secret is null or p_secret is null or p_secret <> v_secret then
    raise exception 'NOT_ALLOWED' using errcode = 'insufficient_privilege';
  end if;
  return query select * from private.store_flexy_open_jobs_v2_impl(null);
end;
$$;
create or replace function public.store_flexy_sweep_jobs_v2(p_secret text)
returns table (job_id bigint, core_key text, status text, phone text, amount int, created_at timestamptz,
               kind text, offer_label text)
language sql as $$ select * from private.store_flexy_sweep_jobs_v2_impl(p_secret) $$;

revoke all on function private.store_flexy_open_jobs_v2_impl(text) from public, anon, authenticated;
revoke all on function public.store_flexy_open_jobs_v2(text) from public, anon, authenticated;
revoke all on function private.store_flexy_sweep_jobs_v2_impl(text) from public, anon, authenticated;
revoke all on function public.store_flexy_sweep_jobs_v2(text) from public, anon, authenticated;
grant execute on function private.store_flexy_open_jobs_v2_impl(text) to service_role;
grant execute on function public.store_flexy_open_jobs_v2(text) to service_role;
grant execute on function private.store_flexy_sweep_jobs_v2_impl(text) to service_role;
grant execute on function public.store_flexy_sweep_jobs_v2(text) to service_role;
