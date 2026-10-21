-- Behavioural tests for v1.3 (flexible pricing). Run after test_store.sql and test_shop.sql on the same database.
\set ON_ERROR_STOP on
\set QUIET on
create temp table p_results (name text, ok boolean, detail text);
grant all on p_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into p_results values (n, coalesce(cond, false), d);
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

-- Ooredoo 1000: two batches, 910 then 950
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Ooredoo'), 'Ooredoo 1000', 1000, 1, true) as oo \gset
select added from public.store_admin_add_codes(:oo, null, 910, E'OO-1\nOO-2') \g /dev/null
select added from public.store_admin_add_codes(:oo, null, 950, E'OO-3\nOO-4\nOO-5') \g /dev/null
select public.store_admin_create_customer('سمير', '0770000010', 'secret123') as c2 \gset
select * from public.store_admin_transfer(:c2, 'cash', 10000, null, gen_random_uuid()) \g /dev/null

select pg_temp.check('no rule → selling price', (select source = 'base' and charge_now = 1000 and current_cost = 910
  from public.store_admin_prices('phone') where customer_id is null and product_id = :oo));

-- default: 9% of the selling price → 910 + 90 = 1000
select public.store_admin_set_price(null, :oo, 'pct', 9);
select pg_temp.check('pct of selling price: 910 + 9% of 1000 → 1000', (select charge_now from public.store_admin_prices('phone') where customer_id = :c2 and product_id = :oo) = 1000);
-- customer override: cost + 30 DZD
select public.store_admin_set_price(:c2, :oo, 'amount', 30);
select pg_temp.check('customer amount rule', (select source = 'customer' and charge_now = 940 from public.store_admin_prices('phone') where customer_id = :c2 and product_id = :oo));
select public.store_admin_set_price(null, :oo, 'pct', 1);
select pg_temp.check('owner example: 910 + 1% of 1000 → 920', (select charge_now from public.store_admin_prices('phone') where customer_id is null and product_id = :oo) = 920);
select public.store_admin_set_price(null, :oo, 'pct', 9);
select pg_temp.check('bad pct rejected', pg_temp.err(format($$select public.store_admin_set_price(null, %s, 'pct', 100)$$, :oo)) like '%INVALID_PRICE_RULE%');
select pg_temp.check('bad fixed rejected', pg_temp.err(format($$select public.store_admin_set_price(null, %s, 'fixed', 0)$$, :oo)) like '%INVALID_PRICE_RULE%');
select pg_temp.check('inherit only for customers', pg_temp.err(format($$select public.store_admin_set_price(null, %s, 'inherit', null)$$, :oo)) like '%INVALID_PRICE_RULE%');

-- customer buys 3: OO-1, OO-2 at 910+30, OO-3 at 950+30 → 940+940+980 = 2860
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select session_token as tok from public.store_login('0770000010', 'secret123') \gset
select pg_temp.check('my prices: pay now 940', (select pay_now from public.store_my_prices(:'tok') where product_id = :oo) = 940);
select * from public.store_buy(:'tok', :oo, 3, gen_random_uuid()) \gset b_
select * from public.store_me(:'tok') \gset me_
select pg_temp.check('priced per code batch', :me_balance = 10000 - 2860, :me_balance::text);
select pg_temp.check('customer profit = selling − paid', (select profit from public.store_orders(:'tok', null, null, null, null, 1, 0)) = 3000 - 2860);

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('real profit on order', (select profit from public.store_admin_orders(:c2, null, null, null, null, 1, 0)) = 2860 - 2770);

-- back to the default rule; current cost is now 950 → 950 + 9% of 1000 = 1040
select public.store_admin_set_price(:c2, :oo, 'inherit', null);
select pg_temp.check('inherit → default again', (select source = 'default' and charge_now = 1040 from public.store_admin_prices('phone') where customer_id = :c2 and product_id = :oo));

reset role;
select pg_temp.check('order keeps the rule', (select price_mode = 'amount' and price_value = 30 from store.orders where id = :b_order_id));
-- legacy codes without cost (entered before v1.3)
insert into store.codes (product_id, batch_id, supplier_id, code, cost)
select :oo, b.id, b.supplier_id, 'LEGACY-1', null from store.code_batches b where b.product_id = :oo order by b.id limit 1;
update store.codes set status = 'void' where product_id = :oo and status = 'available';
update store.codes set status = 'available' where code = 'LEGACY-1';

set role anon;
select pg_temp.check('my prices: unknown when no cost', (select pay_now from public.store_my_prices(:'tok') where product_id = :oo) is null);
select pg_temp.check('pct rule needs cost', pg_temp.err(format($$select * from public.store_buy(%L, %s, 1, gen_random_uuid())$$, :'tok', :oo)) like '%COST_MISSING%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_set_price(:c2, :oo, 'fixed', 1000);
select pg_temp.check('shop cannot buy cost-less code', pg_temp.err(format($$select * from public.store_admin_shop_buy(%s, 1, gen_random_uuid())$$, :oo)) like '%COST_MISSING%');
reset role;
set role anon;
select * from public.store_buy(:'tok', :oo, 1, gen_random_uuid()) \gset l_
select pg_temp.check('fixed rule sells cost-less code', jsonb_array_length(:'l_codes'::jsonb) = 1);
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
-- v1.4 usual cost: used before any codes exist, stock cost wins once codes arrive
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Ooredoo'), 'Ooredoo 500', 500, 2, true) as o5 \gset
select pg_temp.check('no cost yet', (select current_cost is null and cost_source is null from public.store_admin_price_list('phone') where customer_id is null and product_id = :o5));
select public.store_admin_set_default_cost(:o5, 470);
select public.store_admin_set_price(null, :o5, 'amount', 10);
select pg_temp.check('usual cost drives the editor', (select current_cost = 470 and cost_source = 'usual' and charge_now = 480 and default_cost = 470
  from public.store_admin_price_list('phone') where customer_id is null and product_id = :o5));
select pg_temp.check('product costs list', (select default_cost = 470 from public.store_admin_product_costs() where product_id = :o5));
select added from public.store_admin_add_codes(:o5, null, 465, 'O5-1') \g /dev/null
select pg_temp.check('stock cost wins', (select current_cost = 465 and cost_source = 'stock' and charge_now = 475 from public.store_admin_price_list('phone') where customer_id is null and product_id = :o5));
select pg_temp.check('bad usual cost', pg_temp.err(format($$select public.store_admin_set_default_cost(%s, 0)$$, :o5)) like '%INVALID_COST%');
select public.store_admin_save_product(:o5, null, null, null, null, false) \g /dev/null
select pg_temp.check('stopped card listed as inactive', (select not active from public.store_admin_price_list('phone') where customer_id is null and product_id = :o5));
select pg_temp.check('old price list hides stopped', not exists (select 1 from public.store_admin_prices('phone') where product_id = :o5));
select public.store_admin_set_default_cost(:o5, null);
select pg_temp.check('reconcile clean', (select count(*) from public.store_admin_reconcile()) = 0);
reset role;

\set QUIET off
select ok, count(*) from p_results group by ok;
select name, detail from p_results where not ok;
