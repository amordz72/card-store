-- =====================================================================
-- Card Store v1.18 — «ربح الزبون من الربح»: proportional profit share (owner decision 2026-10-23, option ج)
--   share rule: value = the CUSTOMER's % of the whole margin (selling price − cost); the owner keeps the rest
--   customer profit = round(margin × value / 100), owner profit = margin − customer profit (what remains)
--   pay = cost + owner profit, margin = selling price − cost
--   A dearer batch lowers both profits together. e.g. Idoom 1000, customer 50%: cost 960 → 980, cost 970 → 985.
--   No margin (cost ≥ selling price) → the customer pays the cost.
-- Additive: fixed / amount / pct keep working exactly as before.
-- =====================================================================

alter table store.default_prices drop constraint default_prices_mode_check;
alter table store.default_prices drop constraint default_prices_check;
alter table store.default_prices add constraint default_prices_mode_check check (mode in ('fixed', 'amount', 'pct', 'share'));
alter table store.default_prices add constraint default_prices_check
  check ((mode = 'fixed' and value > 0) or (mode = 'amount' and value >= 0) or (mode = 'pct' and value >= 0 and value < 100)
         or (mode = 'share' and value >= 0 and value <= 100));

alter table store.customer_prices drop constraint customer_prices_mode_check;
alter table store.customer_prices drop constraint customer_prices_check;
alter table store.customer_prices add constraint customer_prices_mode_check check (mode in ('fixed', 'amount', 'pct', 'share', 'inherit'));
alter table store.customer_prices add constraint customer_prices_check
  check ((mode = 'inherit') or (mode = 'fixed' and value > 0) or (mode = 'amount' and value >= 0) or (mode = 'pct' and value >= 0 and value < 100)
         or (mode = 'share' and value >= 0 and value <= 100));

-- Used by purchases (store_buy_core)
create or replace function private.store_unit_charge(p_mode text, p_value numeric, p_cost bigint, p_base bigint) returns bigint
language plpgsql immutable set search_path = '' as $$
begin
  if p_mode = 'fixed' then return round(p_value); end if;
  if p_cost is null then raise exception 'COST_MISSING'; end if;
  if p_mode = 'amount' then return p_cost + round(p_value); end if;
  if p_mode = 'pct' then return p_cost + round(p_base * p_value / 100); end if;
  if p_mode = 'share' then
    return p_cost + greatest(p_base - p_cost, 0) - round(greatest(p_base - p_cost, 0) * p_value / 100);
  end if;
  raise exception 'INVALID_PRICE_RULE';
end;
$$;

-- Same as store_unit_charge for the price lists: null instead of an error when the cost is unknown
create function private.store_charge_now(p_mode text, p_value numeric, p_cost bigint, p_base bigint) returns bigint
language sql immutable set search_path = '' as $$
  select case when p_mode <> 'fixed' and p_cost is null then null
              else private.store_unit_charge(p_mode, p_value, p_cost, p_base) end;
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
         private.store_charge_now(x.m, x.v, x.cost, x.base_price)
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
         private.store_charge_now(x.m, x.v, x.cost, x.base_price)
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
         private.store_charge_now(rule.mode, rule.value, private.store_current_cost(p.id), p.base_price)
  from store.products p join store.brands b on b.id = p.brand_id
  cross join lateral private.store_price_rule(v, p.id) rule
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;


create or replace function private.store_admin_set_price_impl(p_customer_id bigint, p_product_id bigint, p_mode text, p_value numeric) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  if p_mode not in ('fixed', 'amount', 'pct', 'share', 'inherit') or (p_mode = 'inherit' and p_customer_id is null) then
    raise exception 'INVALID_PRICE_RULE';
  end if;
  if p_mode = 'fixed' and not (p_value > 0) then raise exception 'INVALID_PRICE_RULE'; end if;
  if p_mode = 'amount' and not (p_value >= 0) then raise exception 'INVALID_PRICE_RULE'; end if;
  if p_mode = 'pct' and not (p_value >= 0 and p_value < 100) then raise exception 'INVALID_PRICE_RULE'; end if;
  if p_mode = 'share' and not (p_value >= 0 and p_value <= 100) then raise exception 'INVALID_PRICE_RULE'; end if;
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

-- Grants: create or replace keeps every existing grant; only the new internal helper needs locking down
-- (it is called from security-definer functions, never by clients)
revoke all on function private.store_charge_now(text, numeric, bigint, bigint) from public, anon, authenticated;
