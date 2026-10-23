-- Behavioural tests for v1.20 (card reports + bell count). Run after all migrations and the other tests.
\set ON_ERROR_STOP on
\set QUIET on
create temp table r_results (name text, ok boolean, detail text);
grant all on r_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into r_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== owner: a product, 3 codes, a customer with balance =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'PUBG'), 'PUBG report test', 500, 9, true) as rp \gset
select public.store_admin_set_price(null, :rp, 'fixed', 480);
select added from public.store_admin_add_codes(:rp, null, 450, E'RPT-1\nRPT-2\nRPT-3') \g /dev/null
select public.store_admin_create_customer('مبلّغ', '0770123456', 'secret123') as rc \gset
select public.store_admin_create_customer('آخر', '0770123457', 'secret123') as rc2 \gset
select entry_id from public.store_admin_transfer(:rc, 'cash', 5000, null, gen_random_uuid()) \g /dev/null
select pg_temp.check('bell starts at zero', public.store_admin_open_reports_count() = 0);

-- ===== customer buys 2 and reports one =====
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select session_token as tok from public.store_login('0770123456', 'secret123') \gset
select session_token as tok2 from public.store_login('0770123457', 'secret123') \gset
select order_id as ord from public.store_buy(:'tok', :rp, 2, gen_random_uuid()) \gset
select min(code_id) as k1, max(code_id) as k2 from public.store_order_codes_v2(:'tok', :ord) \gset

select pg_temp.check('codes v2: 2 reportable', (select count(*) filter (where can_report and report_status is null) from public.store_order_codes_v2(:'tok', :ord)) = 2);
select pg_temp.check('other customer cannot see order', pg_temp.err(format($$select * from public.store_order_codes_v2(%L, %s)$$, :'tok2', :ord)) like '%ORDER_NOT_FOUND%');
select pg_temp.check('bad reason', pg_temp.err(format($$select public.store_report_code(%L, %s, 'x', null)$$, :'tok', :k1)) like '%INVALID_REASON%');
select pg_temp.check('other customer cannot report', pg_temp.err(format($$select public.store_report_code(%L, %s, 'used', null)$$, :'tok2', :k1)) like '%CODE_NOT_FOUND%');

select public.store_report_code(:'tok', :k1, 'used', '  رفضها التطبيق  ') as rep \gset
select pg_temp.check('report saved with trimmed note', (select reason = 'used' and note = 'رفضها التطبيق' and status = 'open' from public.store_my_reports(:'tok') where report_id = :rep));
select pg_temp.check('second report on same card', pg_temp.err(format($$select public.store_report_code(%L, %s, 'other', null)$$, :'tok', :k1)) like '%ALREADY_REPORTED%');
select pg_temp.check('codes v2 shows report', (select report_status = 'open' and not can_report from public.store_order_codes_v2(:'tok', :ord) where code_id = :k1));
select pg_temp.check('old order codes still works', (select count(*) from public.store_order_codes(:'tok', :ord)) = 2);

-- ===== owner reviews =====
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('bell = 1', public.store_admin_open_reports_count() = 1);
select pg_temp.check('admin list masked + history',
  (select masked_code like '****%' and customer_reports = 1 and customer_accepted = 0 and supplier is not null from public.store_admin_reports('open') where report_id = :rep));
select pg_temp.check('resolve bad status', pg_temp.err(format($$select public.store_admin_resolve_report(%s, 'open', null)$$, :rep)) like '%INVALID_REASON%');
select public.store_admin_resolve_report(:rep, 'accepted', 'أُرجع الثمن يدويًا');
select pg_temp.check('resolved once only', pg_temp.err(format($$select public.store_admin_resolve_report(%s, 'rejected', null)$$, :rep)) like '%ALREADY_RESOLVED%');
select pg_temp.check('missing report', pg_temp.err($$select public.store_admin_resolve_report(-1, 'accepted', null)$$) like '%REPORT_NOT_FOUND%');
select pg_temp.check('bell back to 0', public.store_admin_open_reports_count() = 0);
select pg_temp.check('accepted counted', (select customer_accepted = 1 from public.store_admin_reports(null) where report_id = :rep));
select pg_temp.check('no automatic compensation', (select balance from public.store_admin_customers() where customer_id = :rc) = 5000 - 960);

-- refunded order → its cards cannot be reported
select entry_id from public.store_admin_reverse((select entry_id from public.store_admin_entries(:rc, 'purchase', null, null, 10, 0, null) limit 1), null, gen_random_uuid()) \g /dev/null

-- report window: age the sale beyond the setting
reset role;
update store.codes set sold_at = now() - interval '8 days' where id = :k2;

set role anon;
select pg_temp.check('customer sees decision', (select status = 'accepted' and admin_note = 'أُرجع الثمن يدويًا' from public.store_my_reports(:'tok') where report_id = :rep));
select pg_temp.check('refunded or old card not reportable', pg_temp.err(format($$select public.store_report_code(%L, %s, 'used', null)$$, :'tok', :k2)) ~ '(NOT_REPORTABLE|REPORT_WINDOW_CLOSED)');
select pg_temp.check('anon cannot call admin reports', pg_temp.err($$select * from public.store_admin_reports(null)$$) like '%permission denied%');
select pg_temp.check('anon cannot read reports table', pg_temp.err($$select * from store.card_reports$$) like '%permission denied%');
reset role;

-- window alone (order still done): new purchase, aged card
set role anon;
select order_id as ord2 from public.store_buy(:'tok', :rp, 1, gen_random_uuid()) \gset
select code_id as k3 from public.store_order_codes_v2(:'tok', :ord2) \gset
reset role;
update store.codes set sold_at = now() - interval '8 days' where id = :k3;
set role anon;
select pg_temp.check('window closed after 7 days', pg_temp.err(format($$select public.store_report_code(%L, %s, 'used', null)$$, :'tok', :k3)) like '%REPORT_WINDOW_CLOSED%');
select pg_temp.check('codes v2: aged card not reportable', (select not can_report from public.store_order_codes_v2(:'tok', :ord2)));
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin blocked from bell', pg_temp.err($$select public.store_admin_open_reports_count()$$) like '%NOT_ADMIN%');
reset role;

\set QUIET off
select ok, count(*) from r_results group by ok;
select name, detail from r_results where not ok;
