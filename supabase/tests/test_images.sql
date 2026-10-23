-- Behavioural tests for v1.19 (brand/product images). Run after all migrations and test_store.sql / test_shop.sql.
\set ON_ERROR_STOP on
\set QUIET on
create temp table i_results (name text, ok boolean, detail text);
grant all on i_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into i_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);

select pg_temp.check('seeded brand logos', (select count(*) from public.store_admin_brands_v2() where image like 'brands/%.png') = 7);
select pg_temp.check('mobilis logo path', (select image from public.store_admin_brands_v2() where name = 'Mobilis') = 'brands/mobilis.png');

select product_id as pid from public.store_admin_stock_v2() where name = 'Djezzy 1000' \gset
select pg_temp.check('stock returns brand image', (select brand_image from public.store_admin_stock_v2() where product_id = :pid) = 'brands/djezzy.png');
select pg_temp.check('product image empty at first', (select image from public.store_admin_stock_v2() where product_id = :pid) is null);

\set url 'https://wqyebqzbbpohbnznqdjj.supabase.co/storage/v1/object/public/store-images/p/1-abc.webp'
select public.store_admin_set_image('product', :pid, :'url');
select pg_temp.check('product image saved', (select image from public.store_admin_stock_v2() where product_id = :pid) = :'url');
select pg_temp.check('shop catalog has both images',
  (select image = :'url' and brand_image = 'brands/djezzy.png' from public.store_admin_shop_catalog_v2() where product_id = :pid));

select pg_temp.check('foreign url rejected', pg_temp.err(format($$select public.store_admin_set_image('product', %s, 'https://evil.example/x.png')$$, :pid)) like '%INVALID_IMAGE%');
select pg_temp.check('other bucket rejected', pg_temp.err(format($$select public.store_admin_set_image('product', %s,
  'https://wqyebqzbbpohbnznqdjj.supabase.co/storage/v1/object/public/other/x.png')$$, :pid)) like '%INVALID_IMAGE%');
select pg_temp.check('bad kind rejected', pg_temp.err(format($$select public.store_admin_set_image('x', %s, null)$$, :pid)) like '%INVALID_IMAGE%');
select pg_temp.check('missing brand', pg_temp.err($$select public.store_admin_set_image('brand', -1, null)$$) like '%BRAND_NOT_FOUND%');
select pg_temp.check('missing product', pg_temp.err($$select public.store_admin_set_image('product', -1, null)$$) like '%PRODUCT_NOT_FOUND%');

select public.store_admin_set_image('brand', (select brand_id from public.store_admin_brands_v2() where name = 'Djezzy'), :'url');
select pg_temp.check('brand image changed', (select image from public.store_admin_brands_v2() where name = 'Djezzy') = :'url');
select public.store_admin_set_image('product', :pid, null);
select pg_temp.check('product image removed', (select image from public.store_admin_stock_v2() where product_id = :pid) is null);

-- v1.21: frozen codes are not available (same as the old reads and the sale itself)
select public.store_admin_codes_freeze(array(select code_id from public.store_admin_batch_codes(
  (select batch_id from public.store_admin_batches(:pid, 100, 0) limit 1)) where status = 'available'), true) \g /dev/null
select pg_temp.check('v2 stock skips frozen', (select a.available = s.available from public.store_admin_stock_v2() a
  join public.store_admin_stock() s using (product_id) where a.product_id = :pid));
select pg_temp.check('v2 catalog matches old catalog', (select bool_and(v.available = o.available) from public.store_admin_shop_catalog_v2() v
  join public.store_admin_shop_catalog() o using (product_id)));
select public.store_admin_codes_freeze(array(select code_id from public.store_admin_batch_codes(
  (select batch_id from public.store_admin_batches(:pid, 100, 0) limit 1)) where status = 'available'), false) \g /dev/null

reset role;
set role anon;
select pg_temp.check('customer catalog v2 reachable (token checked)', pg_temp.err($$select * from public.store_catalog_v2('bad')$$) like '%INVALID_SESSION%');
select pg_temp.check('anon cannot read admin stock v2', pg_temp.err($$select * from public.store_admin_stock_v2()$$) like '%permission denied%');
select pg_temp.check('anon cannot set image', pg_temp.err(format($$select public.store_admin_set_image('product', %s, null)$$, :pid)) like '%permission denied%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin blocked', pg_temp.err(format($$select public.store_admin_set_image('product', %s, null)$$, :pid)) like '%NOT_ADMIN%');
reset role;

\set QUIET off
select ok, count(*) from i_results group by ok;
select name, detail from i_results where not ok;
