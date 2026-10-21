-- =====================================================================
-- Card Store v1.3 — flexible pricing (owner decisions 2026-10-21)
--  * Purchase cost is mandatory for every new code batch.
--  * Each product has a default price rule; a customer may have his own.
--    The rule is whatever field the owner edited last:
--      fixed  : the customer pays exactly <value> per card
--      amount : cost of that code + <value> dinars
--      pct    : profit = <value>% OF THE AMOUNT PAID  →  pay = cost / (1 − value/100)
--    (910 bought, 9% → 1000; matches the owner's own wording)
--  * Customers without their own rule follow the default rule.
--  * «حساب المحل» pays the code's purchase cost; its profit = selling price − cost.
-- Additive only: old rate tables/functions stay but are no longer used for pricing.
-- =====================================================================

create table store.default_prices (
  product_id bigint primary key references store.products(id),
  mode text not null check (mode in ('fixed', 'amount', 'pct')),
  value numeric(12,2) not null,
  updated_at timestamptz not null default now(),
  check ((mode = 'fixed' and value > 0) or (mode = 'amount' and value >= 0) or (mode = 'pct' and value >= 0 and value < 100))
);

create table store.customer_prices (
  customer_id bigint not null references store.customers(id),
  product_id bigint not null references store.products(id),
  mode text not null check (mode in ('fixed', 'amount', 'pct', 'inherit')),
  value numeric(12,2),
  updated_at timestamptz not null default now(),
  primary key (customer_id, product_id),
  check ((mode = 'inherit') or (mode = 'fixed' and value > 0) or (mode = 'amount' and value >= 0) or (mode = 'pct' and value >= 0 and value < 100))
);
create index on store.customer_prices (product_id);

alter table store.default_prices enable row level security;
alter table store.customer_prices enable row level security;
revoke all on store.default_prices from public, anon, authenticated;
revoke all on store.customer_prices from public, anon, authenticated;

alter table store.orders add column price_mode text;
alter table store.orders add column price_value numeric(12,2);

-- Carry existing discount percentages over as fixed prices (base × (1 − pct))
insert into store.default_prices (product_id, mode, value)
select d.product_id, 'fixed', round(p.base_price * (1 - d.pct / 100))
from store.default_rates d join store.products p on p.id = d.product_id where d.pct > 0;

insert into store.customer_prices (customer_id, product_id, mode, value)
select r.customer_id, r.product_id, 'fixed', round(p.base_price * (1 - r.pct / 100))
from store.customer_rates r join store.products p on p.id = r.product_id
join store.customers c on c.id = r.customer_id
where r.pct > 0 and not c.is_shop;

-- ---------------------------------------------------------------------
-- Pricing helpers
-- ---------------------------------------------------------------------

-- The rule that applies to (customer, product): own rule → default rule → selling price
create function private.store_price_rule(p_customer bigint, p_product bigint, out mode text, out value numeric, out source text)
language plpgsql stable security definer set search_path = '' as $$
begin
  select cp.mode, cp.value, 'customer' into mode, value, source
  from store.customer_prices cp where cp.customer_id = p_customer and cp.product_id = p_product and cp.mode <> 'inherit';
  if found then return; end if;
  select dp.mode, dp.value, 'default' into mode, value, source
  from store.default_prices dp where dp.product_id = p_product;
  if found then return; end if;
  select 'fixed', p.base_price, 'base' into mode, value, source from store.products p where p.id = p_product;
end;
$$;

-- What one card costs the customer under a rule, given that card's purchase cost
create function private.store_unit_charge(p_mode text, p_value numeric, p_cost bigint) returns bigint
language plpgsql immutable set search_path = '' as $$
begin
  if p_mode = 'fixed' then return round(p_value); end if;
  if p_cost is null then raise exception 'COST_MISSING'; end if;
  if p_mode = 'amount' then return p_cost + round(p_value); end if;
  if p_mode = 'pct' then return round(p_cost / (1 - p_value / 100)); end if;
  raise exception 'INVALID_PRICE_RULE';
end;
$$;

-- Purchase cost of the next card that would be sold (oldest available; null if that code has no cost).
-- Out of stock → the latest known cost, so the editor still shows a figure.
create function private.store_current_cost(p_product bigint) returns bigint
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from store.codes k where k.product_id = p_product and k.status = 'available')
      then (select k.cost from store.codes k where k.product_id = p_product and k.status = 'available' order by k.id limit 1)
    else (select k.cost from store.codes k where k.product_id = p_product and k.cost is not null order by k.id desc limit 1)
  end;
$$;

-- ---------------------------------------------------------------------
-- Purchase: price each code from its own batch cost
-- ---------------------------------------------------------------------
create or replace function private.store_buy_core(p_customer bigint, p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  o store.orders;
  p record;
  c store.customers;
  v_mode text;
  v_value numeric;
  v_charged bigint := 0;
  v_ids bigint[];
  v_cost bigint;
  k record;
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

    select array_agg(id order by id) into v_ids from (
      select k2.id from store.codes k2
      where k2.product_id = p.id and k2.status = 'available'
      order by k2.id limit p_qty
      for update skip locked) s;
    if coalesce(array_length(v_ids, 1), 0) < p_qty then raise exception 'OUT_OF_STOCK'; end if;

    select case when bool_and(k3.cost is not null) then sum(k3.cost) end into v_cost
    from store.codes k3 where k3.id = any (v_ids);

    if c.is_shop then
      -- the owner's own account pays exactly what the cards cost him
      if v_cost is null then raise exception 'COST_MISSING'; end if;
      v_charged := v_cost;
      v_mode := 'cost';
    else
      select pr2.mode, pr2.value into v_mode, v_value from private.store_price_rule(p_customer, p.id) pr2;
      for k in select k4.cost from store.codes k4 where k4.id = any (v_ids) order by k4.id loop
        v_charged := v_charged + private.store_unit_charge(v_mode, v_value, k.cost);
      end loop;
    end if;
    if v_charged <= 0 then raise exception 'INVALID_PRICE_RULE'; end if;
    if c.balance < v_charged then raise exception 'INSUFFICIENT_BALANCE'; end if;

    insert into store.orders (customer_id, product_id, qty, base_amount, pct, charged_amount, cost_amount, balance_after,
                              request_id, price_mode, price_value)
    values (p_customer, p.id, p_qty, p.base_price * p_qty, 0, v_charged, v_cost, c.balance - v_charged,
            p_request_id, v_mode, v_value)
    returning * into o;
    update store.codes set status = 'sold', order_id = o.id, sold_at = now() where id = any (v_ids);
    perform private.store_post_entry(p_customer, 'purchase', v_charged, null, o.id, null, null, null);
  end if;

  return query
  select o.id, pr.name, o.qty,
         coalesce((select jsonb_agg(jsonb_build_object('code', k5.code, 'serial', k5.serial) order by k5.id)
                   from store.codes k5 where k5.order_id = o.id), '[]'::jsonb)
  from store.products pr where pr.id = o.product_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Cost is mandatory for new codes
-- ---------------------------------------------------------------------
create or replace function private.store_admin_add_codes_impl(p_product_id bigint, p_supplier_id bigint, p_cost bigint, p_lines text)
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
  if p_cost is null then raise exception 'COST_REQUIRED'; end if;
  if p_cost <= 0 then raise exception 'INVALID_COST'; end if;

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
  update store.code_batches set added = v_added, duplicates = v_total - v_added where id = v_batch;
  return query select b.id, b.added, b.duplicates from store.code_batches b where b.id = v_batch;
end;
$$;

-- ---------------------------------------------------------------------
-- Admin price editor
-- ---------------------------------------------------------------------
-- One row per (default | customer) × product of the category, with the rule in force and today's charge
create function private.store_admin_prices_impl(p_category text)
returns table (customer_id bigint, customer_name text, product_id bigint, product_name text, brand text,
               base_price bigint, current_cost bigint, mode text, value numeric, source text, charge_now bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  with prods as (
    select p.id, p.name, b.name as bname, p.base_price, private.store_current_cost(p.id) as cost, b.sort as bs, p.sort as ps
    from store.products p join store.brands b on b.id = p.brand_id
    where p_category is null or b.category = p_category),
  rows_ as (
    select 0 as grp, ''::text as nm, null::bigint as cid, 'افتراضي'::text as cname, pr.*,
           coalesce(dp.mode, 'fixed') as m, coalesce(dp.value, pr.base_price) as v,
           case when dp.mode is null then 'base' else 'default' end as src
    from prods pr left join store.default_prices dp on dp.product_id = pr.id
    union all
    select 1, c.name, c.id, c.name, pr.*, rule.mode, rule.value, rule.source
    from store.customers c cross join prods pr
    cross join lateral private.store_price_rule(c.id, pr.id) rule
    where not c.is_shop)
  select x.cid, x.cname, x.id, x.name, x.bname, x.base_price, x.cost, x.m, x.v, x.src,
         case when x.m = 'fixed' then round(x.v)::bigint
              when x.cost is null then null
              when x.m = 'amount' then x.cost + round(x.v)::bigint
              else round(x.cost / (1 - x.v / 100))::bigint end
  from rows_ x order by x.grp, x.nm, x.bs, x.ps, x.base_price;
end;
$$;

-- p_customer_id null = default rule. p_mode 'inherit' (customers only) = follow the default again.
create function private.store_admin_set_price_impl(p_customer_id bigint, p_product_id bigint, p_mode text, p_value numeric) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  if p_mode not in ('fixed', 'amount', 'pct', 'inherit') or (p_mode = 'inherit' and p_customer_id is null) then
    raise exception 'INVALID_PRICE_RULE';
  end if;
  if p_mode = 'fixed' and not (p_value > 0) then raise exception 'INVALID_PRICE_RULE'; end if;
  if p_mode = 'amount' and not (p_value >= 0) then raise exception 'INVALID_PRICE_RULE'; end if;
  if p_mode = 'pct' and not (p_value >= 0 and p_value < 100) then raise exception 'INVALID_PRICE_RULE'; end if;
  if p_customer_id is null then
    insert into store.default_prices (product_id, mode, value) values (p_product_id, p_mode, p_value)
    on conflict (product_id) do update set mode = excluded.mode, value = excluded.value, updated_at = now();
  else
    if exists (select 1 from store.customers c where c.id = p_customer_id and c.is_shop) then raise exception 'SHOP_PAYS_COST'; end if;
    insert into store.customer_prices (customer_id, product_id, mode, value)
    values (p_customer_id, p_product_id, p_mode, case when p_mode = 'inherit' then null else p_value end)
    on conflict (customer_id, product_id) do update set mode = excluded.mode, value = excluded.value, updated_at = now();
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Customer: what I pay now per card (replaces "my percentages")
-- ---------------------------------------------------------------------
create function private.store_my_prices_impl(p_token text)
returns table (product_id bigint, brand text, name text, base_price bigint, pay_now bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select p.id, b.name, p.name, p.base_price,
         case when rule.mode = 'fixed' then round(rule.value)::bigint
              when private.store_current_cost(p.id) is null then null
              when rule.mode = 'amount' then private.store_current_cost(p.id) + round(rule.value)::bigint
              else round(private.store_current_cost(p.id) / (1 - rule.value / 100))::bigint end
  from store.products p join store.brands b on b.id = p.brand_id
  cross join lateral private.store_price_rule(v, p.id) rule
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;

-- Public wrappers
create function public.store_admin_prices(p_category text)
returns table (customer_id bigint, customer_name text, product_id bigint, product_name text, brand text,
               base_price bigint, current_cost bigint, mode text, value numeric, source text, charge_now bigint)
language sql set search_path = '' as $$ select * from private.store_admin_prices_impl(p_category); $$;
create function public.store_admin_set_price(p_customer_id bigint, p_product_id bigint, p_mode text, p_value numeric) returns void
language sql set search_path = '' as $$ select private.store_admin_set_price_impl(p_customer_id, p_product_id, p_mode, p_value); $$;
create function public.store_my_prices(p_token text)
returns table (product_id bigint, brand text, name text, base_price bigint, pay_now bigint)
language sql set search_path = '' as $$ select * from private.store_my_prices_impl(p_token); $$;

-- Grants (same rule as before)
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
