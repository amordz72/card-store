-- Behavioural tests for v1.23 (IDOOM top-up for customers). Run after all migrations and the other tests.
\set ON_ERROR_STOP on
\set QUIET on
create temp table c_results (name text, ok boolean, detail text);
grant all on c_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into c_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- clean queue from earlier test files (test database only)
update store.idoom_jobs set status = 'cancelled' where status in ('queued', 'claimed');
select id as shop from store.customers where is_shop \gset

-- ===== owner: cards, a phone, two customers =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'Idoom ADSL C', 'net', 6, true) \g /dev/null
select public.store_admin_save_brand(null, 'Idoom 4G C', 'net', 7, true) \g /dev/null
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Idoom ADSL C'), 'ADSL 1000', 1000, 1, true) as adsl \gset
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Idoom 4G C'), '4G 1000', 1000, 1, true) as lte \gset
select added from public.store_admin_add_codes(:adsl, null, 900, E'A-0001\nA-0002\nA-0003\nA-0004\nA-0005\nA-0006\nA-0007\nA-0008\nA-0009\nA-0010') \g /dev/null
select added from public.store_admin_add_codes(:lte, null, 900, E'L-0001') \g /dev/null
select public.store_admin_create_customer('زبون إيدوم', '0771000001', 'secret123') as cu \gset
select public.store_admin_create_customer('زبون آخر', '0771000002', 'secret123') as cu2 \gset
select entry_id from public.store_admin_transfer(:cu, 'cash', 3500, null, gen_random_uuid()) \g /dev/null
select * from public.store_admin_executor_create('هاتف الزبائن') \gset e_
reset role;

select set_config('request.jwt.claim.sub', '', false);
set role anon;
select session_token as tok from public.store_login('0771000001', 'secret123') \gset
select session_token as tok2 from public.store_login('0771000002', 'secret123') \gset
select pg_temp.check('off by default', (select not enabled from public.store_idoom_status(:'tok')));
select pg_temp.check('not enabled refused', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '029669458', gen_random_uuid())$$, :'tok', :adsl)) like '%IDOOM_NOT_ENABLED%');
select pg_temp.check('anon cannot enable', pg_temp.err(format('select public.store_admin_set_idoom_topup(%s, true)', :cu)) like '%permission denied%');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin cannot enable', pg_temp.err(format('select public.store_admin_set_idoom_topup(%s, true)', :cu)) like '%NOT_ADMIN%');
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_set_idoom_topup(:cu, true) \g /dev/null
select pg_temp.check('shop account cannot be enabled', pg_temp.err(format('select public.store_admin_set_idoom_topup(%s, true)', :shop)) like '%CUSTOMER_NOT_FOUND%');
select pg_temp.check('enabled list', array(select public.store_admin_idoom_topup_customers()) = array[:cu]::bigint[]);
reset role;

-- ===== phone offline / online =====
update store.executors set last_seen_at = now() - interval '10 minutes';
set role anon;
select pg_temp.check('status: enabled, phone offline', (select enabled and not phone_online from public.store_idoom_status(:'tok')));
select pg_temp.check('offline phone refuses', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '029669458', gen_random_uuid())$$, :'tok', :adsl)) like '%IDOOM_PHONE_OFFLINE%');
select count(*) from public.store_exec_claim_v2(:'e_token') \g /dev/null
select pg_temp.check('phone online after contact', (select phone_online from public.store_idoom_status(:'tok')));

-- ===== create: card bought from the customer's balance, code hidden =====
select pg_temp.check('bad line', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '12345', gen_random_uuid())$$, :'tok', :adsl)) like '%INVALID_LINE%');
select pg_temp.check('4G card on fixed line', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '029669458', gen_random_uuid())$$, :'tok', :lte)) like '%CARD_LINE_MISMATCH%');
select gen_random_uuid() as rq \gset
select * from public.store_idoom_create(:'tok', :adsl, '029 669 458', :'rq') \gset j1_
select * from public.store_idoom_create(:'tok', :adsl, '029669458', :'rq') \gset j1b_
select pg_temp.check('idempotent request', :j1_job_id = :j1b_job_id and :'j1_status' = 'queued');
select pg_temp.check('same line busy', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '029669458', gen_random_uuid())$$, :'tok', :adsl)) like '%IDOOM_LINE_BUSY%');
select pg_temp.check('other customer: request id conflict', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '029669458', %L)$$, :'tok2', :adsl, :'rq')) like '%IDOOM_NOT_ENABLED%');
reset role;
select order_id as o1, code_id as k1 from store.idoom_jobs where id = :j1_job_id \gset
select pg_temp.check('card held by the job, charged once', :k1 is not null
  and (select count(*) from store.orders o join store.idoom_jobs j on j.order_id = o.id where j.request_id = :'rq') = 1
  and (select balance from store.customers where id = :cu) = 3500 - (select charged_amount from store.orders where id = :o1));
select charged_amount as price from store.orders where id = :o1 \gset
select pg_temp.check('order marked for the line', (select idoom_line from store.orders where id = :o1) = '029669458');
set role anon;
select pg_temp.check('code hidden (v2)', (select bool_and(code = 'تعبئة إيدوم للخط 029669458' and serial is null and not can_report) from public.store_order_codes_v2(:'tok', :o1)));
select pg_temp.check('code hidden (v1)', (select bool_and(code like 'تعبئة إيدوم%') from public.store_order_codes(:'tok', :o1)));
select pg_temp.check('top-up card not reportable', pg_temp.err(format($$select public.store_report_code(%L, %s, 'used', null)$$, :'tok', :k1)) like '%NOT_REPORTABLE%');
select pg_temp.check('listed for the customer', (select status = 'queued' and charged_amount = :price and not refunded from public.store_idoom_jobs(:'tok', 20, 0) where job_id = :j1_job_id));
select pg_temp.check('other customer sees nothing', not exists (select 1 from public.store_idoom_jobs(:'tok2', 20, 0)));
select pg_temp.check('other customer cannot cancel', pg_temp.err(format('select public.store_idoom_cancel(%L, %s)', :'tok2', :j1_job_id)) like '%NOT_CANCELLABLE%');

-- ===== phone: same card, success =====
select job_id as cj, code as cc from public.store_exec_claim_v2(:'e_token') \gset
select pg_temp.check('phone claims the customer job with its card', :cj = :j1_job_id and :'cc' = (select 'A-000' || 1));
select pg_temp.check('take_code returns the same card', public.store_exec_take_code(:'e_token', :j1_job_id, 'ADSL 2M') = :'cc');
select pg_temp.check('customer cannot cancel once taken', pg_temp.err(format('select public.store_idoom_cancel(%L, %s)', :'tok', :j1_job_id)) like '%NOT_CANCELLABLE%');
select pg_temp.check('success', public.store_exec_report(:'e_token', :j1_job_id, 'SUCCESS_TEXT', 'ADSL 2M', 'ok') = 'success');
select pg_temp.check('line info: own offer', (select offer from public.store_idoom_line_info(:'tok', '029669458')) = 'ADSL 2M');
select pg_temp.check('line info: not for others', not exists (select 1 from public.store_idoom_line_info(:'tok2', '029669458')));
reset role;
select pg_temp.check('balance after success', (select balance from store.customers where id = :cu) = 3500 - :price);

-- ===== stopped before Valider: full refund, card back =====
set role anon;
select * from public.store_idoom_create(:'tok', :adsl, '029669458', gen_random_uuid()) \gset j2_
select job_id as cj2 from public.store_exec_claim_v2(:'e_token') \gset
select pg_temp.check('pre-submit failed', public.store_exec_report(:'e_token', :j2_job_id, 'PRE_SUBMIT_FAILED', null, 'stop') = 'failed');
select pg_temp.check('customer sees refund', (select refunded from public.store_idoom_jobs(:'tok', 20, 0) where job_id = :j2_job_id));
reset role;
select pg_temp.check('refunded + card back', (select balance from store.customers where id = :cu) = 3500 - :price
  and (select count(*) from store.codes where product_id = :adsl and status = 'available') = 9);
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('owner retry refused for customer jobs', pg_temp.err(format($$select public.store_admin_idoom_retry(%s, null)$$, :j2_job_id)) like '%NOT_RETRYABLE%');
reset role;

-- ===== first attempt: the customer cannot cancel (the owner can) =====
set role anon;
select * from public.store_idoom_create(:'tok', :adsl, '029669458', gen_random_uuid()) \gset j3_
select pg_temp.check('no customer cancel on first attempt', pg_temp.err(format('select public.store_idoom_cancel(%L, %s)', :'tok', :j3_job_id)) like '%NOT_CANCELLABLE%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_idoom_cancel(:j3_job_id) \g /dev/null
reset role;
select pg_temp.check('cancel refunds + card back', (select balance from store.customers where id = :cu) = 3500 - :price
  and (select count(*) from store.codes where product_id = :adsl and status = 'available') = 9);

-- ===== used card: refund, one retry with another card, then final =====
set role anon;
select * from public.store_idoom_create(:'tok', :adsl, '029669458', gen_random_uuid()) \gset j4_
reset role;
select code_id as used1, order_id as uo1 from store.idoom_jobs where id = :j4_job_id \gset
set role anon;
select job_id as cj4 from public.store_exec_claim_v2(:'e_token') \gset
select pg_temp.check('used card reported', public.store_exec_report(:'e_token', :j4_job_id, 'VOUCHER_USED', null, 'Carte déjà utilisée !') = 'used_card');
reset role;
select pg_temp.check('retried with another card', (select status = 'queued' and attempt = 2 and code_id <> :used1 and order_id <> :uo1 from store.idoom_jobs where id = :j4_job_id));
select pg_temp.check('used card stays sold, first order refunded', (select status from store.codes where id = :used1) = 'sold'
  and (select status from store.orders where id = :uo1) = 'refunded');
select pg_temp.check('customer charged once net', (select balance from store.customers where id = :cu) = 3500 - 2 * :price);
select pg_temp.check('second order also hidden', (select idoom_line from store.orders o join store.idoom_jobs j on j.order_id = o.id where j.id = :j4_job_id) = '029669458');
set role anon;
select pg_temp.check('first order code still hidden', (select bool_and(code like 'تعبئة إيدوم%') from public.store_order_codes_v2(:'tok', :uo1)));
select job_id as cj5 from public.store_exec_claim_v2(:'e_token') \gset
select pg_temp.check('second used card is final', public.store_exec_report(:'e_token', :j4_job_id, 'VOUCHER_USED', null, 'again') = 'used_card');
reset role;
select pg_temp.check('final: no third try, refunded', (select status = 'used_card' and attempt = 2 from store.idoom_jobs where id = :j4_job_id)
  and (select balance from store.customers where id = :cu) = 3500 - :price);

-- second attempt waiting: the customer may cancel it → full refund, second card back
set role anon;
select * from public.store_idoom_create(:'tok', :adsl, '029669458', gen_random_uuid()) \gset j5_
select job_id from public.store_exec_claim_v2(:'e_token') \g /dev/null
select public.store_exec_report(:'e_token', :j5_job_id, 'VOUCHER_USED', null, 'x') \g /dev/null
select pg_temp.check('customer cancels the second attempt', public.store_idoom_cancel(:'tok', :j5_job_id) = 'cancelled');
reset role;
select pg_temp.check('cancelled retry: refunded in full', (select balance from store.customers where id = :cu) = 3500 - :price
  and (select attempt from store.idoom_jobs where id = :j5_job_id) = 2);

-- used card with no other card left: refund only
update store.codes set status = 'void' where product_id = :adsl and status = 'available' and id > (select min(id) from store.codes where product_id = :adsl and status = 'available');
set role anon;
select * from public.store_idoom_create(:'tok', :adsl, '029669458', gen_random_uuid()) \gset j6_
select job_id from public.store_exec_claim_v2(:'e_token') \g /dev/null
select public.store_exec_report(:'e_token', :j6_job_id, 'VOUCHER_USED', null, 'x') \g /dev/null
reset role;
select pg_temp.check('no stock: refunded, not retried', (select status = 'used_card' and attempt = 1 and reply like '[استُرد المبلغ؛ لا بطاقة أخرى%' from store.idoom_jobs where id = :j6_job_id)
  and (select balance from store.customers where id = :cu) = 3500 - :price);
update store.codes set status = 'available' where product_id = :adsl and status = 'void';

-- ===== review → owner bell; owner cancel refunds =====
set role anon;
select * from public.store_idoom_create(:'tok', :adsl, '029669458', gen_random_uuid()) \gset j7_
select job_id from public.store_exec_claim_v2(:'e_token') \g /dev/null
select pg_temp.check('unknown reply → review', public.store_exec_report(:'e_token', :j7_job_id, 'WEIRD', null, '?') = 'review');
select * from public.store_idoom_create(:'tok', :adsl, '029669458', gen_random_uuid()) \gset j8_
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('bell counts customer review', public.store_admin_idoom_review_count() = 1);
select pg_temp.check('owner list shows the customer', (select customer_name from public.store_admin_idoom_jobs_v3(50) where id = :j7_job_id) = 'زبون إيدوم');
select pg_temp.check('owner cancel of a waiting customer job', public.store_admin_idoom_cancel(:j8_job_id) = 'cancelled');
select pg_temp.check('owner jobs cannot be resolved here', pg_temp.err(format('select public.store_admin_idoom_resolve(%s, true)', :j1_job_id)) like '%NOT_IN_REVIEW%');
select pg_temp.check('owner decides: not done', public.store_admin_idoom_resolve(:j7_job_id, false) = 'failed');
select pg_temp.check('bell cleared', public.store_admin_idoom_review_count() = 0);
select pg_temp.check('decided once', pg_temp.err(format('select public.store_admin_idoom_resolve(%s, true)', :j7_job_id)) like '%NOT_IN_REVIEW%');
reset role;
select pg_temp.check('owner cancel refunded', (select o.status from store.orders o join store.idoom_jobs j on j.order_id = o.id where j.id = :j8_job_id) = 'refunded'
  and (select balance from store.customers where id = :cu) = 3500 - :price
  and (select o.status from store.orders o join store.idoom_jobs j on j.order_id = o.id where j.id = :j7_job_id) = 'refunded');

-- ===== limits, balance =====
update store.idoom_jobs set created_at = now() - interval '2 hours' where customer_id = :cu;  -- earlier steps are not part of the limit tests
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select entry_id from public.store_admin_transfer(:cu, 'cash', 5000, null, gen_random_uuid()) \g /dev/null
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select * from public.store_idoom_create(:'tok', :adsl, '029000001', gen_random_uuid()) \g /dev/null
select * from public.store_idoom_create(:'tok', :adsl, '029000002', gen_random_uuid()) \g /dev/null
select * from public.store_idoom_create(:'tok', :adsl, '029000003', gen_random_uuid()) \g /dev/null
select pg_temp.check('3 waiting at most', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '029000004', gen_random_uuid())$$, :'tok', :adsl)) like '%IDOOM_TOO_MANY%');
reset role;
update store.idoom_jobs set status = 'cancelled' where customer_id = :cu and status = 'queued';
update store.idoom_jobs set created_at = now() where id in (select id from store.idoom_jobs where customer_id = :cu order by id desc limit 10);
set role anon;
select pg_temp.check('10 requests per hour', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '029000006', gen_random_uuid())$$, :'tok', :adsl)) like '%IDOOM_TOO_MANY%');
reset role;
update store.idoom_jobs set created_at = now() - interval '2 hours' where customer_id = :cu;
update store.customers set balance = 10 where id = :cu;
set role anon;
select pg_temp.check('insufficient balance, no job', pg_temp.err(format($$select * from public.store_idoom_create(%L, %s, '029000005', gen_random_uuid())$$, :'tok', :adsl)) like '%INSUFFICIENT_BALANCE%'
  and not exists (select 1 from public.store_idoom_jobs(:'tok', 100, 0) where line = '029000005'));
select pg_temp.check('bad token', pg_temp.err($$select * from public.store_idoom_status('nope')$$) like '%INVALID_SESSION%');
reset role;

-- ===== owner jobs unchanged: no card until the phone asks, the shop pays =====
update store.idoom_jobs set status = 'cancelled' where status in ('queued', 'claimed');
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select * from public.store_admin_shop_topup(5000, 'idoom c', gen_random_uuid()) \g /dev/null
select * from public.store_admin_idoom_create(:adsl, '029669458', gen_random_uuid()) \gset a_
reset role;
select pg_temp.check('owner job holds no card', (select code_id is null and customer_id is null from store.idoom_jobs where id = :a_job_id));
set role anon;
select job_id from public.store_exec_claim_v2(:'e_token') \g /dev/null
select public.store_exec_take_code(:'e_token', :a_job_id, 'x') \g /dev/null
select pg_temp.check('owner used card: no retry', public.store_exec_report(:'e_token', :a_job_id, 'VOUCHER_USED', null, 'x') = 'used_card');
reset role;
select pg_temp.check('owner job paid by the shop, stays used', (select c.is_shop from store.orders o join store.customers c on c.id = o.customer_id join store.idoom_jobs j on j.order_id = o.id where j.id = :a_job_id)
  and (select status = 'used_card' and attempt = 1 from store.idoom_jobs where id = :a_job_id));

\set QUIET off
select ok, count(*) from c_results group by ok;
select name, detail from c_results where not ok;
