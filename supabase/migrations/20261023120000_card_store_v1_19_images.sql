-- v1.19 — صور العلامات والبطاقات (owner decision 2026-10-23)
-- Brand logo + optional per-product image. The admin uploads from «المخزن»;
-- the first brand logos ship inside the app (public/brands/*.png).
-- No image = the store shows the coloured tile exactly as before.

-- An image is either a logo shipped with the app, or a file in this project's public bucket.
alter table store.brands add column image text
  check (image is null or image ~ '^brands/[a-z0-9-]+\.png$'
         or image ~ '^https://wqyebqzbbpohbnznqdjj\.supabase\.co/storage/v1/object/public/store-images/[A-Za-z0-9/_.-]+$');
alter table store.products add column image text
  check (image is null or image ~ '^brands/[a-z0-9-]+\.png$'
         or image ~ '^https://wqyebqzbbpohbnznqdjj\.supabase\.co/storage/v1/object/public/store-images/[A-Za-z0-9/_.-]+$');

update store.brands set image = 'brands/' || x.file || '.png'
from (values ('Mobilis', 'mobilis'), ('Djezzy', 'djezzy'), ('Ooredoo', 'ooredoo'), ('Idoom ADSL', 'idoom-adsl'),
             ('Idoom 4G', 'idoom-4g'), ('Free Fire', 'free-fire'), ('PUBG', 'pubg')) x(name, file)
where store.brands.name = x.name and store.brands.image is null;

-- ---------------------------------------------------------------------
-- Catalog / stock / brands now return the images (return type changes → drop and recreate)
-- ---------------------------------------------------------------------
drop function public.store_catalog(text);
drop function public.store_admin_shop_catalog();
drop function private.store_catalog_impl(text);
drop function private.store_admin_shop_catalog_impl();
drop function private.store_catalog_core();
drop function public.store_admin_stock();
drop function private.store_admin_stock_impl();
drop function public.store_admin_brands();
drop function private.store_admin_brands_impl();

create function private.store_catalog_core()
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int,
               image text, brand_image text)
language sql stable security definer set search_path = '' as $$
  select p.id, b.name, b.category, p.name, p.base_price,
         exists (select 1 from store.codes k where k.product_id = p.id and k.status = 'available'),
         b.sort, p.sort, p.image, b.image
  from store.products p join store.brands b on b.id = p.brand_id
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
$$;

create function private.store_catalog_impl(p_token text)
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int,
               image text, brand_image text)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_session_customer(p_token);
  return query select * from private.store_catalog_core();
end;
$$;

create function private.store_admin_shop_catalog_impl()
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int,
               image text, brand_image text)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select * from private.store_catalog_core();
end;
$$;

create function private.store_admin_stock_impl()
returns table (product_id bigint, brand_id bigint, brand text, category text, name text, base_price bigint, active boolean,
               brand_active boolean, available bigint, sold bigint, voided bigint, sort int, image text, brand_image text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select p.id, b.id, b.name, b.category, p.name, p.base_price, p.active, b.active,
         count(k.id) filter (where k.status = 'available'),
         count(k.id) filter (where k.status = 'sold'),
         count(k.id) filter (where k.status = 'void'), p.sort, p.image, b.image
  from store.products p join store.brands b on b.id = p.brand_id
  left join store.codes k on k.product_id = p.id
  group by p.id, b.id
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;

create function private.store_admin_brands_impl()
returns table (brand_id bigint, name text, category text, sort int, active boolean, image text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select b.id, b.name, b.category, b.sort, b.active, b.image from store.brands b order by b.category, b.sort;
end;
$$;

-- p_kind: 'brand' | 'product'; p_image null removes the image
create function private.store_admin_set_image_impl(p_kind text, p_id bigint, p_image text) returns void
language plpgsql security definer set search_path = '' as $$
declare v bigint;
begin
  perform private.store_require_admin();
  if p_kind = 'brand' then
    update store.brands set image = nullif(btrim(p_image), '') where id = p_id returning id into v;
    if v is null then raise exception 'BRAND_NOT_FOUND'; end if;
  elsif p_kind = 'product' then
    update store.products set image = nullif(btrim(p_image), '') where id = p_id returning id into v;
    if v is null then raise exception 'PRODUCT_NOT_FOUND'; end if;
  else
    raise exception 'INVALID_IMAGE';
  end if;
exception when check_violation then
  raise exception 'INVALID_IMAGE';
end;
$$;

create function public.store_catalog(p_token text)
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int,
               image text, brand_image text)
language sql set search_path = '' as $$ select * from private.store_catalog_impl(p_token); $$;
create function public.store_admin_shop_catalog()
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int,
               image text, brand_image text)
language sql set search_path = '' as $$ select * from private.store_admin_shop_catalog_impl(); $$;
create function public.store_admin_stock()
returns table (product_id bigint, brand_id bigint, brand text, category text, name text, base_price bigint, active boolean,
               brand_active boolean, available bigint, sold bigint, voided bigint, sort int, image text, brand_image text)
language sql set search_path = '' as $$ select * from private.store_admin_stock_impl(); $$;
create function public.store_admin_brands()
returns table (brand_id bigint, name text, category text, sort int, active boolean, image text)
language sql set search_path = '' as $$ select * from private.store_admin_brands_impl(); $$;
create function public.store_admin_set_image(p_kind text, p_id bigint, p_image text) returns void
language sql set search_path = '' as $$ select private.store_admin_set_image_impl(p_kind, p_id, p_image); $$;

-- ---------------------------------------------------------------------
-- Grants (same rule as v1) for the recreated/new functions only
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_catalog_core', 'store_catalog_impl', 'store_catalog', 'store_admin_shop_catalog_impl',
                        'store_admin_shop_catalog', 'store_admin_stock_impl', 'store_admin_stock', 'store_admin_brands_impl',
                        'store_admin_brands', 'store_admin_set_image_impl', 'store_admin_set_image')
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

-- ---------------------------------------------------------------------
-- Storage: public bucket «store-images». Anyone reads; only store admins write.
-- (skipped on a local test database without Supabase Storage)
-- ---------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.buckets') is null then return; end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('store-images', 'store-images', true, 1048576, array['image/png', 'image/jpeg', 'image/webp'])
  on conflict (id) do nothing;
  create policy store_images_admin_select on storage.objects for select to authenticated
    using (bucket_id = 'store-images' and public.store_admin_is_admin());
  create policy store_images_admin_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'store-images' and public.store_admin_is_admin());
  create policy store_images_admin_update on storage.objects for update to authenticated
    using (bucket_id = 'store-images' and public.store_admin_is_admin());
  create policy store_images_admin_delete on storage.objects for delete to authenticated
    using (bucket_id = 'store-images' and public.store_admin_is_admin());
end $$;
