-- =====================================================================
-- Card Store v1.2 — «حساب المحل»: the owner's own wallet account
-- Owner decisions (2026-10-21): own account he tops up himself; own
-- percentage per product; follow-up "since last top-up" and by date.
-- The shop account cannot sign in by phone; the admin reaches it from
-- the admin UI. Its top-ups are a separate kind, never mixed with
-- customer payments.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------
alter table store.customers add column is_shop boolean not null default false;
create unique index customers_one_shop on store.customers (is_shop) where is_shop;
alter table store.customers alter column phone drop not null;
alter table store.customers add constraint customers_phone_or_shop check (is_shop or phone is not null);

alter table store.wallet_entries drop constraint wallet_entries_kind_check;
alter table store.wallet_entries add constraint wallet_entries_kind_check check (kind in (
  'debt', 'debt_refund', 'cash', 'cash_refund', 'pay', 'pay_refund', 'self',
  'purchase', 'purchase_refund', 'shop_topup', 'shop_topup_refund'));

-- The shop account exists from the start; no phone, unusable password
insert into store.customers (name, phone, password_hash, is_shop)
values ('المحل ★', null, extensions.crypt(encode(extensions.gen_random_bytes(24), 'hex'), extensions.gen_salt('bf', 12)), true);

create or replace function private.store_kind_effect(p_kind text, out b int, out d int)
language sql immutable set search_path = '' as $$
  select v.b, v.d from (values
    ('debt', 1, 1), ('debt_refund', -1, -1),
    ('cash', 1, 0), ('cash_refund', -1, 0),
    ('pay', 0, -1), ('pay_refund', 0, 1),
    ('self', 1, 1),
    ('purchase', -1, 0), ('purchase_refund', 1, 0),
    ('shop_topup', 1, 0), ('shop_topup_refund', -1, 0)
  ) v(k, b, d) where v.k = p_kind;
$$;

create or replace function private.store_refund_kind(p_kind text) returns text
language sql immutable set search_path = '' as $$
  select case p_kind
    when 'debt' then 'debt_refund' when 'self' then 'debt_refund'
    when 'cash' then 'cash_refund' when 'pay' then 'pay_refund'
    when 'purchase' then 'purchase_refund'
    when 'shop_topup' then 'shop_topup_refund' end;
$$;

create function private.store_shop_id() returns bigint
language sql stable security definer set search_path = '' as $$
  select c.id from store.customers c where c.is_shop;
$$;

-- ---------------------------------------------------------------------
-- Purchase core shared by customers and the shop account
-- ---------------------------------------------------------------------
create function private.store_buy_core(p_customer bigint, p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
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
    if o.customer_id <> p_customer then raise exception 'REQUEST_ID_CONFLICT'; end if;
  else
    if p_qty is null or p_qty < 1 or p_qty > 20 then raise exception 'INVALID_QTY'; end if;
    select pr.id, pr.base_price, pr.name into p
    from store.products pr join store.brands b on b.id = pr.brand_id
    where pr.id = p_product_id and pr.active and b.active;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

    select * into c from store.customers where id = p_customer for update;
    select coalesce((select r.pct from store.customer_rates r where r.customer_id = p_customer and r.product_id = p.id), 0) into v_pct;
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
    values (p_customer, p.id, p_qty, p.base_price * p_qty, v_pct, v_charged, v_cost, c.balance - v_charged, p_request_id)
    returning * into o;
    update store.codes set status = 'sold', order_id = o.id, sold_at = now() where id = any (v_ids);
    perform private.store_post_entry(p_customer, 'purchase', v_charged, null, o.id, null, null, null);
  end if;

  return query
  select o.id, pr.name, o.qty,
         coalesce((select jsonb_agg(jsonb_build_object('code', k.code, 'serial', k.serial) order by k.id)
                   from store.codes k where k.order_id = o.id), '[]'::jsonb)
  from store.products pr where pr.id = o.product_id;
end;
$$;

create or replace function private.store_buy_impl(p_token text, p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  return query select * from private.store_buy_core(v, p_product_id, p_qty, p_request_id);
end;
$$;

create function private.store_catalog_core()
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int)
language sql stable security definer set search_path = '' as $$
  select p.id, b.name, b.category, p.name, p.base_price,
         exists (select 1 from store.codes k where k.product_id = p.id and k.status = 'available'),
         b.sort, p.sort
  from store.products p join store.brands b on b.id = p.brand_id
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
$$;

create or replace function private.store_catalog_impl(p_token text)
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_session_customer(p_token);
  return query select * from private.store_catalog_core();
end;
$$;

-- ---------------------------------------------------------------------
-- Shop account API (admin only)
-- ---------------------------------------------------------------------
create function private.store_admin_shop_catalog_impl()
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select * from private.store_catalog_core();
end;
$$;

create function private.store_admin_shop_buy_impl(p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select * from private.store_buy_core(private.store_shop_id(), p_product_id, p_qty, p_request_id);
end;
$$;

create function private.store_admin_shop_topup_impl(p_amount bigint, p_note text, p_request_id uuid)
returns table (entry_id bigint, balance_after bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  a uuid := private.store_require_admin();
  r store.wallet_entries;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into r from store.wallet_entries where request_id = p_request_id;
  if not found then
    r := private.store_post_entry(private.store_shop_id(), 'shop_topup', p_amount, p_note, null, null, p_request_id, a);
  end if;
  return query select r.id, r.balance_after;
end;
$$;

-- Follow-up figures for the shop account in three scopes:
--   all        : since the beginning
--   since_last : since the last top-up (inclusive of purchases after it)
--   range      : between p_from and p_to (dates, inclusive); empty dates = no bound
-- profit_pct  = selling price − amount deducted (per the owner's own percentage)
-- real_profit = selling price − actual code cost, only where the cost was entered
create function private.store_admin_shop_summary_impl(p_from date, p_to date)
returns table (scope text, topups bigint, consumed bigint, orders_count bigint, profit_pct bigint,
               real_profit bigint, unknown_cost_orders bigint, balance bigint,
               last_topup_at timestamptz, last_topup_amount bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v bigint;
  v_last store.wallet_entries;
begin
  perform private.store_require_admin();
  v := private.store_shop_id();
  select * into v_last from store.wallet_entries e
  where e.customer_id = v and e.kind = 'shop_topup'
    and not exists (select 1 from store.wallet_entries x where x.reverses_id = e.id)
  order by e.id desc limit 1;

  return query
  with scopes(scope, t_from, t_to) as (values
    ('all', null::timestamptz, null::timestamptz),
    ('since_last', v_last.created_at, null::timestamptz),
    ('range', p_from::timestamptz, (p_to + 1)::timestamptz)
  )
  select s.scope,
    coalesce((select sum(e.d_balance) from store.wallet_entries e
              where e.customer_id = v and e.kind in ('shop_topup', 'shop_topup_refund')
                and (s.t_from is null or e.created_at >= s.t_from) and (s.t_to is null or e.created_at < s.t_to)), 0)::bigint,
    coalesce(sum(o.charged_amount), 0)::bigint,
    count(o.id),
    coalesce(sum(o.base_amount - o.charged_amount), 0)::bigint,
    coalesce(sum(o.base_amount - o.cost_amount) filter (where o.cost_amount is not null), 0)::bigint,
    count(o.id) filter (where o.cost_amount is null),
    (select c.balance from store.customers c where c.id = v),
    v_last.created_at,
    v_last.amount
  from scopes s
  left join store.orders o on o.customer_id = v and o.status = 'done'
    and (s.t_from is null or o.created_at >= s.t_from) and (s.t_to is null or o.created_at < s.t_to)
  group by s.scope, s.t_from, s.t_to
  order by array_position(array['all', 'since_last', 'range'], s.scope);
end;
$$;

-- ---------------------------------------------------------------------
-- Existing admin functions: hide the shop account from the customer
-- list, expose is_shop, add an optional scope filter (all/shop/customers)
-- ---------------------------------------------------------------------
create or replace function private.store_admin_customers_impl()
returns table (customer_id bigint, name text, phone text, active boolean, balance bigint, debt bigint,
               debt_limit bigint, self_topup boolean, locked_until timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select c.id, c.name, c.phone, c.active, c.balance, c.debt, c.debt_limit, c.self_topup, c.locked_until, c.created_at
  from store.customers c where not c.is_shop order by c.name;
end;
$$;

drop function public.store_admin_orders(bigint, text, date, date, text, int, int);
drop function private.store_admin_orders_impl(bigint, text, date, date, text, int, int);
create function private.store_admin_orders_impl(
  p_customer_id bigint, p_category text, p_from date, p_to date, p_query text, p_limit int, p_offset int, p_scope text default null)
returns table (order_id bigint, customer_id bigint, customer_name text, brand text, category text, product_name text, qty int,
               base_amount bigint, charged_amount bigint, cost_amount bigint, profit bigint, balance_after bigint, status text,
               created_at timestamptz, total_count bigint, is_shop boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select o.id, o.customer_id, c.name, b.name, b.category, p.name, o.qty, o.base_amount, o.charged_amount, o.cost_amount,
         case when c.is_shop then o.base_amount - o.cost_amount else o.charged_amount - o.cost_amount end,
         o.balance_after, o.status, o.created_at, count(*) over (), c.is_shop
  from store.orders o join store.customers c on c.id = o.customer_id
  join store.products p on p.id = o.product_id join store.brands b on b.id = p.brand_id
  where (p_customer_id is null or o.customer_id = p_customer_id)
    and (p_scope is null or p_scope = 'all' or (p_scope = 'shop') = c.is_shop)
    and (p_category is null or b.category = p_category)
    and (p_from is null or o.created_at >= p_from)
    and (p_to is null or o.created_at < p_to + 1)
    and (nullif(btrim(p_query), '') is null or p.name ilike '%' || btrim(p_query) || '%'
         or c.name ilike '%' || btrim(p_query) || '%' or o.id::text = btrim(p_query))
  order by o.created_at desc, o.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
create function public.store_admin_orders(
  p_customer_id bigint, p_category text, p_from date, p_to date, p_query text, p_limit int, p_offset int, p_scope text default null)
returns table (order_id bigint, customer_id bigint, customer_name text, brand text, category text, product_name text, qty int,
               base_amount bigint, charged_amount bigint, cost_amount bigint, profit bigint, balance_after bigint, status text,
               created_at timestamptz, total_count bigint, is_shop boolean)
language sql set search_path = '' as $$
  select * from private.store_admin_orders_impl(p_customer_id, p_category, p_from, p_to, p_query, p_limit, p_offset, p_scope);
$$;

drop function public.store_admin_entries(bigint, text, date, date, int, int);
drop function private.store_admin_entries_impl(bigint, text, date, date, int, int);
create function private.store_admin_entries_impl(
  p_customer_id bigint, p_kind text, p_from date, p_to date, p_limit int, p_offset int, p_scope text default null)
returns table (entry_id bigint, customer_id bigint, customer_name text, kind text, amount bigint, d_balance bigint, d_debt bigint,
               balance_after bigint, debt_after bigint, note text, order_id bigint, reversed boolean, reverses_id bigint,
               created_at timestamptz, total_count bigint, total_amount numeric, is_shop boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select e.id, e.customer_id, c.name, e.kind, e.amount, e.d_balance, e.d_debt, e.balance_after, e.debt_after, e.note,
         e.order_id, exists (select 1 from store.wallet_entries x where x.reverses_id = e.id), e.reverses_id, e.created_at,
         count(*) over (), sum(e.amount) over (), c.is_shop
  from store.wallet_entries e join store.customers c on c.id = e.customer_id
  where (p_customer_id is null or e.customer_id = p_customer_id)
    and (p_scope is null or p_scope = 'all' or (p_scope = 'shop') = c.is_shop)
    and (p_kind is null or (p_kind = 'refund' and e.kind like '%\_refund') or e.kind = p_kind)
    and (p_from is null or e.created_at >= p_from)
    and (p_to is null or e.created_at < p_to + 1)
  order by e.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
create function public.store_admin_entries(
  p_customer_id bigint, p_kind text, p_from date, p_to date, p_limit int, p_offset int, p_scope text default null)
returns table (entry_id bigint, customer_id bigint, customer_name text, kind text, amount bigint, d_balance bigint, d_debt bigint,
               balance_after bigint, debt_after bigint, note text, order_id bigint, reversed boolean, reverses_id bigint,
               created_at timestamptz, total_count bigint, total_amount numeric, is_shop boolean)
language sql set search_path = '' as $$
  select * from private.store_admin_entries_impl(p_customer_id, p_kind, p_from, p_to, p_limit, p_offset, p_scope);
$$;

-- The owner's own codes are shown in full; customers' codes stay masked (reveal is logged)
create or replace function private.store_admin_order_codes_impl(p_order_id bigint)
returns table (code_id bigint, masked_code text, serial text, status text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v_shop boolean;
begin
  perform private.store_require_admin();
  select c.is_shop into v_shop from store.orders o join store.customers c on c.id = o.customer_id where o.id = p_order_id;
  return query select k.id, case when v_shop then k.code else '****' || right(k.code, 4) end, k.serial, k.status
  from store.codes k where k.order_id = p_order_id order by k.id;
end;
$$;

-- Rate matrix: default row, then the shop row, then customers
create or replace function private.store_admin_rates_impl(p_category text)
returns table (customer_id bigint, customer_name text, product_id bigint, product_name text, base_price bigint, pct numeric)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  with prods as (
    select p.id, p.name, p.base_price, b.category, b.sort as bs, p.sort as ps
    from store.products p join store.brands b on b.id = p.brand_id
    where p_category is null or b.category = p_category),
  rows_ as (
    select 0 as grp, ''::text as nm, null::bigint as cid, 'افتراضي'::text as cname, pr.*, coalesce(d.pct, 0) as rate
    from prods pr left join store.default_rates d on d.product_id = pr.id
    union all
    select case when c.is_shop then 1 else 2 end, c.name, c.id, c.name, pr.*, coalesce(r.pct, 0)
    from store.customers c cross join prods pr
    left join store.customer_rates r on r.customer_id = c.id and r.product_id = pr.id)
  select x.cid, x.cname, x.id, x.name, x.base_price, x.rate
  from rows_ x order by x.grp, x.nm, x.category, x.bs, x.ps, x.base_price;
end;
$$;

-- Public wrappers for the shop API
create function public.store_admin_shop_catalog()
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int)
language sql set search_path = '' as $$ select * from private.store_admin_shop_catalog_impl(); $$;
create function public.store_admin_shop_buy(p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language sql set search_path = '' as $$ select * from private.store_admin_shop_buy_impl(p_product_id, p_qty, p_request_id); $$;
create function public.store_admin_shop_topup(p_amount bigint, p_note text, p_request_id uuid)
returns table (entry_id bigint, balance_after bigint)
language sql set search_path = '' as $$ select * from private.store_admin_shop_topup_impl(p_amount, p_note, p_request_id); $$;
create function public.store_admin_shop_summary(p_from date, p_to date)
returns table (scope text, topups bigint, consumed bigint, orders_count bigint, profit_pct bigint, real_profit bigint,
               unknown_cost_orders bigint, balance bigint, last_topup_at timestamptz, last_topup_amount bigint)
language sql set search_path = '' as $$ select * from private.store_admin_shop_summary_impl(p_from, p_to); $$;

-- ---------------------------------------------------------------------
-- Grants (same rule as v1): revoke everything on new/recreated functions, grant exactly
-- ---------------------------------------------------------------------
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
