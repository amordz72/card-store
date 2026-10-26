-- Behavioural tests for v1.37 (one operations list: cards and Flexy). Run after test_store, test_shop and test_shop_flexy.
\set ON_ERROR_STOP on
\set QUIET on
create temp table o_results (name text, ok boolean, detail text);
grant all on o_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into o_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- what the tables hold, read as the owner of the database
select count(*) as n_orders from store.orders \gset
select count(*) as n_jobs from store.flexy_jobs \gset
select count(*) as n_offers from store.flexy_jobs where kind = 'offer' \gset
select count(*) as n_shop_orders from store.orders o join store.customers c on c.id = o.customer_id where c.is_shop \gset
select j.customer_id as fcu, count(*) as fcu_jobs from store.flexy_jobs j group by j.customer_id order by count(*) desc limit 1 \gset
select count(*) as fcu_orders from store.orders where customer_id = :fcu \gset
select j.id as jid, j.phone as jphone, e.balance_after as jbal from store.flexy_jobs j join store.wallet_entries e on e.id = j.entry_id
  order by j.id limit 1 \gset
select pg_temp.check('fixture: there are cards and Flexy jobs', :n_orders > 0 and :n_jobs > 0 and :n_offers > 0);

-- ===== owner =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('all: cards and Flexy together', (select count(*) = :n_orders + :n_jobs and max(total_count) = :n_orders + :n_jobs
  from public.store_admin_ops(null, null, null, null, null, null, 100, 0)));
select pg_temp.check('newest first', (select bool_and(ok) from (select created_at >= lead(created_at) over (order by created_at desc, op_id desc) is not false as ok
  from public.store_admin_ops(null, null, null, null, null, null, 100, 0)) x));
select pg_temp.check('type flexy: 630 only', (select count(*) = :n_jobs - :n_offers and bool_and(source = 'flexy' and category = 'flexy' and product_name = 'فليكسي')
  from public.store_admin_ops(null, null, 'flexy', null, null, null, 100, 0)));
select pg_temp.check('type offer: offers only, by name', (select count(*) = :n_offers and bool_and(source = 'flexy' and category = 'offer' and product_name = offer_label)
  from public.store_admin_ops(null, null, 'offer', null, null, null, 100, 0)));
select pg_temp.check('type phone: cards of that category only', (select bool_and(source = 'card' and category = 'phone')
  from public.store_admin_ops(null, null, 'phone', null, null, null, 100, 0)));
select pg_temp.check('scope shop: the shop account only', (select count(*) = :n_shop_orders and coalesce(bool_and(is_shop), true)
  from public.store_admin_ops('shop', null, null, null, null, null, 100, 0)));
select pg_temp.check('scope customers: no shop row', (select count(*) = :n_orders + :n_jobs - :n_shop_orders and not bool_or(is_shop)
  from public.store_admin_ops('customers', null, null, null, null, null, 100, 0)));
select pg_temp.check('one customer', (select count(*) = :fcu_orders + :fcu_jobs and bool_and(customer_id = :fcu)
  from public.store_admin_ops(null, :fcu, null, null, null, null, 100, 0)));
select pg_temp.check('Flexy row: phone, amount and the wallet balance after', (select phone = :'jphone' and balance_after = :jbal and charged_amount > 0
  from public.store_admin_ops(null, null, null, null, null, null, 100, 0) where source = 'flexy' and op_id = :jid));
select pg_temp.check('search by phone', (select count(*) >= 1 and bool_and(phone = :'jphone')
  from public.store_admin_ops(null, null, null, null, null, :'jphone', 100, 0)));
select pg_temp.check('dates: tomorrow is empty', (select count(*) = 0
  from public.store_admin_ops(null, null, null, current_date + 1, null, null, 100, 0)));
select pg_temp.check('dates: today has all', (select count(*) = :n_orders + :n_jobs
  from public.store_admin_ops(null, null, null, current_date, current_date, null, 100, 0)));
select pg_temp.check('paged: offset and limit', (select count(*) = 2 from public.store_admin_ops(null, null, null, null, null, null, 2, 1)));
reset role;

-- ===== the customer =====
select set_config('request.jwt.claim.sub', '', false);
select c.phone as fphone from store.customers c where c.id = :fcu \gset
set role anon;
select pg_temp.check('anon cannot read the owner list', pg_temp.err('select * from public.store_admin_ops(null, null, null, null, null, null, 10, 0)') like 'permission denied%');
select session_token as ftok from public.store_login(:'fphone', 'secret123') \gset
select pg_temp.check('customer: own cards and Flexy only', (select count(*) = :fcu_orders + :fcu_jobs and max(total_count) = :fcu_orders + :fcu_jobs
  from public.store_ops(:'ftok', null, null, null, null, 100, 0)));
select pg_temp.check('customer: type offer', (select count(*) = (select count(*) from public.store_ops(:'ftok', null, null, null, null, 100, 0) where category = 'offer')
  from public.store_ops(:'ftok', 'offer', null, null, null, 100, 0)));
select pg_temp.check('customer: a bad session is refused', pg_temp.err('select * from public.store_ops(''nope'', null, null, null, null, 10, 0)') <> 'NO_ERROR');
reset role;

-- ===== v1.38: the keys of shop Flexy rows, owner only =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('keys: the owner reads a job''s core key', (select count(*) = 1 and bool_and(core_key like 'cs\_%')
  from public.store_admin_flexy_keys(array[:jid]::bigint[])));
select pg_temp.check('keys: none for no ids', (select count(*) = 0 from public.store_admin_flexy_keys('{}')));
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select pg_temp.check('keys: anon refused', pg_temp.err('select * from public.store_admin_flexy_keys(array[1]::bigint[])') like 'permission denied%');
reset role;
select name, detail from o_results where not ok;
select ok, count(*) from o_results group by ok;
