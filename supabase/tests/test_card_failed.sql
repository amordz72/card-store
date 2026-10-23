-- Behavioural tests for v1.29 («لم تعمل» on one shop card). Run after all migrations and the other tests.
\set ON_ERROR_STOP on
\set QUIET on
create temp table f_results (name text, ok boolean, detail text);
grant all on f_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into f_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== owner: product (base 1000, cost 910), shop buys 5, a customer buys 1 =====
select id as shop_id from store.customers where is_shop \gset
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Mobilis'), 'Mobilis failed test', 1000, 9, true) as fp \gset
select public.store_admin_set_price(null, :fp, 'fixed', 980);
select added from public.store_admin_add_codes(:fp, null, 910, E'FL-1\nFL-2\nFL-3\nFL-4\nFL-5\nFL-6\nFL-7') \g /dev/null
select public.store_admin_create_customer('زبون فحص', '0770999301', 'secret123') as fc \gset
select entry_id from public.store_admin_transfer(:fc, 'cash', 5000, null, gen_random_uuid()) \g /dev/null
select entry_id from public.store_admin_shop_topup(10000, null, gen_random_uuid()) \g /dev/null
select order_id as sord from public.store_admin_shop_buy(:fp, 5, gen_random_uuid()) \gset
select min(code_id) as k1, max(code_id) as k5 from public.store_admin_order_codes(:sord) \gset
select (select code_id from public.store_admin_order_codes(:sord) order by code_id offset 1 limit 1) as k2 \gset
select consumed as cons0, real_profit as prof0, balance as bal0 from public.store_admin_shop_summary(null, null) where scope = 'all' \gset
reset role;
set role anon;
select session_token as tok from public.store_login('0770999301', 'secret123') \gset
select order_id as cord from public.store_buy(:'tok', :fp, 1, gen_random_uuid()) \gset
select code_id as ck from public.store_order_codes_v2(:'tok', :cord) \gset
reset role;

-- ===== the last shop card did not work =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('bad reason', pg_temp.err(format($$select * from public.store_admin_card_failed(%s, 'x', null, gen_random_uuid())$$, :k5)) like '%INVALID_REASON%');
select pg_temp.check('request id required', pg_temp.err(format($$select * from public.store_admin_card_failed(%s, 'used', null, null)$$, :k5)) like '%REQUEST_ID_REQUIRED%');
select * from public.store_admin_card_failed(:k5, 'used', 'The card you entered is used.', '55555555-5555-5555-5555-555555555555') \gset f_
select pg_temp.check('910 back to shop', :f_balance_after = :bal0 + 910, :'f_balance_after');
select * from public.store_admin_card_failed(:k5, 'used', null, '55555555-5555-5555-5555-555555555555') \gset f2_
select pg_temp.check('same request id = same refund', :f2_entry_id = :f_entry_id and :f2_balance_after = :f_balance_after);
select pg_temp.check('second report on same card', pg_temp.err(format($$select * from public.store_admin_card_failed(%s, 'used', null, gen_random_uuid())$$, :k5)) like '%ALREADY_REPORTED%');
select pg_temp.check('card void with reason', (select status = 'void' from public.store_admin_order_codes(:sord) where code_id = :k5));
select pg_temp.check('other 4 still sold', (select count(*) = 4 from public.store_admin_order_codes(:sord) where status = 'sold'));
select pg_temp.check('order stays done', exists (select 1 from public.store_admin_orders(null, null, null, null, null, 50, 0, 'shop') where order_id = :sord and status = 'done'));
select pg_temp.check('summary: consumed minus 910', (select consumed = :cons0 - 910 from public.store_admin_shop_summary(null, null) where scope = 'all'));
-- real profit loses that card's margin (base 1000 − cost 910)
select pg_temp.check('summary: profit minus 90', (select real_profit = :prof0 - 90 from public.store_admin_shop_summary(null, null) where scope = 'all'));
select pg_temp.check('shop ledger reconciles', not exists (select 1 from public.store_admin_reconcile() where customer_id = :shop_id));
select pg_temp.check('void card cannot be restored (it was delivered)', public.store_admin_codes_restore(array[:k5]::bigint[], 'x') = 0);

-- ===== refused =====
select pg_temp.check('customer card refused', pg_temp.err(format($$select * from public.store_admin_card_failed(%s, 'used', null, gen_random_uuid())$$, :ck)) like '%CODE_NOT_FOUND%');
select pg_temp.check('stock card refused', pg_temp.err(format($$select * from public.store_admin_card_failed((select code_id from public.store_admin_batch_codes_v2((select batch_id from public.store_admin_batches_v2(%s, 10, 0) limit 1)) where status = 'available' limit 1), 'used', null, gen_random_uuid())$$, :fp)) like '%CODE_NOT_FOUND%');
reset role;
-- an IDOOM-job card keeps its own refund flow
update store.orders set idoom_line = '029000000' where id = :sord;
set role authenticated;
select pg_temp.check('IDOOM order card refused', pg_temp.err(format($$select * from public.store_admin_card_failed(%s, 'not_found', null, gen_random_uuid())$$, :k2)) like '%NOT_REPORTABLE%');
reset role;
update store.orders set idoom_line = null where id = :sord;

-- ===== a later full reversal refunds only the rest =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select balance as bal1 from public.store_admin_shop_summary(null, null) where scope = 'all' \gset
select balance_after as bal2 from public.store_admin_reverse((select w.entry_id from public.store_admin_entries(null, 'purchase', null, null, 50, 0, 'shop') w where w.order_id = :sord), 'كل العملية', gen_random_uuid()) \gset
select pg_temp.check('full reversal refunds 4 × 910 only', :bal2 = :bal1 + 3640, :'bal2');
select pg_temp.check('shop ledger still reconciles', not exists (select 1 from public.store_admin_reconcile() where customer_id = :shop_id));
select pg_temp.check('reversed card cannot fail again', pg_temp.err(format($$select * from public.store_admin_card_failed(%s, 'used', null, gen_random_uuid())$$, :k2)) like '%NOT_REPORTABLE%');
reset role;
select pg_temp.check('check logged once', (select count(*) = 1 and bool_and(result = 'used') from store.card_checks where code_id = :k5));
select pg_temp.check('check log append-only', pg_temp.err('delete from store.card_checks') like '%APPEND_ONLY%');

-- ===== access =====
set role anon;
select pg_temp.check('anon blocked', pg_temp.err(format($$select * from public.store_admin_card_failed(%s, 'used', null, gen_random_uuid())$$, :k1)) like '%permission denied%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin blocked', pg_temp.err(format($$select * from public.store_admin_card_failed(%s, 'used', null, gen_random_uuid())$$, :k1)) like '%NOT_ADMIN%');
reset role;

\set QUIET off
select ok, count(*) from f_results group by ok;
select name, detail from f_results where not ok;
