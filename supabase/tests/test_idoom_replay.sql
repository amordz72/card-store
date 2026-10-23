-- Behavioural tests for v1.26 (a top-up card cannot be read back through store_buy). Run after all migrations and the other tests.
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

update store.idoom_jobs set status = 'cancelled' where status in ('queued', 'claimed');

-- ===== owner: an IDOOM card, a phone, a customer with the service =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'Idoom ADSL R', 'net', 8, true) \g /dev/null
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Idoom ADSL R'), 'ADSL 500', 500, 1, true) as adsl \gset
select added from public.store_admin_add_codes(:adsl, null, 450, E'R-0001\nR-0002\nR-0003\nR-0004\nR-0005\nR-0006') \g /dev/null
select public.store_admin_create_customer('زبون الإعادة', '0779000261', 'secret123') as cu \gset
select entry_id from public.store_admin_transfer(:cu, 'cash', 2000, null, gen_random_uuid()) \g /dev/null
select public.store_admin_set_idoom_topup(:cu, true) \g /dev/null
select * from public.store_admin_executor_create('هاتف الإعادة') \gset e_
reset role;
set role anon;
select session_token as tok from public.store_login('0779000261', 'secret123') \gset
select count(*) from public.store_exec_claim_v2(:'e_token') \g /dev/null

-- ===== the customer orders a top-up, then replays store_buy with the same request id =====
select gen_random_uuid() as rq \gset
select * from public.store_idoom_create(:'tok', :adsl, '029000261', :'rq') \gset j_
reset role;
select order_id as o1, code_id as k1 from store.idoom_jobs where id = :j_job_id \gset
select code as card from store.codes where id = :k1 \gset
set role anon;
select pg_temp.check('replay of the top-up request id is refused',
  pg_temp.err(format($$select * from public.store_buy(%L, %s, 1, %L)$$, :'tok', :adsl, :'rq')) like '%REQUEST_ID_CONFLICT%');
select pg_temp.check('no store_buy call returns the top-up card',
  coalesce((select codes::text from public.store_buy(:'tok', :adsl, 1, gen_random_uuid())), '') not like '%' || :'card' || '%');
reset role;
select pg_temp.check('the purchase has its own request id', (select request_id <> :'rq'::uuid from store.orders where id = :o1));
select pg_temp.check('one top-up order for the request', (select count(*) from store.idoom_jobs where request_id = :'rq') = 1);

-- ===== an order made before the fix (customer request id on the order) is protected too =====
select gen_random_uuid() as old_rq \gset
update store.orders set request_id = :'old_rq' where id = :o1;
set role anon;
select pg_temp.check('old top-up order: replay refused',
  pg_temp.err(format($$select * from public.store_buy(%L, %s, 1, %L)$$, :'tok', :adsl, :'old_rq')) like '%REQUEST_ID_CONFLICT%');

-- ===== an ordinary purchase is still idempotent and returns its own codes =====
select gen_random_uuid() as nrq \gset
select codes::text as c1 from public.store_buy(:'tok', :adsl, 1, :'nrq') \gset
select codes::text as c2 from public.store_buy(:'tok', :adsl, 1, :'nrq') \gset
select pg_temp.check('ordinary replay returns the same codes', :'c1' = :'c2' and :'c1' like '%R-000%');
select pg_temp.check('idempotent create still works', (select job_id from public.store_idoom_create(:'tok', :adsl, '029000261', :'rq')) = :j_job_id);
reset role;

\set QUIET off
select ok, count(*) from r_results group by ok;
select name, detail from r_results where not ok;
