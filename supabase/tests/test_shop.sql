-- Behavioural tests for v1.2 (shop account). Run after test_store.sql on the same database.
\set ON_ERROR_STOP on
\set QUIET on
create temp table s_results (name text, ok boolean, detail text);
grant all on s_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into s_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

select id as shop_id from store.customers where is_shop \gset
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);

-- product with costed codes; the shop always pays the purchase cost
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Djezzy'), 'Djezzy 1000', 1000, 1, true) as dj \gset
select added from public.store_admin_add_codes(:dj, null, 900, E'DJ-1\nDJ-2\nDJ-3\nDJ-4') \g /dev/null
select pg_temp.check('shop not in price editor', not exists (select 1 from public.store_admin_prices('phone') where customer_name = 'المحل ★'));
select pg_temp.check('no price rule for shop', pg_temp.err(format($$select public.store_admin_set_price(%s, %s, 'fixed', 950)$$,
  :shop_id, :dj)) like '%SHOP_PAYS_COST%');
select pg_temp.check('shop hidden from customers list', not exists (select 1 from public.store_admin_customers() where name = 'المحل ★'));

select pg_temp.check('buy without balance blocked', pg_temp.err($$select * from public.store_admin_shop_buy((select product_id from public.store_admin_shop_catalog() where name='Djezzy 1000'), 1, gen_random_uuid())$$) like '%INSUFFICIENT_BALANCE%');

select * from public.store_admin_shop_topup(5000, 'دفعة', '33333333-3333-3333-3333-333333333333') \gset t_
select * from public.store_admin_shop_topup(5000, 'دفعة', '33333333-3333-3333-3333-333333333333') \gset t2_
select pg_temp.check('topup idempotent', :t_entry_id = :t2_entry_id and :t2_balance_after = 5000);

select * from public.store_admin_shop_buy(:dj, 2, gen_random_uuid()) \gset b_
select pg_temp.check('shop buy returns full codes', jsonb_array_length(:'b_codes'::jsonb) = 2 and (:'b_codes'::jsonb->0->>'code') like 'DJ-%');

select * from public.store_admin_shop_summary(null, null) where scope = 'all' \gset a_
-- 2 × 1000 at cost 900 → consumed 1800, profit 2×(1000−900)=200
select pg_temp.check('summary all', :a_topups = 5000 and :a_consumed = 1800 and :a_profit_pct = 200 and :a_real_profit = 200 and :a_balance = 3200 and :a_orders_count = 1,
  :a_topups || '/' || :a_consumed || '/' || :a_profit_pct || '/' || :a_real_profit || '/' || :a_balance);

-- second top-up: since_last resets, all keeps totals
select public.store_admin_shop_topup(1000, null, gen_random_uuid()) \g /dev/null
select * from public.store_admin_shop_buy(:dj, 1, gen_random_uuid()) \g /dev/null
select * from public.store_admin_shop_summary(null, null) where scope = 'since_last' \gset l_
select pg_temp.check('since last top-up', :l_topups = 1000 and :l_consumed = 900 and :l_orders_count = 1 and :l_last_topup_amount = 1000,
  :l_topups || '/' || :l_consumed || '/' || :l_orders_count);
select * from public.store_admin_shop_summary(current_date, current_date) where scope = 'range' \gset r_
select pg_temp.check('range today', :r_topups = 6000 and :r_consumed = 2700);
select * from public.store_admin_shop_summary(current_date + 1, current_date + 1) where scope = 'range' \gset r2_
select pg_temp.check('range tomorrow empty', :r2_topups = 0 and :r2_consumed = 0);

select pg_temp.check('admin orders scope shop', (select bool_and(is_shop) and count(*) = 2 from public.store_admin_orders(null, null, null, null, null, 10, 0, 'shop')));
select pg_temp.check('admin orders scope customers', (select coalesce(bool_and(not is_shop), true) from public.store_admin_orders(null, null, null, null, null, 10, 0, 'customers')));
select pg_temp.check('old 7-arg call still works', (select count(*) >= 2 from public.store_admin_orders(null, null, null, null, null, 10, 0)));
select pg_temp.check('shop profit = selling − cost', (select profit from public.store_admin_orders(null, null, null, null, null, 1, 0, 'shop')) = 100);
select pg_temp.check('shop codes unmasked for admin',
  (select bool_and(masked_code not like '****%') from public.store_admin_order_codes((select order_id from public.store_admin_orders(null, null, null, null, null, 1, 0, 'shop')))));
select pg_temp.check('entries scope shop', (select bool_and(is_shop) from public.store_admin_entries(null, null, null, null, 50, 0, 'shop')));
select pg_temp.check('reverse shop topup',
  (select balance_after from public.store_admin_reverse((select entry_id from public.store_admin_entries(null, 'shop_topup', null, null, 1, 0, 'shop')), null, gen_random_uuid())) = 2300);
select pg_temp.check('reconcile clean', (select count(*) from public.store_admin_reconcile()) = 0);

-- customers cannot reach the shop API or log in as the shop
reset role;
set role anon;
select pg_temp.check('anon cannot call shop api', pg_temp.err($$select * from public.store_admin_shop_summary(null, null)$$) like '%permission denied%');
select pg_temp.check('shop cannot log in by phone', (select count(*) from public.store_login('', '')) = 0);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin blocked from shop', pg_temp.err($$select * from public.store_admin_shop_topup(1, null, gen_random_uuid())$$) like '%NOT_ADMIN%');
reset role;

\set QUIET off
select ok, count(*) from s_results group by ok;
select name, detail from s_results where not ok;
