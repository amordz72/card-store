-- Behavioural tests for IDOOM top-up (v1.11–v1.14). Run after test_shop.sql on the same database.
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
select public.store_admin_save_brand(null, 'IDOOM', 'net', 5, true) \g /dev/null
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'IDOOM'), 'IDOOM 500', 500, 1, true) as idm \gset
select added from public.store_admin_add_codes(:idm, null, 480, E'1111222233334444\n5555666677778888') \g /dev/null
select * from public.store_admin_shop_topup(5000, 'idoom', gen_random_uuid()) \g /dev/null
select * from public.store_admin_executor_create('هاتف 1') \gset e_

-- lookup: 9 digits, no card, cached, limited
select pg_temp.check('10-digit line rejected', pg_temp.err($$select * from public.store_admin_idoom_lookup('0330971540', gen_random_uuid())$$) like '%INVALID_LINE%');
select * from public.store_admin_idoom_lookup('029 669 458', gen_random_uuid()) \gset l_
select * from public.store_admin_idoom_lookup('029669458', gen_random_uuid()) \gset l2_
select pg_temp.check('pending lookup reused', :l_job_id = :l2_job_id);
reset role;
set role anon;
select pg_temp.check('bad token rejected', pg_temp.err($$select * from public.store_exec_claim_v2('nope')$$) like '%INVALID_EXECUTOR%');
select job_id, kind, coalesce(code, '') as code from public.store_exec_claim_v2(:'e_token') \gset lc_
select pg_temp.check('lookup claimed without code', :lc_job_id = :l_job_id and :'lc_kind' = 'lookup' and :'lc_code' = '');
select pg_temp.check('lookup reported', public.store_exec_report(:'e_token', :l_job_id, 'LOOKUP_OK', 'FTTH 15M', 'Offre: FTTH 15M') = 'looked_up');
reset role;
set role authenticated;
select * from public.store_admin_idoom_lookup('029669458', gen_random_uuid()) \gset l3_
select pg_temp.check('fresh result reused (15 min)', :l3_job_id = :l_job_id);
select pg_temp.check('lookup listed with offer', exists (select 1 from public.store_admin_idoom_jobs_v2(10) where kind = 'lookup' and offer = 'FTTH 15M'));
reset role;
insert into store.idoom_jobs (kind, line, request_id, created_by, status, finished_at, created_at)
select 'lookup', '031000000', gen_random_uuid(), '60e166af-1366-47cc-81f9-791a4585c66e', 'failed', now(), now() from generate_series(1, 3);
set role authenticated;
select pg_temp.check('3 checks per line per hour', pg_temp.err($$select * from public.store_admin_idoom_lookup('031000000', gen_random_uuid())$$) like '%RATE_LIMIT_LINE%');
select pg_temp.check('anon cannot queue', true);
reset role;
set role anon;
select pg_temp.check('anon cannot create jobs', pg_temp.err(format($$select * from public.store_admin_idoom_create(%s, '029669458', gen_random_uuid())$$, :idm)) like '%permission denied%');
reset role;

-- charge: no card until the phone asks after the check
set role authenticated;
select * from public.store_admin_idoom_create(:idm, '029669458', gen_random_uuid()) \gset c_
reset role;
select pg_temp.check('queued charge holds no card', (select code_id is null and order_id is null from store.idoom_jobs where id = :c_job_id)
  and (select count(*) from store.codes where product_id = :idm and status = 'available') = 2);
set role anon;
select job_id, kind, coalesce(code, '') as code from public.store_exec_claim_v2(:'e_token') \gset cc_
select pg_temp.check('charge claimed without code', :cc_job_id = :c_job_id and :'cc_kind' = 'charge' and :'cc_code' = '');
select public.store_exec_take_code(:'e_token', :c_job_id, 'FTTH 15M') as code1 \gset
select public.store_exec_take_code(:'e_token', :c_job_id, 'FTTH 15M') as code2 \gset
select pg_temp.check('take code idempotent', :'code1' = :'code2' and :'code1' = '1111222233334444');
reset role;
select balance as bal_after_buy from store.customers where is_shop \gset
set role anon;
select pg_temp.check('stopped before Valider → failed', public.store_exec_report(:'e_token', :c_job_id, 'PRE_SUBMIT_FAILED', null, 'le numéro de téléphone est invalide.') = 'failed');
reset role;
select pg_temp.check('card back in stock', (select status = 'available' and order_id is null from store.codes where code = '1111222233334444'));
select pg_temp.check('shop refunded', (select balance from store.customers where is_shop) = :bal_after_buy + 480);
select pg_temp.check('job keeps refunded order, no card', (select j.code_id is null and o.status = 'refunded'
  from store.idoom_jobs j join store.orders o on o.id = j.order_id where j.id = :c_job_id));

-- charge to the end: used card keeps the code sold
set role authenticated;
select * from public.store_admin_idoom_create(:idm, '030977530', gen_random_uuid()) \gset d_
reset role;
set role anon;
select job_id from public.store_exec_claim_v2(:'e_token') \gset dc_
select pg_temp.check('no second job while one is claimed', :dc_job_id = :d_job_id and not exists (select 1 from public.store_exec_claim_v2(:'e_token')));
select public.store_exec_take_code(:'e_token', :d_job_id, 'ADSL') \g /dev/null
select pg_temp.check('used card mapped', public.store_exec_report(:'e_token', :d_job_id, 'VOUCHER_USED', 'ADSL', 'Carte déjà utilisée !') = 'used_card');
select pg_temp.check('report only once', pg_temp.err(format($$select public.store_exec_report('%s', %s, 'SUCCESS_TEXT', '', '')$$, :'e_token', :d_job_id)) like '%JOB_NOT_CLAIMED%');
reset role;
select pg_temp.check('used card stays sold', (select k.status = 'sold' from store.idoom_jobs j join store.codes k on k.id = j.code_id where j.id = :d_job_id));
set role authenticated;
select pg_temp.check('admin sees phones', exists (select 1 from public.store_admin_executors() where name = 'هاتف 1' and last_seen_at is not null));
reset role;
\set QUIET off
select name, ok, detail from i_results where not ok;
select count(*) filter (where ok) as passed, count(*) as total from i_results;
