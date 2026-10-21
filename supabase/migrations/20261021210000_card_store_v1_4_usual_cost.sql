-- =====================================================================
-- Card Store v1.4 — «سعر الشراء المعتاد» per card (owner decision 2026-10-21)
--  * The owner can type the usual purchase cost of a card before any codes
--    exist, so the price editor can compute profit right away.
--  * It pre-fills the cost field when adding codes; real sales still use the
--    cost of the batch each code came from.
--  * Current cost for the editor: next available code's cost → usual cost → last known cost.
--  * The price list also returns stopped cards (UI shows them in their own section).
-- Additive only (no drop), so earlier API calls keep working.
-- =====================================================================

alter table store.products add column default_cost bigint check (default_cost is null or default_cost > 0);

create or replace function private.store_current_cost(p_product bigint) returns bigint
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from store.codes k where k.product_id = p_product and k.status = 'available')
      then (select k.cost from store.codes k where k.product_id = p_product and k.status = 'available' order by k.id limit 1)
    else coalesce(
      (select p.default_cost from store.products p where p.id = p_product),
      (select k.cost from store.codes k where k.product_id = p_product and k.cost is not null order by k.id desc limit 1))
  end;
$$;

-- Where the editor's cost comes from: stock (next code to sell) | usual (typed by owner) | last (last batch) | null
create function private.store_cost_source(p_product bigint) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from store.codes k where k.product_id = p_product and k.status = 'available') then 'stock'
    when (select p.default_cost from store.products p where p.id = p_product) is not null then 'usual'
    when exists (select 1 from store.codes k where k.product_id = p_product and k.cost is not null) then 'last'
  end;
$$;

create function private.store_admin_set_default_cost_impl(p_product_id bigint, p_cost bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  if p_cost is not null and p_cost <= 0 then raise exception 'INVALID_COST'; end if;
  update store.products set default_cost = p_cost where id = p_product_id;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
end;
$$;

-- Price editor rows, including stopped cards (active = false)
create function private.store_admin_price_list_impl(p_category text)
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
              else round(x.cost / (1 - x.v / 100))::bigint end
  from rows_ x order by x.grp, x.nm, x.bs, x.ps, x.base_price;
end;
$$;

-- Usual cost per card (stock page pre-fills the code form with it)
create function private.store_admin_product_costs_impl()
returns table (product_id bigint, default_cost bigint, current_cost bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select p.id, p.default_cost, private.store_current_cost(p.id) from store.products p;
end;
$$;

create function public.store_admin_set_default_cost(p_product_id bigint, p_cost bigint) returns void
language sql set search_path = '' as $$ select private.store_admin_set_default_cost_impl(p_product_id, p_cost); $$;
create function public.store_admin_price_list(p_category text)
returns table (customer_id bigint, customer_name text, product_id bigint, product_name text, brand text, category text,
               active boolean, base_price bigint, default_cost bigint, current_cost bigint, cost_source text,
               mode text, value numeric, source text, charge_now bigint)
language sql set search_path = '' as $$ select * from private.store_admin_price_list_impl(p_category); $$;
create function public.store_admin_product_costs()
returns table (product_id bigint, default_cost bigint, current_cost bigint)
language sql set search_path = '' as $$ select * from private.store_admin_product_costs_impl(); $$;

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
