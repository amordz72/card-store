-- v1.33: Flexy for shops (customers). Owner decisions 2026-10-25:
-- developer/projects/flexy-core/SHOP-FLEXY-DECISIONS-2026-10-25.md
--
--   * Per shop: enabled, a rate for ordinary credit (630) and a separate rate for offers,
--     and a maximum per operation. The defaults are copied ONCE (when the owner first
--     enables a shop); changing a default later never touches existing shops.
--   * The shop never sees its rate, the amount charged or its role: the customer API
--     returns the amount sent, the status and the network reply only.
--   * Money: the charge is taken from the balance when the request is made (kind 'flexy'),
--     returned in full on a confirmed failure or a request that never left
--     (kind 'flexy_refund'), held while in review until the owner decides.
--   * Creating and updating a job is for the server only (Edge function store-flexy with
--     the service role): the browser cannot take money without the send that follows.
--   * Sending stays closed (settings.flexy_open = false) until Flexy Core can send for an
--     app. No money moves in this migration.

-- ---------------------------------------------------------------------
-- Wallet: two new kinds. A flexy entry is not reversible by hand: only its job refunds it.
-- ---------------------------------------------------------------------
alter table store.wallet_entries drop constraint wallet_entries_kind_check;
alter table store.wallet_entries add constraint wallet_entries_kind_check check (kind in (
  'debt', 'debt_refund', 'cash', 'cash_refund', 'pay', 'pay_refund', 'self',
  'purchase', 'purchase_refund', 'shop_topup', 'shop_topup_refund', 'flexy', 'flexy_refund'));

create or replace function private.store_kind_effect(p_kind text, out b int, out d int)
language sql immutable set search_path = '' as $$
  select v.b, v.d from (values
    ('debt', 1, 1), ('debt_refund', -1, -1),
    ('cash', 1, 0), ('cash_refund', -1, 0),
    ('pay', 0, -1), ('pay_refund', 0, 1),
    ('self', 1, 1),
    ('purchase', -1, 0), ('purchase_refund', 1, 0),
    ('shop_topup', 1, 0), ('shop_topup_refund', -1, 0),
    ('flexy', -1, 0), ('flexy_refund', 1, 0)
  ) v(k, b, d) where v.k = p_kind;
$$;

-- ---------------------------------------------------------------------
-- Settings and per-shop columns
-- ---------------------------------------------------------------------
alter table store.settings add column flexy_open boolean not null default false;
alter table store.settings add column flexy_default_rate_630 numeric(5,2) not null default 4
  check (flexy_default_rate_630 >= 0 and flexy_default_rate_630 < 100);
alter table store.settings add column flexy_default_rate_offer numeric(5,2)
  check (flexy_default_rate_offer >= 0 and flexy_default_rate_offer < 100);
alter table store.settings add column flexy_default_max int not null default 5000
  check (flexy_default_max between 40 and 50000);
comment on column store.settings.flexy_open is 'Owner switch: shops may send Flexy. Off stops every shop at once';
comment on column store.settings.flexy_default_rate_offer is 'Null until the owner sets it: offers stay closed for shops without a rate';

alter table store.customers add column flexy_enabled boolean not null default false;
alter table store.customers add column flexy_role text not null default 'trader' check (flexy_role in ('trader', 'wholesale'));
alter table store.customers add column flexy_rate_630 numeric(5,2) check (flexy_rate_630 >= 0 and flexy_rate_630 < 100);
alter table store.customers add column flexy_rate_offer numeric(5,2) check (flexy_rate_offer >= 0 and flexy_rate_offer < 100);
alter table store.customers add column flexy_max int check (flexy_max between 40 and 50000);
comment on column store.customers.flexy_role is 'Owner label only (تاجر / تاجر الجملة); never shown to the shop';

-- ---------------------------------------------------------------------
-- Jobs
-- ---------------------------------------------------------------------
create table store.flexy_jobs (
  id bigint generated always as identity primary key,
  customer_id bigint not null references store.customers(id),
  request_id uuid not null unique,
  core_key text not null unique check (core_key ~ '^[A-Za-z0-9_-]{16,128}$'),
  kind text not null check (kind in ('630', 'offer')),
  phone text not null check (phone ~ '^06[0-9]{8}$'),
  amount int not null check (amount between 40 and 50000),
  offer_code text,
  offer_label text,
  charged bigint not null check (charged > 0),
  entry_id bigint not null references store.wallet_entries(id),
  status text not null default 'queued' check (status in ('queued', 'sent', 'success', 'failed', 'review', 'not_sent')),
  network_reply text,
  decided_by text check (decided_by in ('core', 'owner')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz,
  check ((kind = 'offer') = (offer_code is not null))
);
create index on store.flexy_jobs (customer_id, id desc);
create index on store.flexy_jobs (status) where status in ('queued', 'sent', 'review');
alter table store.flexy_jobs enable row level security;
revoke all on store.flexy_jobs from public, anon, authenticated;
comment on table store.flexy_jobs is 'Shop Flexy requests. Money: entry_id debits on create; a flexy_refund entry reverses it on failed/not_sent';

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create function private.store_flexy_phone(p_phone text) returns text
language plpgsql immutable set search_path = '' as $$
declare v text := pg_catalog.regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
begin
  if left(v, 3) = '213' and length(v) = 12 then v := '0' || substr(v, 4); end if;
  if v !~ '^06[0-9]{8}$' then raise exception 'FLEXY_PHONE_NOT_MOBILIS'; end if;
  return v;
end;
$$;

-- Refund once, linked to the debit. Safe to call twice.
create function private.store_flexy_refund(p_job store.flexy_jobs, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare e store.wallet_entries;
begin
  select * into e from store.wallet_entries w where w.id = p_job.entry_id and w.kind = 'flexy';
  if found and not exists (select 1 from store.wallet_entries x where x.reverses_id = e.id) then
    perform private.store_post_entry(e.customer_id, 'flexy_refund', e.amount, p_note, null, e.id, null, null);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Customer (read only from the browser)
-- ---------------------------------------------------------------------
create function private.store_flexy_status_impl(p_token text)
returns table (enabled boolean, open boolean, max_amount int, offers boolean)
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
                      c.flexy_rate_offer is not null;
end;
$$;

-- Compact on purpose (weak networks): no rate, no charge, no role.
create function private.store_flexy_jobs_impl(p_token text, p_limit int, p_before bigint)
returns table (job_id bigint, kind text, phone text, amount int, offer_label text, status text,
               network_reply text, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select j.id, j.kind, j.phone, j.amount, j.offer_label, j.status, j.network_reply, j.created_at
  from store.flexy_jobs j
  where j.customer_id = v and (p_before is null or j.id < p_before)
  order by j.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 50);
end;
$$;

-- ---------------------------------------------------------------------
-- Server (service role, from the Edge function store-flexy)
-- ---------------------------------------------------------------------
-- Take the money and record the request. Idempotent on p_request_id: a retry after a lost
-- answer returns the same job and never charges twice.
create function private.store_flexy_create_impl(p_token text, p_kind text, p_phone text, p_amount int,
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
    if p_offer_code is not null then raise exception 'FLEXY_BAD_REQUEST'; end if;
    v_rate := c.flexy_rate_630;
  elsif p_kind = 'offer' then
    -- Offers open only when Flexy Core sends them (parallel track); the rate must be set.
    raise exception 'FLEXY_OFFERS_NOT_READY';
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
  e := private.store_post_entry(v, 'flexy', v_charge, 'فليكسي ' || p_amount || ' دج إلى ' || v_phone, null, null, null, null);
  insert into store.flexy_jobs (customer_id, request_id, core_key, kind, phone, amount, offer_code, offer_label, charged, entry_id)
  values (v, p_request_id, 'cs_' || replace(p_request_id::text, '-', ''), p_kind, v_phone, p_amount,
          null, null, v_charge, e.id)
  returning * into j;
  return query select j.id, j.status, j.core_key, j.phone, j.amount, j.created_at, false;
end;
$$;

-- Apply what Flexy Core said. Money follows the status: failed/not_sent refunds once,
-- review holds, success keeps the charge. A final status never changes here.
create function private.store_flexy_mark_impl(p_job_id bigint, p_status text, p_reply text)
returns text
language plpgsql security definer set search_path = '' as $$
declare j store.flexy_jobs;
begin
  if p_status not in ('sent', 'success', 'failed', 'review', 'not_sent') then raise exception 'FLEXY_BAD_STATUS'; end if;
  select * into j from store.flexy_jobs x where x.id = p_job_id for update;
  if not found then raise exception 'FLEXY_JOB_NOT_FOUND'; end if;
  if j.status in ('success', 'failed', 'not_sent') then return j.status; end if;
  if j.status = 'review' and p_status = 'sent' then return j.status; end if;
  if p_status = 'not_sent' and j.status <> 'queued' then raise exception 'FLEXY_ALREADY_SENT'; end if;
  update store.flexy_jobs x
     set status = p_status,
         network_reply = coalesce(left(nullif(btrim(p_reply), ''), 500), x.network_reply),
         decided_by = case when p_status in ('success', 'failed', 'not_sent', 'review') then 'core' else x.decided_by end,
         updated_at = now(),
         finished_at = case when p_status in ('success', 'failed', 'not_sent') then now() end
   where x.id = j.id;
  if p_status in ('failed', 'not_sent') then
    perform private.store_flexy_refund(j, case p_status when 'failed' then 'فليكسي: فشل، أُعيد المبلغ'
                                                         else 'فليكسي: لم يُرسل، أُعيد المبلغ' end);
  end if;
  return p_status;
end;
$$;

-- Jobs the server must follow up with Flexy Core (lost answers, still running).
create function private.store_flexy_open_jobs_impl(p_customer_token text)
returns table (job_id bigint, core_key text, status text, phone text, amount int, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare v bigint := case when p_customer_token is null then null else private.store_session_customer(p_customer_token) end;
begin
  return query
  select j.id, j.core_key, j.status, j.phone, j.amount, j.created_at from store.flexy_jobs j
  where j.status in ('queued', 'sent') and (v is null or j.customer_id = v)
  order by j.id
  limit 50;
end;
$$;

-- ---------------------------------------------------------------------
-- Owner
-- ---------------------------------------------------------------------
create function private.store_admin_flexy_settings_impl()
returns table (open boolean, default_rate_630 numeric, default_rate_offer numeric, default_max int)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select s.flexy_open, s.flexy_default_rate_630, s.flexy_default_rate_offer, s.flexy_default_max
  from store.settings s where s.id = 1;
end;
$$;

create function private.store_admin_set_flexy_settings_impl(p_open boolean, p_rate_630 numeric, p_rate_offer numeric, p_max int)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.settings s
     set flexy_open = coalesce(p_open, s.flexy_open),
         flexy_default_rate_630 = coalesce(p_rate_630, s.flexy_default_rate_630),
         flexy_default_rate_offer = coalesce(p_rate_offer, s.flexy_default_rate_offer),
         flexy_default_max = coalesce(p_max, s.flexy_default_max),
         updated_at = now()
   where s.id = 1;
end;
$$;

-- «نسب المحلات»: every customer, with the Flexy columns.
create function private.store_admin_flexy_customers_impl()
returns table (customer_id bigint, name text, enabled boolean, role text, rate_630 numeric, rate_offer numeric, max_amount int)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select c.id, c.name, c.flexy_enabled, c.flexy_role, c.flexy_rate_630, c.flexy_rate_offer, c.flexy_max
  from store.customers c where not c.is_shop order by c.name;
end;
$$;

-- Null leaves a value as it is. The first enable copies the defaults that are still empty.
create function private.store_admin_set_customer_flexy_impl(p_customer_id bigint, p_enabled boolean, p_role text,
                                                            p_rate_630 numeric, p_rate_offer numeric, p_max int)
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
         flexy_max = coalesce(p_max, c.flexy_max, case when coalesce(p_enabled, false) then s.flexy_default_max end)
   where c.id = p_customer_id and not c.is_shop;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
end;
$$;

create function private.store_admin_flexy_jobs_impl(p_status text, p_limit int, p_before bigint)
returns table (job_id bigint, customer_id bigint, customer_name text, kind text, phone text, amount int,
               offer_label text, charged bigint, status text, network_reply text, decided_by text, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query
  select j.id, j.customer_id, c.name, j.kind, j.phone, j.amount, j.offer_label, j.charged, j.status,
         j.network_reply, j.decided_by, j.created_at
  from store.flexy_jobs j join store.customers c on c.id = j.customer_id
  where (p_status is null or j.status = p_status) and (p_before is null or j.id < p_before)
  order by j.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
end;
$$;

create function private.store_admin_flexy_review_count_impl() returns bigint
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return (select count(*) from store.flexy_jobs j where j.status = 'review');
end;
$$;

-- Owner decides a job in review: sent (the charge stays) or not sent (full refund).
create function private.store_admin_flexy_resolve_impl(p_job_id bigint, p_done boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare j store.flexy_jobs;
begin
  perform private.store_require_admin();
  select * into j from store.flexy_jobs x where x.id = p_job_id and x.status = 'review' for update;
  if not found then raise exception 'NOT_IN_REVIEW'; end if;
  update store.flexy_jobs x
     set status = case when coalesce(p_done, false) then 'success' else 'failed' end,
         decided_by = 'owner', updated_at = now(), finished_at = now()
   where x.id = j.id;
  if not coalesce(p_done, false) then
    perform private.store_flexy_refund(j, 'فليكسي: قرار المحل لم يُرسل، أُعيد المبلغ');
    return 'failed';
  end if;
  return 'success';
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------
create function public.store_flexy_status(p_token text)
returns table (enabled boolean, open boolean, max_amount int, offers boolean)
language sql as $$ select * from private.store_flexy_status_impl(p_token) $$;
create function public.store_flexy_jobs(p_token text, p_limit int default 10, p_before bigint default null)
returns table (job_id bigint, kind text, phone text, amount int, offer_label text, status text,
               network_reply text, created_at timestamptz)
language sql as $$ select * from private.store_flexy_jobs_impl(p_token, p_limit, p_before) $$;
create function public.store_flexy_create(p_token text, p_kind text, p_phone text, p_amount int,
                                          p_offer_code text, p_offer_label text, p_request_id uuid)
returns table (job_id bigint, status text, core_key text, phone text, amount int, created_at timestamptz, reused boolean)
language sql as $$ select * from private.store_flexy_create_impl(p_token, p_kind, p_phone, p_amount, p_offer_code, p_offer_label, p_request_id) $$;
create function public.store_flexy_mark(p_job_id bigint, p_status text, p_reply text)
returns text language sql as $$ select private.store_flexy_mark_impl(p_job_id, p_status, p_reply) $$;
create function public.store_flexy_open_jobs(p_customer_token text default null)
returns table (job_id bigint, core_key text, status text, phone text, amount int, created_at timestamptz)
language sql as $$ select * from private.store_flexy_open_jobs_impl(p_customer_token) $$;
create function public.store_admin_flexy_settings()
returns table (open boolean, default_rate_630 numeric, default_rate_offer numeric, default_max int)
language sql as $$ select * from private.store_admin_flexy_settings_impl() $$;
create function public.store_admin_set_flexy_settings(p_open boolean, p_rate_630 numeric, p_rate_offer numeric, p_max int)
returns void language sql as $$ select private.store_admin_set_flexy_settings_impl(p_open, p_rate_630, p_rate_offer, p_max) $$;
create function public.store_admin_flexy_customers()
returns table (customer_id bigint, name text, enabled boolean, role text, rate_630 numeric, rate_offer numeric, max_amount int)
language sql as $$ select * from private.store_admin_flexy_customers_impl() $$;
create function public.store_admin_set_customer_flexy(p_customer_id bigint, p_enabled boolean, p_role text,
                                                      p_rate_630 numeric, p_rate_offer numeric, p_max int)
returns void language sql as $$ select private.store_admin_set_customer_flexy_impl(p_customer_id, p_enabled, p_role, p_rate_630, p_rate_offer, p_max) $$;
create function public.store_admin_flexy_jobs(p_status text default null, p_limit int default 20, p_before bigint default null)
returns table (job_id bigint, customer_id bigint, customer_name text, kind text, phone text, amount int,
               offer_label text, charged bigint, status text, network_reply text, decided_by text, created_at timestamptz)
language sql as $$ select * from private.store_admin_flexy_jobs_impl(p_status, p_limit, p_before) $$;
create function public.store_admin_flexy_review_count() returns bigint
language sql as $$ select private.store_admin_flexy_review_count_impl() $$;
create function public.store_admin_flexy_resolve(p_job_id bigint, p_done boolean) returns text
language sql as $$ select private.store_admin_flexy_resolve_impl(p_job_id, p_done) $$;

-- ---------------------------------------------------------------------
-- Grants: customer reads to anon/authenticated, owner to authenticated,
-- create/mark/open-jobs to the service role only (the Edge function).
-- ---------------------------------------------------------------------
revoke all on function private.store_flexy_phone(text) from public, anon, authenticated;
revoke all on function private.store_flexy_refund(store.flexy_jobs, text) from public, anon, authenticated;
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_flexy_status_impl', 'store_flexy_status', 'store_flexy_jobs_impl', 'store_flexy_jobs',
                        'store_flexy_create_impl', 'store_flexy_create', 'store_flexy_mark_impl', 'store_flexy_mark',
                        'store_flexy_open_jobs_impl', 'store_flexy_open_jobs',
                        'store_admin_flexy_settings_impl', 'store_admin_flexy_settings',
                        'store_admin_set_flexy_settings_impl', 'store_admin_set_flexy_settings',
                        'store_admin_flexy_customers_impl', 'store_admin_flexy_customers',
                        'store_admin_set_customer_flexy_impl', 'store_admin_set_customer_flexy',
                        'store_admin_flexy_jobs_impl', 'store_admin_flexy_jobs',
                        'store_admin_flexy_review_count_impl', 'store_admin_flexy_review_count',
                        'store_admin_flexy_resolve_impl', 'store_admin_flexy_resolve')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.name ~ '^store_flexy_(create|mark|open_jobs)' then
      execute format('grant execute on function %s to service_role', f.sig);
    elsif f.name like 'store\_admin\_%' then
      execute format('grant execute on function %s to authenticated', f.sig);
    else
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end;
$$;
