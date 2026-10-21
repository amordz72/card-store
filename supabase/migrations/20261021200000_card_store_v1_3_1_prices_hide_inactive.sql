-- v1.3.1: the price editor lists only active cards (stopped cards stay hidden until re-activated)
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
              else round(x.cost / (1 - x.v / 100))::bigint end
  from rows_ x order by x.grp, x.nm, x.bs, x.ps, x.base_price;
end;
$$;
