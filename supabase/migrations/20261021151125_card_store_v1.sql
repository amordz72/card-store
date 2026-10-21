-- =====================================================================
-- Card Store v1 — schema `store` (standalone; additive only)
-- Decisions: developer/projects/card-store/*.md (2026-10-21)
-- No object outside `store`, `private.store_*`, `public.store_*` is touched.
-- Rollback: drop schema store cascade; drop function private.store_* / public.store_*.
-- =====================================================================

create schema if not exists store;
revoke all on schema store from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table store.admins (
  user_id uuid primary key,
  created_at timestamptz not null default now()
);

create table store.settings (
  id smallint primary key default 1 check (id = 1),
  announcement text not null default '',
  updated_at timestamptz not null default now()
);

create table store.brands (
  id bigint generated always as identity primary key,
  name text not null unique check (length(btrim(name)) between 1 and 60),
  category text not null check (category in ('phone', 'net', 'game')),
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table store.products (
  id bigint generated always as identity primary key,
  brand_id bigint not null references store.brands(id),
  name text not null check (length(btrim(name)) between 1 and 80),
  base_price bigint not null check (base_price > 0),
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (brand_id, name)
);
create index on store.products (brand_id);

create table store.suppliers (
  id bigint generated always as identity primary key,
  name text not null unique check (length(btrim(name)) between 1 and 80),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index suppliers_one_default on store.suppliers (is_default) where is_default;

create table store.customers (
  id bigint generated always as identity primary key,
  name text not null check (length(btrim(name)) between 1 and 80),
  phone text not null unique check (phone ~ '^0[5-7][0-9]{8}$'),
  password_hash text not null,
  active boolean not null default true,
  debt_limit bigint not null default 0 check (debt_limit >= 0),
  self_topup boolean not null default false,
  balance bigint not null default 0 check (balance >= 0),
  debt bigint not null default 0,
  login_failures int not null default 0,
  lock_count int not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now()
);

create table store.customer_sessions (
  id bigint generated always as identity primary key,
  customer_id bigint not null references store.customers(id),
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_used_at timestamptz,
  revoked_at timestamptz
);
create index on store.customer_sessions (customer_id);

create table store.default_rates (
  product_id bigint primary key references store.products(id),
  pct numeric(5,2) not null check (pct >= 0 and pct <= 50)
);

create table store.customer_rates (
  customer_id bigint not null references store.customers(id),
  product_id bigint not null references store.products(id),
  pct numeric(5,2) not null check (pct >= 0 and pct <= 50),
  primary key (customer_id, product_id)
);
create index on store.customer_rates (product_id);

create table store.code_batches (
  id bigint generated always as identity primary key,
  product_id bigint not null references store.products(id),
  supplier_id bigint not null references store.suppliers(id),
  cost bigint check (cost is null or cost > 0),
  added int not null,
  duplicates int not null,
  created_by uuid not null,
  created_at timestamptz not null default now()
);
create index on store.code_batches (product_id);
create index on store.code_batches (supplier_id);

create table store.orders (
  id bigint generated always as identity primary key,
  customer_id bigint not null references store.customers(id),
  product_id bigint not null references store.products(id),
  qty int not null check (qty between 1 and 20),
  base_amount bigint not null check (base_amount > 0),
  pct numeric(5,2) not null,
  charged_amount bigint not null check (charged_amount > 0),
  cost_amount bigint,
  balance_after bigint not null,
  status text not null default 'done' check (status in ('done', 'refunded')),
  request_id uuid not null unique,
  created_at timestamptz not null default now()
);
create index on store.orders (customer_id, created_at desc);
create index on store.orders (product_id);

create table store.codes (
  id bigint generated always as identity primary key,
  product_id bigint not null references store.products(id),
  batch_id bigint not null references store.code_batches(id),
  supplier_id bigint not null references store.suppliers(id),
  code text not null check (length(code) between 1 and 200),
  serial text,
  cost bigint check (cost is null or cost > 0),
  status text not null default 'available' check (status in ('available', 'sold', 'void')),
  order_id bigint references store.orders(id),
  sold_at timestamptz,
  created_at timestamptz not null default now(),
  unique (product_id, code)
);
create index codes_available on store.codes (product_id, id) where status = 'available';
create index on store.codes (order_id);
create index on store.codes (batch_id);
create index on store.codes (supplier_id);

create table store.wallet_entries (
  id bigint generated always as identity primary key,
  customer_id bigint not null references store.customers(id),
  kind text not null check (kind in ('debt', 'debt_refund', 'cash', 'cash_refund', 'pay', 'pay_refund', 'self', 'purchase', 'purchase_refund')),
  amount bigint not null check (amount > 0),
  d_balance bigint not null,
  d_debt bigint not null,
  balance_after bigint not null check (balance_after >= 0),
  debt_after bigint not null,
  note text,
  order_id bigint references store.orders(id),
  reverses_id bigint unique references store.wallet_entries(id),
  request_id uuid unique,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index on store.wallet_entries (customer_id, created_at desc);
create index on store.wallet_entries (order_id);

create table store.code_reveals (
  id bigint generated always as identity primary key,
  code_id bigint not null references store.codes(id),
  admin_id uuid not null,
  created_at timestamptz not null default now()
);
create index on store.code_reveals (code_id);

-- Ledger is append-only: corrections are new reversing rows.
create function private.store_block_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'APPEND_ONLY';
end;
$$;
create trigger wallet_entries_append_only before update or delete on store.wallet_entries
  for each row execute function private.store_block_change();
create trigger code_reveals_append_only before update or delete on store.code_reveals
  for each row execute function private.store_block_change();

-- Defense in depth: RLS on, no policies, no table grants. Access is via functions only.
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'store' loop
    execute format('alter table store.%I enable row level security', t);
    execute format('revoke all on store.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Seed: settings, the owner as admin, default supplier, brands
-- ---------------------------------------------------------------------
insert into store.settings (id) values (1);
insert into store.admins (user_id) values ('60e166af-1366-47cc-81f9-791a4585c66e');
insert into store.suppliers (name, is_default) values ('أنا — مخزون أول', true);
insert into store.brands (name, category, sort) values
  ('Mobilis', 'phone', 1), ('Djezzy', 'phone', 2), ('Ooredoo', 'phone', 3),
  ('Idoom ADSL', 'net', 1), ('Idoom 4G', 'net', 2),
  ('Free Fire', 'game', 1), ('PUBG', 'game', 2);

-- ---------------------------------------------------------------------
-- Internal helpers (private, never granted)
-- ---------------------------------------------------------------------

-- guidelines/PHONE-NUMBER-NORMALIZATION.md: strip spaces/marks, +213/213 → 0
create function private.store_norm_phone(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when x ~ '^213[0-9]{9}$' then '0' || substr(x, 4)
    else x end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as x) s;
$$;

create function private.store_require_admin() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := auth.uid();
begin
  if v is null or not exists (select 1 from store.admins a where a.user_id = v) then
    raise exception 'NOT_ADMIN';
  end if;
  return v;
end;
$$;

create function private.store_session_customer(p_token text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v bigint;
begin
  update store.customer_sessions s set last_used_at = now()
  from store.customers c
  where s.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
    and s.revoked_at is null and s.expires_at > now()
    and c.id = s.customer_id and c.active
  returning s.customer_id into v;
  if v is null then raise exception 'INVALID_SESSION'; end if;
  return v;
end;
$$;

create function private.store_check_password(p text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p is null or length(p) < 8 then raise exception 'PASSWORD_TOO_SHORT'; end if;
  if octet_length(p) > 72 then raise exception 'PASSWORD_TOO_LONG'; end if;
end;
$$;

-- Effect of each entry kind on (balance, debt)
create function private.store_kind_effect(p_kind text, out b int, out d int)
language sql immutable set search_path = '' as $$
  select v.b, v.d from (values
    ('debt', 1, 1), ('debt_refund', -1, -1),
    ('cash', 1, 0), ('cash_refund', -1, 0),
    ('pay', 0, -1), ('pay_refund', 0, 1),
    ('self', 1, 1),
    ('purchase', -1, 0), ('purchase_refund', 1, 0)
  ) v(k, b, d) where v.k = p_kind;
$$;

create function private.store_refund_kind(p_kind text) returns text
language sql immutable set search_path = '' as $$
  select case p_kind
    when 'debt' then 'debt_refund' when 'self' then 'debt_refund'
    when 'cash' then 'cash_refund' when 'pay' then 'pay_refund'
    when 'purchase' then 'purchase_refund' end;
$$;

-- The only writer of wallet entries. Caller must hold the customer row lock or let this take it.
create function private.store_post_entry(
  p_customer bigint, p_kind text, p_amount bigint, p_note text,
  p_order bigint, p_reverses bigint, p_request uuid, p_admin uuid
) returns store.wallet_entries
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  c store.customers;
  e record;
  r store.wallet_entries;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  select * into e from private.store_kind_effect(p_kind);
  if e.b is null then raise exception 'INVALID_KIND'; end if;
  select * into c from store.customers where id = p_customer for update;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  if c.balance + e.b * p_amount < 0 then raise exception 'INSUFFICIENT_BALANCE'; end if;
  if p_kind = 'self' and c.debt + p_amount > c.debt_limit then raise exception 'DEBT_LIMIT'; end if;

  update store.customers
     set balance = balance + e.b * p_amount, debt = debt + e.d * p_amount
   where id = p_customer;

  insert into store.wallet_entries
    (customer_id, kind, amount, d_balance, d_debt, balance_after, debt_after, note, order_id, reverses_id, request_id, created_by)
  values
    (p_customer, p_kind, p_amount, e.b * p_amount, e.d * p_amount,
     c.balance + e.b * p_amount, c.debt + e.d * p_amount,
     nullif(btrim(coalesce(p_note, '')), ''), p_order, p_reverses, p_request, p_admin)
  returning * into r;
  return r;
end;
$$;

-- ---------------------------------------------------------------------
-- Customer API (anon): private implementations
-- ---------------------------------------------------------------------

-- Returns one row on success, no rows on any failure (wrong phone/password, locked, inactive).
create function private.store_login_impl(p_phone text, p_password text)
returns table (session_token text, customer_name text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  c store.customers;
  v_token text;
  v_ok boolean;
begin
  select * into c from store.customers where phone = private.store_norm_phone(p_phone) for update;
  -- Same work and same error whether the phone exists, is locked, or is inactive (no enumeration).
  v_ok := c.id is not null
          and c.password_hash = extensions.crypt(coalesce(p_password, ''), c.password_hash);
  if c.id is null then
    perform extensions.crypt(coalesce(p_password, ''), '$2a$12$abcdefghijklmnopqrstuu');
  end if;
  if c.id is not null and (not c.active or (c.locked_until is not null and c.locked_until > now())) then
    v_ok := false;
  end if;

  if not v_ok then
    if c.id is not null and c.active and (c.locked_until is null or c.locked_until <= now()) then
      if c.login_failures + 1 >= 5 then
        update store.customers
           set login_failures = 0, lock_count = lock_count + 1,
               locked_until = now() + case when c.lock_count = 0 then interval '5 minutes'
                                          when c.lock_count = 1 then interval '15 minutes'
                                          else interval '60 minutes' end
         where id = c.id;
      else
        update store.customers set login_failures = login_failures + 1 where id = c.id;
      end if;
    end if;
    -- No exception here: it would roll back the failure counter. No row = invalid login.
    return;
  end if;

  update store.customers set login_failures = 0, lock_count = 0, locked_until = null where id = c.id;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into store.customer_sessions (customer_id, token_hash, expires_at)
  values (c.id, encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '30 days');
  return query select v_token, c.name;
end;
$$;

create function private.store_logout_impl(p_token text) returns void
language sql security definer set search_path = '' as $$
  update store.customer_sessions set revoked_at = now()
  where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex') and revoked_at is null;
$$;

create function private.store_me_impl(p_token text)
returns table (name text, phone text, balance bigint, debt bigint, debt_limit bigint, self_topup boolean, profit bigint, announcement text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select c.name, c.phone, c.balance, c.debt, c.debt_limit, c.self_topup,
         coalesce((select sum(o.base_amount - o.charged_amount) from store.orders o where o.customer_id = v and o.status = 'done'), 0)::bigint,
         (select s.announcement from store.settings s where s.id = 1)
  from store.customers c where c.id = v;
end;
$$;

-- Only the default selling price is exposed in the catalog (owner decision).
create function private.store_catalog_impl(p_token text)
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_session_customer(p_token);
  return query
  select p.id, b.name, b.category, p.name, p.base_price,
         exists (select 1 from store.codes k where k.product_id = p.id and k.status = 'available'),
         b.sort, p.sort
  from store.products p join store.brands b on b.id = p.brand_id
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;

create function private.store_rates_impl(p_token text)
returns table (product_id bigint, brand text, name text, pct numeric)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select p.id, b.name, p.name, coalesce(r.pct, 0)
  from store.products p join store.brands b on b.id = p.brand_id
  left join store.customer_rates r on r.customer_id = v and r.product_id = p.id
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;

create function private.store_buy_impl(p_token text, p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v bigint := private.store_session_customer(p_token);
  o store.orders;
  p record;
  c store.customers;
  v_pct numeric(5,2);
  v_unit bigint;
  v_charged bigint;
  v_ids bigint[];
  v_cost bigint;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into o from store.orders where request_id = p_request_id;
  if found then
    if o.customer_id <> v then raise exception 'REQUEST_ID_CONFLICT'; end if;
  else
    if p_qty is null or p_qty < 1 or p_qty > 20 then raise exception 'INVALID_QTY'; end if;
    select pr.id, pr.base_price, pr.name into p
    from store.products pr join store.brands b on b.id = pr.brand_id
    where pr.id = p_product_id and pr.active and b.active;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

    select * into c from store.customers where id = v for update;   -- serializes this customer's money
    select coalesce((select r.pct from store.customer_rates r where r.customer_id = v and r.product_id = p.id), 0) into v_pct;
    v_unit := round(p.base_price * (1 - v_pct / 100));
    v_charged := v_unit * p_qty;
    if c.balance < v_charged then raise exception 'INSUFFICIENT_BALANCE'; end if;

    select array_agg(id order by id) into v_ids from (
      select k.id from store.codes k
      where k.product_id = p.id and k.status = 'available'
      order by k.id limit p_qty
      for update skip locked) s;
    if coalesce(array_length(v_ids, 1), 0) < p_qty then raise exception 'OUT_OF_STOCK'; end if;
    select case when bool_and(k.cost is not null) then sum(k.cost) end into v_cost
    from store.codes k where k.id = any (v_ids);

    insert into store.orders (customer_id, product_id, qty, base_amount, pct, charged_amount, cost_amount, balance_after, request_id)
    values (v, p.id, p_qty, p.base_price * p_qty, v_pct, v_charged, v_cost, c.balance - v_charged, p_request_id)
    returning * into o;
    update store.codes set status = 'sold', order_id = o.id, sold_at = now() where id = any (v_ids);
    perform private.store_post_entry(v, 'purchase', v_charged, null, o.id, null, null, null);
  end if;

  return query
  select o.id, pr.name, o.qty,
         coalesce((select jsonb_agg(jsonb_build_object('code', k.code, 'serial', k.serial) order by k.id)
                   from store.codes k where k.order_id = o.id), '[]'::jsonb)
  from store.products pr where pr.id = o.product_id;
end;
$$;

create function private.store_orders_impl(
  p_token text, p_category text, p_from date, p_to date, p_query text, p_limit int, p_offset int)
returns table (order_id bigint, brand text, category text, product_name text, qty int, base_amount bigint,
               charged_amount bigint, profit bigint, balance_after bigint, status text, created_at timestamptz, total_count bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select o.id, b.name, b.category, p.name, o.qty, o.base_amount, o.charged_amount,
         o.base_amount - o.charged_amount, o.balance_after, o.status, o.created_at,
         count(*) over ()
  from store.orders o join store.products p on p.id = o.product_id join store.brands b on b.id = p.brand_id
  where o.customer_id = v
    and (p_category is null or b.category = p_category)
    and (p_from is null or o.created_at >= p_from)
    and (p_to is null or o.created_at < p_to + 1)
    and (nullif(btrim(p_query), '') is null or p.name ilike '%' || btrim(p_query) || '%' or o.id::text = btrim(p_query))
  order by o.created_at desc, o.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create function private.store_order_codes_impl(p_token text, p_order_id bigint)
returns table (code text, serial text, status text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  if not exists (select 1 from store.orders o where o.id = p_order_id and o.customer_id = v) then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  return query select k.code, k.serial, k.status from store.codes k where k.order_id = p_order_id order by k.id;
end;
$$;

create function private.store_entries_impl(p_token text, p_limit int, p_offset int)
returns table (entry_id bigint, kind text, amount bigint, d_balance bigint, d_debt bigint, balance_after bigint,
               debt_after bigint, note text, reversed boolean, reverses_id bigint, created_at timestamptz, total_count bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select e.id, e.kind, e.amount, e.d_balance, e.d_debt, e.balance_after, e.debt_after, e.note,
         exists (select 1 from store.wallet_entries x where x.reverses_id = e.id), e.reverses_id, e.created_at,
         count(*) over ()
  from store.wallet_entries e where e.customer_id = v
  order by e.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create function private.store_self_topup_impl(p_token text, p_amount bigint, p_request_id uuid)
returns table (balance bigint, debt bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v bigint := private.store_session_customer(p_token);
  r store.wallet_entries;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into r from store.wallet_entries where request_id = p_request_id;
  if not found then
    if not (select c.self_topup from store.customers c where c.id = v) then raise exception 'SELF_TOPUP_DISABLED'; end if;
    r := private.store_post_entry(v, 'self', p_amount, 'شحن ذاتي', null, null, p_request_id, null);
  elsif r.customer_id <> v then
    raise exception 'REQUEST_ID_CONFLICT';
  end if;
  return query select c.balance, c.debt from store.customers c where c.id = v;
end;
$$;

create function private.store_change_password_impl(p_token text, p_old text, p_new text) returns void
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  if not exists (select 1 from store.customers c where c.id = v and c.password_hash = extensions.crypt(coalesce(p_old, ''), c.password_hash)) then
    raise exception 'INVALID_PASSWORD';
  end if;
  perform private.store_check_password(p_new);
  update store.customers set password_hash = extensions.crypt(p_new, extensions.gen_salt('bf', 12)) where id = v;
  -- Sign out every other device; keep the current one.
  update store.customer_sessions set revoked_at = now()
  where customer_id = v and revoked_at is null
    and token_hash <> encode(extensions.digest(p_token, 'sha256'), 'hex');
end;
$$;

-- ---------------------------------------------------------------------
-- Admin API (authenticated + store.admins): private implementations
-- ---------------------------------------------------------------------

create function private.store_admin_is_admin_impl() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from store.admins a where a.user_id = auth.uid());
$$;

create function private.store_admin_customers_impl()
returns table (customer_id bigint, name text, phone text, active boolean, balance bigint, debt bigint,
               debt_limit bigint, self_topup boolean, locked_until timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select c.id, c.name, c.phone, c.active, c.balance, c.debt, c.debt_limit, c.self_topup, c.locked_until, c.created_at
  from store.customers c order by c.name;
end;
$$;

create function private.store_admin_create_customer_impl(p_name text, p_phone text, p_password text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v bigint;
  v_phone text := private.store_norm_phone(p_phone);
begin
  perform private.store_require_admin();
  if v_phone !~ '^0[5-7][0-9]{8}$' then raise exception 'INVALID_PHONE'; end if;
  if exists (select 1 from store.customers c where c.phone = v_phone) then raise exception 'PHONE_EXISTS'; end if;
  perform private.store_check_password(p_password);
  insert into store.customers (name, phone, password_hash)
  values (btrim(p_name), v_phone, extensions.crypt(p_password, extensions.gen_salt('bf', 12)))
  returning id into v;
  insert into store.customer_rates (customer_id, product_id, pct)
  select v, d.product_id, d.pct from store.default_rates d where d.pct > 0;
  return v;
end;
$$;

create function private.store_admin_update_customer_impl(
  p_customer_id bigint, p_name text, p_phone text, p_debt_limit bigint, p_self_topup boolean, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare v_phone text := case when p_phone is null then null else private.store_norm_phone(p_phone) end;
begin
  perform private.store_require_admin();
  if v_phone is not null and v_phone !~ '^0[5-7][0-9]{8}$' then raise exception 'INVALID_PHONE'; end if;
  if v_phone is not null and exists (select 1 from store.customers c where c.phone = v_phone and c.id <> p_customer_id) then
    raise exception 'PHONE_EXISTS';
  end if;
  update store.customers set
    name = coalesce(nullif(btrim(p_name), ''), name),
    phone = coalesce(v_phone, phone),
    debt_limit = coalesce(p_debt_limit, debt_limit),
    self_topup = coalesce(p_self_topup, self_topup),
    active = coalesce(p_active, active)
  where id = p_customer_id;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  if p_active is false then
    update store.customer_sessions set revoked_at = now() where customer_id = p_customer_id and revoked_at is null;
  end if;
end;
$$;

create function private.store_admin_set_password_impl(p_customer_id bigint, p_password text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  perform private.store_check_password(p_password);
  update store.customers
     set password_hash = extensions.crypt(p_password, extensions.gen_salt('bf', 12)),
         login_failures = 0, lock_count = 0, locked_until = null
   where id = p_customer_id;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  update store.customer_sessions set revoked_at = now() where customer_id = p_customer_id and revoked_at is null;
end;
$$;

create function private.store_admin_revoke_sessions_impl(p_customer_id bigint) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.store_require_admin();
  update store.customer_sessions set revoked_at = now() where customer_id = p_customer_id and revoked_at is null;
  get diagnostics n = row_count;
  return n;
end;
$$;

create function private.store_admin_transfer_impl(
  p_customer_id bigint, p_kind text, p_amount bigint, p_note text, p_request_id uuid)
returns table (entry_id bigint, balance_after bigint, debt_after bigint, over_limit boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  a uuid := private.store_require_admin();
  r store.wallet_entries;
begin
  if p_kind not in ('debt', 'cash', 'pay', 'debt_refund', 'cash_refund', 'pay_refund') then raise exception 'INVALID_KIND'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into r from store.wallet_entries where request_id = p_request_id;
  if not found then
    r := private.store_post_entry(p_customer_id, p_kind, p_amount, p_note, null, null, p_request_id, a);
  end if;
  -- The debt limit never blocks the admin; it is reported so the UI can warn.
  return query select r.id, r.balance_after, r.debt_after,
         r.debt_after > (select c.debt_limit from store.customers c where c.id = r.customer_id);
end;
$$;

create function private.store_admin_reverse_impl(p_entry_id bigint, p_note text, p_request_id uuid)
returns table (entry_id bigint, kind text, balance_after bigint, debt_after bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  a uuid := private.store_require_admin();
  e store.wallet_entries;
  r store.wallet_entries;
  v_kind text;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into r from store.wallet_entries where request_id = p_request_id;
  if not found then
    select * into e from store.wallet_entries where id = p_entry_id;
    if not found then raise exception 'ENTRY_NOT_FOUND'; end if;
    v_kind := private.store_refund_kind(e.kind);
    if v_kind is null then raise exception 'NOT_REVERSIBLE'; end if;
    if exists (select 1 from store.wallet_entries x where x.reverses_id = e.id) then raise exception 'ALREADY_REVERSED'; end if;
    r := private.store_post_entry(e.customer_id, v_kind, e.amount, p_note, e.order_id, e.id, p_request_id, a);
    if e.kind = 'purchase' then
      update store.orders set status = 'refunded' where id = e.order_id;
      update store.codes set status = 'void' where order_id = e.order_id;   -- seen by the customer: never resold
    end if;
  end if;
  return query select r.id, r.kind, r.balance_after, r.debt_after;
end;
$$;

create function private.store_admin_entries_impl(
  p_customer_id bigint, p_kind text, p_from date, p_to date, p_limit int, p_offset int)
returns table (entry_id bigint, customer_id bigint, customer_name text, kind text, amount bigint, d_balance bigint, d_debt bigint,
               balance_after bigint, debt_after bigint, note text, order_id bigint, reversed boolean, reverses_id bigint,
               created_at timestamptz, total_count bigint, total_amount numeric)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select e.id, e.customer_id, c.name, e.kind, e.amount, e.d_balance, e.d_debt, e.balance_after, e.debt_after, e.note,
         e.order_id, exists (select 1 from store.wallet_entries x where x.reverses_id = e.id), e.reverses_id, e.created_at,
         count(*) over (), sum(e.amount) over ()
  from store.wallet_entries e join store.customers c on c.id = e.customer_id
  where (p_customer_id is null or e.customer_id = p_customer_id)
    and (p_kind is null or (p_kind = 'refund' and e.kind like '%\_refund') or e.kind = p_kind)
    and (p_from is null or e.created_at >= p_from)
    and (p_to is null or e.created_at < p_to + 1)
  order by e.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create function private.store_admin_orders_impl(
  p_customer_id bigint, p_category text, p_from date, p_to date, p_query text, p_limit int, p_offset int)
returns table (order_id bigint, customer_id bigint, customer_name text, brand text, category text, product_name text, qty int,
               base_amount bigint, charged_amount bigint, cost_amount bigint, profit bigint, balance_after bigint, status text,
               created_at timestamptz, total_count bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select o.id, o.customer_id, c.name, b.name, b.category, p.name, o.qty, o.base_amount, o.charged_amount, o.cost_amount,
         o.charged_amount - o.cost_amount, o.balance_after, o.status, o.created_at, count(*) over ()
  from store.orders o join store.customers c on c.id = o.customer_id
  join store.products p on p.id = o.product_id join store.brands b on b.id = p.brand_id
  where (p_customer_id is null or o.customer_id = p_customer_id)
    and (p_category is null or b.category = p_category)
    and (p_from is null or o.created_at >= p_from)
    and (p_to is null or o.created_at < p_to + 1)
    and (nullif(btrim(p_query), '') is null or p.name ilike '%' || btrim(p_query) || '%'
         or c.name ilike '%' || btrim(p_query) || '%' or o.id::text = btrim(p_query))
  order by o.created_at desc, o.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- Codes are masked for the admin; revealing one is logged.
create function private.store_admin_order_codes_impl(p_order_id bigint)
returns table (code_id bigint, masked_code text, serial text, status text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select k.id, '****' || right(k.code, 4), k.serial, k.status
  from store.codes k where k.order_id = p_order_id order by k.id;
end;
$$;

create function private.store_admin_reveal_code_impl(p_code_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  a uuid := private.store_require_admin();
  v text;
begin
  select k.code into v from store.codes k where k.id = p_code_id;
  if v is null then raise exception 'CODE_NOT_FOUND'; end if;
  insert into store.code_reveals (code_id, admin_id) values (p_code_id, a);
  return v;
end;
$$;

-- One code per line; optional serial after ; , or |
create function private.store_admin_add_codes_impl(p_product_id bigint, p_supplier_id bigint, p_cost bigint, p_lines text)
returns table (batch_id bigint, added int, duplicates int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  a uuid := private.store_require_admin();
  v_batch bigint;
  v_supplier bigint := coalesce(p_supplier_id, (select s.id from store.suppliers s where s.is_default));
  v_total int;
  v_added int;
begin
  if not exists (select 1 from store.products p where p.id = p_product_id) then raise exception 'PRODUCT_NOT_FOUND'; end if;
  if not exists (select 1 from store.suppliers s where s.id = v_supplier) then raise exception 'SUPPLIER_NOT_FOUND'; end if;
  if p_cost is not null and p_cost <= 0 then raise exception 'INVALID_COST'; end if;

  select count(*) into v_total from regexp_split_to_table(coalesce(p_lines, ''), E'\r?\n') l where btrim(l) <> '';
  if v_total = 0 then raise exception 'NO_CODES'; end if;
  if v_total > 5000 then raise exception 'TOO_MANY_CODES'; end if;

  insert into store.code_batches (product_id, supplier_id, cost, added, duplicates, created_by)
  values (p_product_id, v_supplier, p_cost, 0, 0, a) returning id into v_batch;
  insert into store.codes (product_id, batch_id, supplier_id, code, serial, cost)
  select distinct on (y.code) p_product_id, v_batch, v_supplier, y.code, y.serial, p_cost
  from (
    select btrim(split_part(x.l, x.sep, 1)) as code,
           nullif(btrim(substr(x.l, length(split_part(x.l, x.sep, 1)) + 2)), '') as serial
    from (select l, coalesce(substring(l from '[;,|]'), ';') as sep
          from regexp_split_to_table(coalesce(p_lines, ''), E'\r?\n') as l) x
  ) y
  where y.code <> ''
  on conflict (product_id, code) do nothing;
  get diagnostics v_added = row_count;
  -- duplicates = repeated inside the paste + already in stock
  update store.code_batches set added = v_added, duplicates = v_total - v_added where id = v_batch;
  return query select b.id, b.added, b.duplicates from store.code_batches b where b.id = v_batch;
end;
$$;

create function private.store_admin_stock_impl()
returns table (product_id bigint, brand_id bigint, brand text, category text, name text, base_price bigint, active boolean,
               brand_active boolean, available bigint, sold bigint, voided bigint, sort int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select p.id, b.id, b.name, b.category, p.name, p.base_price, p.active, b.active,
         count(k.id) filter (where k.status = 'available'),
         count(k.id) filter (where k.status = 'sold'),
         count(k.id) filter (where k.status = 'void'), p.sort
  from store.products p join store.brands b on b.id = p.brand_id
  left join store.codes k on k.product_id = p.id
  group by p.id, b.id
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;

create function private.store_admin_brands_impl()
returns table (brand_id bigint, name text, category text, sort int, active boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select b.id, b.name, b.category, b.sort, b.active from store.brands b order by b.category, b.sort;
end;
$$;

create function private.store_admin_save_brand_impl(p_brand_id bigint, p_name text, p_category text, p_sort int, p_active boolean)
returns bigint
language plpgsql security definer set search_path = '' as $$
declare v bigint;
begin
  perform private.store_require_admin();
  if p_brand_id is null then
    insert into store.brands (name, category, sort, active)
    values (btrim(p_name), p_category, coalesce(p_sort, 0), coalesce(p_active, true)) returning id into v;
  else
    update store.brands set name = coalesce(nullif(btrim(p_name), ''), name), category = coalesce(p_category, category),
      sort = coalesce(p_sort, sort), active = coalesce(p_active, active)
    where id = p_brand_id returning id into v;
    if v is null then raise exception 'BRAND_NOT_FOUND'; end if;
  end if;
  return v;
end;
$$;

create function private.store_admin_save_product_impl(
  p_product_id bigint, p_brand_id bigint, p_name text, p_base_price bigint, p_sort int, p_active boolean) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v bigint;
begin
  perform private.store_require_admin();
  if p_product_id is null then
    insert into store.products (brand_id, name, base_price, sort, active)
    values (p_brand_id, btrim(p_name), p_base_price, coalesce(p_sort, 0), coalesce(p_active, true)) returning id into v;
  else
    update store.products set brand_id = coalesce(p_brand_id, brand_id), name = coalesce(nullif(btrim(p_name), ''), name),
      base_price = coalesce(p_base_price, base_price), sort = coalesce(p_sort, sort), active = coalesce(p_active, active)
    where id = p_product_id returning id into v;
    if v is null then raise exception 'PRODUCT_NOT_FOUND'; end if;
  end if;
  return v;
end;
$$;

create function private.store_admin_suppliers_impl()
returns table (supplier_id bigint, name text, is_default boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select s.id, s.name, s.is_default from store.suppliers s order by s.is_default desc, s.name;
end;
$$;

create function private.store_admin_add_supplier_impl(p_name text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v bigint;
begin
  perform private.store_require_admin();
  if exists (select 1 from store.suppliers s where lower(s.name) = lower(btrim(p_name))) then raise exception 'SUPPLIER_EXISTS'; end if;
  insert into store.suppliers (name) values (btrim(p_name)) returning id into v;
  return v;
end;
$$;

-- Rate matrix for one category; customer_id null = the default row
create function private.store_admin_rates_impl(p_category text)
returns table (customer_id bigint, customer_name text, product_id bigint, product_name text, base_price bigint, pct numeric)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  with prods as (
    select p.id, p.name, p.base_price, b.sort as bs, p.sort as ps
    from store.products p join store.brands b on b.id = p.brand_id
    where p_category is null or b.category = p_category)
  select null::bigint, 'افتراضي'::text, pr.id, pr.name, pr.base_price, coalesce(d.pct, 0)
  from prods pr left join store.default_rates d on d.product_id = pr.id
  union all
  select c.id, c.name, pr.id, pr.name, pr.base_price, coalesce(r.pct, 0)
  from store.customers c cross join prods pr
  left join store.customer_rates r on r.customer_id = c.id and r.product_id = pr.id;
end;
$$;

create function private.store_admin_set_rate_impl(p_customer_id bigint, p_product_id bigint, p_pct numeric) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  if p_pct is null or p_pct < 0 or p_pct > 50 then raise exception 'INVALID_PCT'; end if;
  if p_customer_id is null then
    insert into store.default_rates (product_id, pct) values (p_product_id, p_pct)
    on conflict (product_id) do update set pct = excluded.pct;
  else
    insert into store.customer_rates (customer_id, product_id, pct) values (p_customer_id, p_product_id, p_pct)
    on conflict (customer_id, product_id) do update set pct = excluded.pct;
  end if;
end;
$$;

create function private.store_admin_set_announcement_impl(p_text text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.settings set announcement = left(coalesce(p_text, ''), 500), updated_at = now() where id = 1;
end;
$$;

-- Stored balance/debt must equal the ledger; returns only mismatches (empty = healthy)
create function private.store_admin_reconcile_impl()
returns table (customer_id bigint, stored_balance bigint, ledger_balance bigint, stored_debt bigint, ledger_debt bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select c.id, c.balance, coalesce(sum(e.d_balance), 0)::bigint, c.debt, coalesce(sum(e.d_debt), 0)::bigint
  from store.customers c left join store.wallet_entries e on e.customer_id = c.id
  group by c.id
  having c.balance <> coalesce(sum(e.d_balance), 0) or c.debt <> coalesce(sum(e.d_debt), 0);
end;
$$;

-- ---------------------------------------------------------------------
-- Public API: thin SECURITY INVOKER wrappers (the MyTool pattern)
-- ---------------------------------------------------------------------
create function public.store_login(p_phone text, p_password text) returns table (session_token text, customer_name text)
language sql set search_path = '' as $$ select * from private.store_login_impl(p_phone, p_password); $$;
create function public.store_logout(p_token text) returns void
language sql set search_path = '' as $$ select private.store_logout_impl(p_token); $$;
create function public.store_me(p_token text)
returns table (name text, phone text, balance bigint, debt bigint, debt_limit bigint, self_topup boolean, profit bigint, announcement text)
language sql set search_path = '' as $$ select * from private.store_me_impl(p_token); $$;
create function public.store_catalog(p_token text)
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int)
language sql set search_path = '' as $$ select * from private.store_catalog_impl(p_token); $$;
create function public.store_rates(p_token text) returns table (product_id bigint, brand text, name text, pct numeric)
language sql set search_path = '' as $$ select * from private.store_rates_impl(p_token); $$;
create function public.store_buy(p_token text, p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language sql set search_path = '' as $$ select * from private.store_buy_impl(p_token, p_product_id, p_qty, p_request_id); $$;
create function public.store_orders(p_token text, p_category text, p_from date, p_to date, p_query text, p_limit int, p_offset int)
returns table (order_id bigint, brand text, category text, product_name text, qty int, base_amount bigint, charged_amount bigint,
               profit bigint, balance_after bigint, status text, created_at timestamptz, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_orders_impl(p_token, p_category, p_from, p_to, p_query, p_limit, p_offset); $$;
create function public.store_order_codes(p_token text, p_order_id bigint) returns table (code text, serial text, status text)
language sql set search_path = '' as $$ select * from private.store_order_codes_impl(p_token, p_order_id); $$;
create function public.store_entries(p_token text, p_limit int, p_offset int)
returns table (entry_id bigint, kind text, amount bigint, d_balance bigint, d_debt bigint, balance_after bigint, debt_after bigint,
               note text, reversed boolean, reverses_id bigint, created_at timestamptz, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_entries_impl(p_token, p_limit, p_offset); $$;
create function public.store_self_topup(p_token text, p_amount bigint, p_request_id uuid) returns table (balance bigint, debt bigint)
language sql set search_path = '' as $$ select * from private.store_self_topup_impl(p_token, p_amount, p_request_id); $$;
create function public.store_change_password(p_token text, p_old text, p_new text) returns void
language sql set search_path = '' as $$ select private.store_change_password_impl(p_token, p_old, p_new); $$;

create function public.store_admin_is_admin() returns boolean
language sql set search_path = '' as $$ select private.store_admin_is_admin_impl(); $$;
create function public.store_admin_customers()
returns table (customer_id bigint, name text, phone text, active boolean, balance bigint, debt bigint, debt_limit bigint,
               self_topup boolean, locked_until timestamptz, created_at timestamptz)
language sql set search_path = '' as $$ select * from private.store_admin_customers_impl(); $$;
create function public.store_admin_create_customer(p_name text, p_phone text, p_password text) returns bigint
language sql set search_path = '' as $$ select private.store_admin_create_customer_impl(p_name, p_phone, p_password); $$;
create function public.store_admin_update_customer(p_customer_id bigint, p_name text, p_phone text, p_debt_limit bigint, p_self_topup boolean, p_active boolean) returns void
language sql set search_path = '' as $$ select private.store_admin_update_customer_impl(p_customer_id, p_name, p_phone, p_debt_limit, p_self_topup, p_active); $$;
create function public.store_admin_set_password(p_customer_id bigint, p_password text) returns void
language sql set search_path = '' as $$ select private.store_admin_set_password_impl(p_customer_id, p_password); $$;
create function public.store_admin_revoke_sessions(p_customer_id bigint) returns int
language sql set search_path = '' as $$ select private.store_admin_revoke_sessions_impl(p_customer_id); $$;
create function public.store_admin_transfer(p_customer_id bigint, p_kind text, p_amount bigint, p_note text, p_request_id uuid)
returns table (entry_id bigint, balance_after bigint, debt_after bigint, over_limit boolean)
language sql set search_path = '' as $$ select * from private.store_admin_transfer_impl(p_customer_id, p_kind, p_amount, p_note, p_request_id); $$;
create function public.store_admin_reverse(p_entry_id bigint, p_note text, p_request_id uuid)
returns table (entry_id bigint, kind text, balance_after bigint, debt_after bigint)
language sql set search_path = '' as $$ select * from private.store_admin_reverse_impl(p_entry_id, p_note, p_request_id); $$;
create function public.store_admin_entries(p_customer_id bigint, p_kind text, p_from date, p_to date, p_limit int, p_offset int)
returns table (entry_id bigint, customer_id bigint, customer_name text, kind text, amount bigint, d_balance bigint, d_debt bigint,
               balance_after bigint, debt_after bigint, note text, order_id bigint, reversed boolean, reverses_id bigint,
               created_at timestamptz, total_count bigint, total_amount numeric)
language sql set search_path = '' as $$ select * from private.store_admin_entries_impl(p_customer_id, p_kind, p_from, p_to, p_limit, p_offset); $$;
create function public.store_admin_orders(p_customer_id bigint, p_category text, p_from date, p_to date, p_query text, p_limit int, p_offset int)
returns table (order_id bigint, customer_id bigint, customer_name text, brand text, category text, product_name text, qty int,
               base_amount bigint, charged_amount bigint, cost_amount bigint, profit bigint, balance_after bigint, status text,
               created_at timestamptz, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_admin_orders_impl(p_customer_id, p_category, p_from, p_to, p_query, p_limit, p_offset); $$;
create function public.store_admin_order_codes(p_order_id bigint) returns table (code_id bigint, masked_code text, serial text, status text)
language sql set search_path = '' as $$ select * from private.store_admin_order_codes_impl(p_order_id); $$;
create function public.store_admin_reveal_code(p_code_id bigint) returns text
language sql set search_path = '' as $$ select private.store_admin_reveal_code_impl(p_code_id); $$;
create function public.store_admin_add_codes(p_product_id bigint, p_supplier_id bigint, p_cost bigint, p_lines text)
returns table (batch_id bigint, added int, duplicates int)
language sql set search_path = '' as $$ select * from private.store_admin_add_codes_impl(p_product_id, p_supplier_id, p_cost, p_lines); $$;
create function public.store_admin_stock()
returns table (product_id bigint, brand_id bigint, brand text, category text, name text, base_price bigint, active boolean,
               brand_active boolean, available bigint, sold bigint, voided bigint, sort int)
language sql set search_path = '' as $$ select * from private.store_admin_stock_impl(); $$;
create function public.store_admin_brands() returns table (brand_id bigint, name text, category text, sort int, active boolean)
language sql set search_path = '' as $$ select * from private.store_admin_brands_impl(); $$;
create function public.store_admin_save_brand(p_brand_id bigint, p_name text, p_category text, p_sort int, p_active boolean) returns bigint
language sql set search_path = '' as $$ select private.store_admin_save_brand_impl(p_brand_id, p_name, p_category, p_sort, p_active); $$;
create function public.store_admin_save_product(p_product_id bigint, p_brand_id bigint, p_name text, p_base_price bigint, p_sort int, p_active boolean) returns bigint
language sql set search_path = '' as $$ select private.store_admin_save_product_impl(p_product_id, p_brand_id, p_name, p_base_price, p_sort, p_active); $$;
create function public.store_admin_suppliers() returns table (supplier_id bigint, name text, is_default boolean)
language sql set search_path = '' as $$ select * from private.store_admin_suppliers_impl(); $$;
create function public.store_admin_add_supplier(p_name text) returns bigint
language sql set search_path = '' as $$ select private.store_admin_add_supplier_impl(p_name); $$;
create function public.store_admin_rates(p_category text)
returns table (customer_id bigint, customer_name text, product_id bigint, product_name text, base_price bigint, pct numeric)
language sql set search_path = '' as $$ select * from private.store_admin_rates_impl(p_category); $$;
create function public.store_admin_set_rate(p_customer_id bigint, p_product_id bigint, p_pct numeric) returns void
language sql set search_path = '' as $$ select private.store_admin_set_rate_impl(p_customer_id, p_product_id, p_pct); $$;
create function public.store_admin_set_announcement(p_text text) returns void
language sql set search_path = '' as $$ select private.store_admin_set_announcement_impl(p_text); $$;
create function public.store_admin_reconcile()
returns table (customer_id bigint, stored_balance bigint, ledger_balance bigint, stored_debt bigint, ledger_debt bigint)
language sql set search_path = '' as $$ select * from private.store_admin_reconcile_impl(); $$;

-- ---------------------------------------------------------------------
-- Grants: Postgres grants EXECUTE to PUBLIC by default — revoke everything, then grant exactly.
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname = 'private' and p.proname like 'store\_%')
       or (n.nspname = 'public' and p.proname like 'store\_%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.name like 'store\_admin\_%' then
      -- admin API: signed-in Supabase users only; the impl still checks store.admins
      if f.sch = 'public' or f.name like '%\_impl' then
        execute format('grant execute on function %s to authenticated', f.sig);
      end if;
    elsif f.name like '%\_impl' or f.sch = 'public' then
      -- customer API: token-based, independent of Supabase Auth sessions
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
