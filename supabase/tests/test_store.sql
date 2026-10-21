-- Behavioural tests for card store v1. Run as postgres; switches roles like the API would.
\set ON_ERROR_STOP on
\set QUIET on
create temp table t_results (name text, ok boolean, detail text);
grant all on t_results to anon, authenticated;

create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into t_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== as admin (authenticated + uid of owner) =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);

select pg_temp.check('admin is admin', public.store_admin_is_admin());
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Mobilis'), 'Mobilis 1000', 1000, 1, true) \gset prod_
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Free Fire'), 'Free Fire 100+10', 250, 1, true) \gset ff_
\set p1 :prod_store_admin_save_product
\set p2 :ff_store_admin_save_product

-- default rate 2% for p1, then create customer → copied
select public.store_admin_set_rate(null, :p1, 2);
select public.store_admin_create_customer('أحمد', '+213 661 00 00 01', 'secret123') as c1 \gset
select pg_temp.check('phone normalized', (select phone from public.store_admin_customers() where customer_id = :c1) = '0661000001');
select pg_temp.check('default rate copied', (select pct from public.store_admin_rates('phone') where customer_id = :c1 and product_id = :p1) = 2);
select pg_temp.check('short password rejected', pg_temp.err($$select public.store_admin_create_customer('x', '0770000002', 'short')$$) like '%PASSWORD_TOO_SHORT%');
select pg_temp.check('duplicate phone rejected', pg_temp.err($$select public.store_admin_create_customer('x', '0661000001', 'secret123')$$) like '%PHONE_EXISTS%');

-- codes: paste with duplicates and serials
select * from public.store_admin_add_codes(:p1, null, 920, E'AAA-1\nBBB-2 ; SN-2\n\nAAA-1\nCCC-3|SN3') \gset add_
select pg_temp.check('codes added=3 dup=1', :add_added = 3 and :add_duplicates = 1, :add_added || '/' || :add_duplicates);
select * from public.store_admin_add_codes(:p1, null, null, E'AAA-1\nDDD-4') \gset add2_
select pg_temp.check('existing code is duplicate', :add2_added = 1 and :add2_duplicates = 1);
select pg_temp.check('stock available=4', (select available from public.store_admin_stock() where product_id = :p1) = 4);

-- transfers
select * from public.store_admin_transfer(:c1, 'debt', 2000, 'رصيد بالدين', gen_random_uuid()) \gset t1_
select pg_temp.check('debt: bal 2000 debt 2000', :t1_balance_after = 2000 and :t1_debt_after = 2000);
select pg_temp.check('admin over limit allowed + flagged', :'t1_over_limit'::boolean);
select * from public.store_admin_transfer(:c1, 'pay', 3000, 'دفع زائد', gen_random_uuid()) \gset t2_
select pg_temp.check('overpay: debt -1000, bal unchanged', :t2_debt_after = -1000 and :t2_balance_after = 2000);
select * from public.store_admin_transfer(:c1, 'cash', 500, null, '11111111-1111-1111-1111-111111111111') \gset t3_
select * from public.store_admin_transfer(:c1, 'cash', 500, null, '11111111-1111-1111-1111-111111111111') \gset t3b_
select pg_temp.check('idempotent transfer', :t3_entry_id = :t3b_entry_id and :t3b_balance_after = 2500);
select pg_temp.check('cash_refund beyond balance blocked', pg_temp.err(format($$select * from public.store_admin_transfer(%s, 'cash_refund', 99999, null, gen_random_uuid())$$, :c1)) like '%INSUFFICIENT_BALANCE%');
select pg_temp.check('bad kind blocked', pg_temp.err(format($$select * from public.store_admin_transfer(%s, 'purchase', 1, null, gen_random_uuid())$$, :c1)) like '%INVALID_KIND%');
select public.store_admin_set_announcement('متوفر فري فاير');

-- ===== as customer (anon) =====
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;

select pg_temp.check('anon cannot call admin', pg_temp.err($$select public.store_admin_customers()$$) like '%permission denied%');
select pg_temp.check('anon cannot read store tables', pg_temp.err($$select * from store.codes$$) like '%permission denied%');
select pg_temp.check('anon cannot call helper', pg_temp.err($$select private.store_post_entry(1,'cash',1,null,null,null,null,null)$$) like '%permission denied%');

select pg_temp.check('wrong password → no row', (select count(*) from public.store_login('0661000001', 'wrongpass')) = 0);
select pg_temp.check('unknown phone → no row', (select count(*) from public.store_login('0699999999', 'secret123')) = 0);
select session_token as tok from public.store_login('0661 00 00 01', 'secret123') \gset
select pg_temp.check('login ok', length(:'tok') = 64);
select pg_temp.check('bad token rejected', pg_temp.err($$select * from public.store_me('nope')$$) like '%INVALID_SESSION%');

select * from public.store_me(:'tok') \gset me_
select pg_temp.check('me: balance/debt/announcement', :me_balance = 2500 and :me_debt = -1000 and :'me_announcement' = 'متوفر فري فاير');
select pg_temp.check('catalog shows base price only', (select base_price from public.store_catalog(:'tok') where product_id = :p1) = 1000);
select pg_temp.check('catalog availability', (select available from public.store_catalog(:'tok') where product_id = :p2) = false);

-- buy 2 × Mobilis 1000 at 2% → 980 each = 1960
select * from public.store_buy(:'tok', :p1, 2, '22222222-2222-2222-2222-222222222222') \gset b1_
select pg_temp.check('buy returns 2 codes', jsonb_array_length(:'b1_codes'::jsonb) = 2);
select * from public.store_buy(:'tok', :p1, 2, '22222222-2222-2222-2222-222222222222') \gset b1r_
select pg_temp.check('buy idempotent', :b1_order_id = :b1r_order_id);
select * from public.store_me(:'tok') \gset me2_
select pg_temp.check('charged 1960, profit 40', :me2_balance = 540 and :me2_profit = 40, :me2_balance || ' ' || :me2_profit);
select pg_temp.check('insufficient balance', pg_temp.err(format($$select * from public.store_buy(%L, %s, 1, gen_random_uuid())$$, :'tok', :p1)) like '%INSUFFICIENT_BALANCE%');
select pg_temp.check('out of stock', pg_temp.err(format($$select * from public.store_buy(%L, %s, 1, gen_random_uuid())$$, :'tok', :p2)) like '%OUT_OF_STOCK%');
select pg_temp.check('orders list', (select count(*) from public.store_orders(:'tok', null, null, null, null, 10, 0)) = 1);
select pg_temp.check('order detail fields', (select base_amount = 2000 and charged_amount = 1960 and profit = 40 and balance_after = 540 from public.store_orders(:'tok', 'phone', current_date, current_date, 'Mobilis', 10, 0)));
select pg_temp.check('self topup disabled', pg_temp.err(format($$select * from public.store_self_topup(%L, 100, gen_random_uuid())$$, :'tok')) like '%SELF_TOPUP_DISABLED%');

-- ===== admin: enable self topup with limit, reverse purchase =====
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_update_customer(:c1, null, null, 1000, true, null);
select pg_temp.check('admin codes masked', (select bool_and(masked_code like '****%') from public.store_admin_order_codes(:b1_order_id)));
select pg_temp.check('reveal logged', public.store_admin_reveal_code((select min(code_id) from public.store_admin_order_codes(:b1_order_id))) is not null);
select pg_temp.check('admin orders profit (cost known)', (select profit from public.store_admin_orders(null, null, null, null, null, 10, 0) where order_id = :b1_order_id) = 1960 - 1840);

reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select * from public.store_self_topup(:'tok', 1500, gen_random_uuid()) \gset s1_
select pg_temp.check('self topup within limit (debt -1000 → 500)', :s1_debt = 500 and :s1_balance = 2040);
select pg_temp.check('self topup over limit blocked', pg_temp.err(format($$select * from public.store_self_topup(%L, 600, gen_random_uuid())$$, :'tok')) like '%DEBT_LIMIT%');

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('reverse purchase',
  (select balance_after from public.store_admin_reverse((select entry_id from public.store_admin_entries(:c1, 'purchase', null, null, 10, 0)), 'خطأ', gen_random_uuid())) = 4000);
select pg_temp.check('codes voided, order refunded',
  (select voided from public.store_admin_stock() where product_id = :p1) = 2
  and (select status from public.store_admin_orders(:c1, null, null, null, null, 10, 0) where order_id = :b1_order_id) = 'refunded');
select pg_temp.check('double reverse blocked', pg_temp.err(format($$select * from public.store_admin_reverse(%s, null, gen_random_uuid())$$,
  (select entry_id from public.store_admin_entries(:c1, 'purchase', null, null, 10, 0)))) like '%ALREADY_REVERSED%');
select pg_temp.check('refund filter', (select count(*) from public.store_admin_entries(null, 'refund', null, null, 10, 0)) = 1);
select pg_temp.check('reconcile clean', (select count(*) from public.store_admin_reconcile()) = 0);

reset role;
select pg_temp.check('ledger append-only', pg_temp.err($$update store.wallet_entries set amount = 1$$) like '%APPEND_ONLY%');
select pg_temp.check('reveal row written', (select count(*) from store.code_reveals) = 1);

-- non-admin signed-in user
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin blocked', pg_temp.err($$select public.store_admin_customers()$$) like '%NOT_ADMIN%');
reset role;

-- lockout: 5 wrong → locked; correct password then fails; counter persisted
set role anon;
select count(*) from public.store_login('0661000001', 'bad1') \g /dev/null
select count(*) from public.store_login('0661000001', 'bad2') \g /dev/null
select count(*) from public.store_login('0661000001', 'bad3') \g /dev/null
select count(*) from public.store_login('0661000001', 'bad4') \g /dev/null
select count(*) from public.store_login('0661000001', 'bad5') \g /dev/null
select pg_temp.check('locked after 5 failures', (select count(*) from public.store_login('0661000001', 'secret123')) = 0);
reset role;
select pg_temp.check('lock persisted 5 min', (select locked_until > now() + interval '4 minutes' and lock_count = 1 from store.customers where id = :c1));

-- admin password reset unlocks and revokes sessions
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_set_password(:c1, 'newsecret1');
reset role;
set role anon;
select pg_temp.check('old session revoked', pg_temp.err(format($$select * from public.store_me(%L)$$, :'tok')) like '%INVALID_SESSION%');
select pg_temp.check('login with new password', (select count(*) from public.store_login('0661000001', 'newsecret1')) = 1);
reset role;

\set QUIET off
select ok, count(*) from t_results group by ok;
select name, detail from t_results where not ok;
