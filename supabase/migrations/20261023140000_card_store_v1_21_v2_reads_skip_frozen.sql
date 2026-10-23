-- v1.21 — fix: the v1.19 *_v2 reads counted frozen codes as available.
-- v1.10 excludes frozen codes from sale (store_buy_core) and from the old catalog/stock counts;
-- the v2 copies lost that condition, so a card with only frozen codes showed «متوفر» but could not be bought.
-- Same signatures (create or replace): no DROP, grants kept.

create or replace function private.store_catalog_v2_core()
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int,
               image text, brand_image text)
language sql stable security definer set search_path = '' as $$
  select p.id, b.name, b.category, p.name, p.base_price,
         exists (select 1 from store.codes k where k.product_id = p.id and k.status = 'available' and not k.frozen),
         b.sort, p.sort, p.image, b.image
  from store.products p join store.brands b on b.id = p.brand_id
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
$$;

create or replace function private.store_admin_stock_v2_impl()
returns table (product_id bigint, brand_id bigint, brand text, category text, name text, base_price bigint, active boolean,
               brand_active boolean, available bigint, sold bigint, voided bigint, sort int, image text, brand_image text)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query
  select p.id, b.id, b.name, b.category, p.name, p.base_price, p.active, b.active,
         count(k.id) filter (where k.status = 'available' and not k.frozen),
         count(k.id) filter (where k.status = 'sold'),
         count(k.id) filter (where k.status = 'void'), p.sort, p.image, b.image
  from store.products p join store.brands b on b.id = p.brand_id
  left join store.codes k on k.product_id = p.id
  group by p.id, b.id
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;
