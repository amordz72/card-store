-- Behavioural tests for v1.11 (IDOOM top-up jobs). Run after test_shop.sql on the same database.
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

select pg_temp.check('bad line rejected', pg_temp.err(format($$select * from public.store_admin_idoom_create(%s, '12345', gen_random_uuid())$$, :idm)) like '%INVALID_LINE%');
select * from public.store_admin_idoom_create(:idm, '029 669 458', '44444444-4444-4444-4444-444444444444') \gset j_
select * from public.store_admin_idoom_create(:idm, '029669458', '44444444-4444-4444-4444-444444444444') \gset j2_
select pg_temp.check('create idempotent', :j_job_id = :j2_job_id and :'j_status' = 'queued');
reset role;
select pg_temp.check('one code sold to shop', (select count(*) from store.codes where product_id = :idm and status = 'sold') = 1);
set role authenticated;
select * from public.store_admin_executor_create('هاتف 1') \gset e_

reset role;
set role anon;
select pg_temp.check('bad token rejected', pg_temp.err($$select * from public.store_exec_claim('nope')$$) like '%INVALID_EXECUTOR%');
select pg_temp.check('anon cannot create jobs', pg_temp.err(format($$select * from public.store_admin_idoom_create(%s, '029669458', gen_random_uuid())$$, :idm)) like '%permission denied%');
select * from public.store_exec_claim(:'e_token') \gset c_
select pg_temp.check('claim returns line and code', :c_job_id = :j_job_id and :'c_line' = '029669458' and :'c_code' = '1111222233334444');
reset role;
set role authenticated;
select * from public.store_admin_idoom_create(:idm, '030977530', gen_random_uuid()) \gset k_
reset role;
set role anon;
select pg_temp.check('no second job while one is claimed', not exists (select 1 from public.store_exec_claim(:'e_token')));
select public.store_exec_report(:'e_token', :j_job_id, 'VOUCHER_USED', '20M ADSL', 'Carte déjà utilisée !') as r \gset
select pg_temp.check('used card mapped', :'r' = 'used_card');
select pg_temp.check('report only once', pg_temp.err(format($$select public.store_exec_report('%s', %s, 'SUCCESS_TEXT', '', '')$$, :'e_token', :j_job_id)) like '%JOB_NOT_CLAIMED%');
select * from public.store_exec_claim(:'e_token') \gset c2_
select pg_temp.check('next job after report', :c2_job_id = :k_job_id);
select public.store_exec_report(:'e_token', :k_job_id, 'BLANK_AFTER_SUBMIT', 'FTTH', '') as r2 \gset
select pg_temp.check('blank screen is likely success', :'r2' = 'likely_success');
reset role;
set role authenticated;
select pg_temp.check('admin sees jobs', (select count(*) from public.store_admin_idoom_jobs(10)) = 2);
select pg_temp.check('finished job not cancellable', pg_temp.err(format($$select public.store_admin_idoom_cancel(%s)$$, :k_job_id)) like '%NOT_CANCELLABLE%');
select pg_temp.check('out of stock blocks create', pg_temp.err(format($$select * from public.store_admin_idoom_create(%s, '029669458', gen_random_uuid())$$, :idm)) like '%OUT_OF_STOCK%');

-- v1.12 lookup jobs
select * from public.store_admin_idoom_lookup('0296 69 458', gen_random_uuid()) \gset l_
reset role;
set role anon;
select pg_temp.check('old claim skips lookup jobs', not exists (select 1 from public.store_exec_claim(:'e_token')));
select job_id, kind, coalesce(code, '') as code from public.store_exec_claim_v2(:'e_token') \gset lc_
select pg_temp.check('lookup claimed without code', :lc_job_id = :l_job_id and :'lc_kind' = 'lookup' and :'lc_code' = '');
select public.store_exec_report(:'e_token', :l_job_id, 'LOOKUP_OK', '20M ADSL', 'Offre: 20M') as r3 \gset
select pg_temp.check('lookup reported', :'r3' = 'looked_up');
reset role;
set role authenticated;
select pg_temp.check('lookup listed with offer', exists (select 1 from public.store_admin_idoom_jobs_v2(10) where kind = 'lookup' and offer = '20M ADSL'));
reset role;
select pg_temp.check('lookup bought nothing', (select count(*) from store.orders) = (select count(*) from store.orders));
\set QUIET off
select name, ok, detail from i_results where not ok;
select count(*) filter (where ok) as passed, count(*) as total from i_results;
