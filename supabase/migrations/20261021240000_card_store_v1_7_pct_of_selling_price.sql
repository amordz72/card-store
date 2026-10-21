-- =====================================================================
-- Card Store v1.7 — profit % is a share of the SELLING price (owner decision 2026-10-21)
--   pct rule: pay = cost + selling price × p / 100
--   e.g. Mobilis 1000, cost 910, 1% → 910 + 10 = 920  (before: 10/920 = 1.09%)
--   The owner's first example still holds: cost 910, 9% of 1000 → 1000.
-- No stored rule uses 'pct' at the time of writing, so no customer price changes.
-- New 4-argument store_unit_charge; the old 3-argument one is no longer called.
-- =====================================================================

create function private.store_unit_charge(p_mode text, p_value numeric, p_cost bigint, p_base bigint) returns bigint
language plpgsql immutable set search_path = '' as $$
begin
  if p_mode = 'fixed' then return round(p_value); end if;
  if p_cost is null then raise exception 'COST_MISSING'; end if;
  if p_mode = 'amount' then return p_cost + round(p_value); end if;
  if p_mode = 'pct' then return p_cost + round(p_base * p_value / 100); end if;
  raise exception 'INVALID_PRICE_RULE';
end;
$$;

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
        v_charged := v_charged + private.store_unit_charge(v_mode, v_value, k.cost, p.base_price);
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

create or replace function private.store_admin_prices_impl(p_category text)
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
    where (p_category is null or b.category = p_category) and p.active and b.active),
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
              else x.cost + round(x.base_price * x.v / 100)::bigint end
  from rows_ x order by x.grp, x.nm, x.bs, x.ps, x.base_price;
end;
$$;

create or replace function private.store_admin_price_list_impl(p_category text)
returns table (customer_id bigint, customer_name text, product_id bigint, product_name text, brand text, category text,
               active boolean, base_price bigint, default_cost bigint, current_cost bigint, cost_source text,
               mode text, value numeric, source text, charge_now bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  with prods as (
    select p.id, p.name, b.name as bname, b.category as bcat, (p.active and b.active) as act, p.base_price, p.default_cost as dcost,
           private.store_current_cost(p.id) as cost, private.store_cost_source(p.id) as csrc, b.sort as bs, p.sort as ps
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
  select x.cid, x.cname, x.id, x.name, x.bname, x.bcat, x.act, x.base_price, x.dcost, x.cost, x.csrc, x.m, x.v, x.src,
         case when x.m = 'fixed' then round(x.v)::bigint
              when x.cost is null then null
              when x.m = 'amount' then x.cost + round(x.v)::bigint
              else x.cost + round(x.base_price * x.v / 100)::bigint end
  from rows_ x order by x.grp, x.nm, x.bs, x.ps, x.base_price;
end;
$$;

create or replace function private.store_my_prices_impl(p_token text)
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
              else private.store_current_cost(p.id) + round(p.base_price * rule.value / 100)::bigint end
  from store.products p join store.brands b on b.id = p.brand_id
  cross join lateral private.store_price_rule(v, p.id) rule
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;

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
