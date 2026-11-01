-- Behavioural tests for s174 («Carte non existante» = a used card). Part A runs BEFORE s174 (makes a job in «مراجعة»),
-- part B after it: run with -v phase=a, apply s174, then -v phase=b.
\set ON_ERROR_STOP on
\set QUIET on
\if :{?phase}
\else
\set phase b
\endif
create table if not exists public.t174 (k text primary key, v text);
grant all on public.t174 to anon, authenticated;
create temp table v_results (name text, ok boolean, detail text);
grant all on v_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into v_results values (n, coalesce(cond, false), d);
$$;
grant execute on all functions in schema pg_temp to anon, authenticated;
select (:'phase' = 'a') as is_a \gset
\if :is_a
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'IDOOM s174', 'net', 5, true) \g /dev/null
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'IDOOM s174'), 'IDOOM ADSL 500', 500, 1, true) as idm \gset
select batch_id as ib from public.store_admin_add_codes(:idm, null, 450, E'S174-A-1111222233\nS174-B-4444555566\nS174-C-7777888899') \gset
select * from public.store_admin_shop_topup(10000, 's174', gen_random_uuid()) \g /dev/null
select * from public.store_admin_executor_create('هاتف s174') \gset e_
select job_id as j1 from public.store_admin_idoom_create(:idm, '029669458', gen_random_uuid()) \gset
reset role;
insert into public.t174 values ('token', :'e_token'), ('idm', :'idm'), ('j1', :'j1');
set role anon;
select job_id as cj from public.store_exec_claim_v2(:'e_token') \gset
select public.store_exec_take_code(:'e_token', :cj, null) \g /dev/null
select public.store_exec_report(:'e_token', :cj, 'UNKNOWN', null, 'Rechargement Internet | Carte non existante ! | Accéder à MY IDOOM') \g /dev/null
reset role;
select pg_temp.check('before s174: the job is in review', (select status = 'review' from store.idoom_jobs where id = :j1));
\else
select v as e_token from public.t174 where k = 'token' \gset
select v as idm from public.t174 where k = 'idm' \gset
select v as j1 from public.t174 where k = 'j1' \gset
select pg_temp.check('s174 closes the review job as a used card', (select status = 'used_card' and outcome = 'VOUCHER_USED' from store.idoom_jobs where id = :j1));
select pg_temp.check('its card is marked used', (select k.bad = 'used' from store.idoom_jobs j join store.codes k on k.id = j.code_id where j.id = :j1));
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select job_id as j2 from public.store_admin_idoom_create(:idm, '029669458', gen_random_uuid()) \gset
reset role;
set role anon;
select job_id as cj2 from public.store_exec_claim_v2(:'e_token') \gset
select public.store_exec_take_code(:'e_token', :cj2, null) \g /dev/null
select public.store_exec_report(:'e_token', :cj2, 'UNKNOWN', null, 'Carte non existante !') as st \gset
reset role;
select pg_temp.check('a new «Carte non existante» answer → used_card', :'st' = 'used_card');
select pg_temp.check('its card is marked used too', (select k.bad = 'used' from store.idoom_jobs j join store.codes k on k.id = j.code_id where j.id = :j2));
select pg_temp.check('two used in the batch → batch alert', exists (select 1 from store.batch_alerts a join store.codes k on k.batch_id = a.batch_id join store.idoom_jobs j on j.code_id = k.id where j.id = :j2));
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_add_codes(:idm, null, 450, E'S174-D-1212343456') \g /dev/null
select job_id as j3 from public.store_admin_idoom_create(:idm, '029669458', gen_random_uuid()) \gset
reset role;
set role anon;
select job_id as cj3 from public.store_exec_claim_v2(:'e_token') \gset
select public.store_exec_take_code(:'e_token', :cj3, null) \g /dev/null
select public.store_exec_report(:'e_token', :cj3, 'UNKNOWN', null, 'Erreur inconnue') as st3 \gset
reset role;
select pg_temp.check('another unknown answer still goes to review', :'st3' = 'review');
drop table public.t174;
\endif
select coalesce(string_agg(case when ok then 'PASS ' else 'FAIL ' end || name || ' ' || detail, E'\n' order by name), 'none') from v_results;
