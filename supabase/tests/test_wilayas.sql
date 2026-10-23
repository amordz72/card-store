-- Behavioural tests for v1.24 (shop province + IDOOM known line inside the province). Run after all migrations and the other tests.
\set ON_ERROR_STOP on
\set QUIET on
create temp table w_results (name text, ok boolean, detail text);
grant all on w_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into w_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

update store.idoom_jobs set status = 'cancelled' where status in ('queued', 'claimed');
select id as shop from store.customers where is_shop \gset

-- ===== owner: card, phone, four shops =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'Idoom ADSL W', 'net', 8, true) \g /dev/null
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Idoom ADSL W'), 'ADSL W 1000', 1000, 1, true) as adsl \gset
select added from public.store_admin_add_codes(:adsl, null, 900, E'W-1\nW-2\nW-3\nW-4') \g /dev/null
select * from public.store_admin_shop_topup(5000, 'w', gen_random_uuid()) \g /dev/null
select public.store_admin_create_customer('محل تقرت 1', '0772000001', 'secret123') as a \gset
select public.store_admin_create_customer('محل تقرت 2', '0772000002', 'secret123') as b \gset
select public.store_admin_create_customer('محل ورقلة', '0772000003', 'secret123') as c \gset
select public.store_admin_create_customer('محل بلا ولاية', '0772000004', 'secret123') as d \gset
select entry_id from public.store_admin_transfer(:a, 'cash', 3000, null, gen_random_uuid()) \g /dev/null
select public.store_admin_set_idoom_topup(:a, true) \g /dev/null
select * from public.store_admin_executor_create('هاتف ولاية') \gset e_
select public.store_admin_set_customer_wilaya(:a, 55) \g /dev/null
select pg_temp.check('owner sets a province', (select wilaya_code from public.store_admin_customer_wilayas() where customer_id = :a) = 55);
select pg_temp.check('unknown province refused', pg_temp.err(format('select public.store_admin_set_customer_wilaya(%s, 77)', :a)) like '%WILAYA_NOT_FOUND%');
select pg_temp.check('unknown account refused', pg_temp.err('select public.store_admin_set_customer_wilaya(999999, 55)') like '%CUSTOMER_NOT_FOUND%');
select public.store_admin_set_customer_wilaya(:shop, 55) \g /dev/null
select pg_temp.check('owner shop has a province', (select wilaya_code from public.store_admin_customer_wilayas() where is_shop) = 55);
reset role;

-- ===== everyone: the list; shops set their own =====
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select pg_temp.check('58 provinces, 55 = تقرت', (select count(*) from public.store_wilayas()) = 58
  and (select name_ar from public.store_wilayas() where code = 55) = 'تقرت');
select session_token as ta from public.store_login('0772000001', 'secret123') \gset
select session_token as tb from public.store_login('0772000002', 'secret123') \gset
select session_token as tc from public.store_login('0772000003', 'secret123') \gset
select session_token as td from public.store_login('0772000004', 'secret123') \gset
select public.store_set_my_wilaya(:'tb', 55) \g /dev/null
select public.store_set_my_wilaya(:'tc', 30) \g /dev/null
select pg_temp.check('shop sets its own', public.store_my_wilaya(:'tb') = 55 and public.store_my_wilaya(:'tc') = 30 and public.store_my_wilaya(:'td') is null);
select pg_temp.check('shop: unknown province refused', pg_temp.err(format('select public.store_set_my_wilaya(%L, 0)', :'tb')) like '%WILAYA_NOT_FOUND%');
select pg_temp.check('bad token', pg_temp.err($$select public.store_set_my_wilaya('nope', 55)$$) like '%INVALID_SESSION%');
select pg_temp.check('anon cannot run owner function', pg_temp.err('select * from public.store_admin_customer_wilayas()') like '%permission denied%');
select pg_temp.check('no direct table access', pg_temp.err('select * from store.wilayas') like '%permission denied%');

-- ===== shop A (تقرت) tops up line X =====
select count(*) from public.store_exec_claim_v2(:'e_token') \g /dev/null
select * from public.store_idoom_create(:'ta', :adsl, '029111222', gen_random_uuid()) \gset ja_
select job_id from public.store_exec_claim_v2(:'e_token') \g /dev/null
select public.store_exec_report(:'e_token', :ja_job_id, 'SUCCESS_TEXT', 'FTTH 60M Prepaid individual', 'ok') \g /dev/null
select pg_temp.check('A: own line, with date', (select offer = 'FTTH 60M Prepaid individual' and checked_at is not null from public.store_idoom_line_info(:'ta', '029111222')));
select pg_temp.check('B same province: full offer, no date', (select offer = 'FTTH 60M Prepaid individual' and checked_at is null from public.store_idoom_line_info(:'tb', '029 111 222')));
select pg_temp.check('C other province: nothing', not exists (select 1 from public.store_idoom_line_info(:'tc', '029111222')));
select pg_temp.check('D no province: nothing', not exists (select 1 from public.store_idoom_line_info(:'td', '029111222')));
select pg_temp.check('B other number: nothing', not exists (select 1 from public.store_idoom_line_info(:'tb', '029111223')));
reset role;

-- ===== owner job on line Y counts for his shop's province =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select * from public.store_admin_idoom_create(:adsl, '029333444', gen_random_uuid()) \gset o_
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select job_id from public.store_exec_claim_v2(:'e_token') \g /dev/null
select public.store_exec_take_code(:'e_token', :o_job_id, 'x') \g /dev/null
select public.store_exec_report(:'e_token', :o_job_id, 'SUCCESS_TEXT', '20M ADSL Prepaid', 'ok') \g /dev/null
select pg_temp.check('owner job seen in his province', (select offer from public.store_idoom_line_info(:'tb', '029333444')) = '20M ADSL Prepaid');
select pg_temp.check('owner job not seen elsewhere', not exists (select 1 from public.store_idoom_line_info(:'tc', '029333444')));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_set_customer_wilaya(:shop, null) \g /dev/null
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select pg_temp.check('owner shop without province: owner job not shared', not exists (select 1 from public.store_idoom_line_info(:'tb', '029333444')));
-- moving B to another province hides X from B
select public.store_set_my_wilaya(:'tb', 30) \g /dev/null
select pg_temp.check('B moved: X hidden', not exists (select 1 from public.store_idoom_line_info(:'tb', '029111222')));
select pg_temp.check('C now sees nothing from تقرت either', not exists (select 1 from public.store_idoom_line_info(:'tc', '029111222')));
reset role;

\set QUIET off
select ok, count(*) from w_results group by ok;
select name, detail from w_results where not ok;
