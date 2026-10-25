-- Behavioural tests for v1.33 (Flexy for shops). Run after all migrations.
\set ON_ERROR_STOP on
\set QUIET on
create temp table c_results (name text, ok boolean, detail text);
grant all on c_results to anon, authenticated, service_role;
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
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
-- test only: let the checks below read the tables while acting as the service role
grant usage on schema store to service_role;
grant select on all tables in schema store to service_role;

-- ===== owner: two customers with money =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_create_customer('محل فليكسي', '0771000101', 'secret123') as cu \gset
select public.store_admin_create_customer('محل آخر', '0771000102', 'secret123') as cu2 \gset
select entry_id from public.store_admin_transfer(:cu, 'cash', 10000, null, gen_random_uuid()) \g /dev/null
select entry_id from public.store_admin_transfer(:cu2, 'cash', 10000, null, gen_random_uuid()) \g /dev/null
reset role;

select set_config('request.jwt.claim.sub', '', false);
set role anon;
select session_token as tok from public.store_login('0771000101', 'secret123') \gset
select session_token as tok2 from public.store_login('0771000102', 'secret123') \gset

-- ===== closed by default =====
select pg_temp.check('status: not enabled, closed', (select not enabled and not open and max_amount = 5000 and not offers
  from public.store_flexy_status(:'tok')));
select pg_temp.check('anon cannot create', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, null, gen_random_uuid())', :'tok', '630', '0661000001')) like 'permission denied%');
select pg_temp.check('anon cannot mark', pg_temp.err('select public.store_flexy_mark(1, ''success'', null)') like 'permission denied%');
select pg_temp.check('anon cannot read owner list', pg_temp.err('select * from public.store_admin_flexy_customers()') like 'permission denied%');
reset role;

set role service_role;
select pg_temp.check('service: not enabled', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, null, gen_random_uuid())', :'tok', '630', '0661000001')) = 'FLEXY_NOT_ENABLED');
reset role;

-- ===== owner enables one shop: defaults copied once =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_set_customer_flexy(:cu, true, null, null, null, null);
select pg_temp.check('enable copies defaults', (select enabled and rate_630 = 4 and rate_offer is null and max_amount = 5000 and role = 'trader'
  from public.store_admin_flexy_customers() where customer_id = :cu));
select public.store_admin_set_flexy_settings(null, 5, null, null);
select pg_temp.check('later default change leaves the shop', (select rate_630 = 4 from public.store_admin_flexy_customers() where customer_id = :cu));
select public.store_admin_set_customer_flexy(:cu, null, 'wholesale', 6.25, null, null);
select pg_temp.check('owner sets rate and role', (select rate_630 = 6.25 and role = 'wholesale' from public.store_admin_flexy_customers() where customer_id = :cu));
reset role;

set role service_role;
select pg_temp.check('enabled but closed', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, null, gen_random_uuid())', :'tok', '630', '0661000001')) = 'FLEXY_CLOSED');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_set_flexy_settings(true, null, null, null);
reset role;

-- ===== create: checks, charge, idempotency =====
set role service_role;
select pg_temp.check('not mobilis', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, null, gen_random_uuid())', :'tok', '630', '0551000001')) = 'FLEXY_PHONE_NOT_MOBILIS');
select pg_temp.check('above max', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 5001, null, null, gen_random_uuid())', :'tok', '630', '0661000001')) = 'FLEXY_AMOUNT_OUT_OF_RANGE');
select pg_temp.check('below 40', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 39, null, null, gen_random_uuid())', :'tok', '630', '0661000001')) = 'FLEXY_AMOUNT_OUT_OF_RANGE');
select pg_temp.check('offer without an offers rate', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 1000, null, %L, gen_random_uuid())', :'tok', 'offer', '0661000001', 'PixX 1000')) = 'FLEXY_RATE_MISSING');
select pg_temp.check('other shop not enabled', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, null, gen_random_uuid())', :'tok2', '630', '0661000009')) = 'FLEXY_NOT_ENABLED');

select gen_random_uuid() as rq1 \gset
select job_id as j1, core_key as k1, reused as r1 from public.store_flexy_create(:'tok', '630', '+213 661 00 00 01', 1000, null, null, :'rq1') \gset
select pg_temp.check('created, phone normalised', (select status = 'queued' and phone = '0661000001' and charged = 937
  from store.flexy_jobs where id = :j1));
select pg_temp.check('core key from request', :'k1' = 'cs_' || replace(:'rq1', '-', '') and not :'r1'::boolean);
select pg_temp.check('charged 937 (6.25%)', (select balance = 10000 - 937 from store.customers where id = :cu));
select job_id as j1b, reused as r1b from public.store_flexy_create(:'tok', '630', '0661000001', 1000, null, null, :'rq1') \gset
select pg_temp.check('replay: same job, no second charge', :j1b = :j1 and :'r1b'::boolean
  and (select balance = 10000 - 937 from store.customers where id = :cu));
select pg_temp.check('same phone busy', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 200, null, null, gen_random_uuid())', :'tok', '630', '0661000001')) = 'FLEXY_PHONE_BUSY');
select pg_temp.check('foreign request id', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, null, %L)', :'tok2', '630', '0661000001', :'rq1')) = 'REQUEST_ID_CONFLICT');

-- ===== verdicts =====
select public.store_flexy_mark(:j1, 'sent', null) \g /dev/null
select pg_temp.check('open jobs list', (select count(*) = 1 from public.store_flexy_open_jobs(null) where job_id = :j1 and status = 'sent'));
select pg_temp.check('sent cannot become not_sent', pg_temp.err(format('select public.store_flexy_mark(%s, %L, null)', :j1, 'not_sent')) = 'FLEXY_ALREADY_SENT');
select public.store_flexy_mark(:j1, 'success', 'credit transmis vers le 0661000001') \g /dev/null
select pg_temp.check('success keeps charge', (select balance = 10000 - 937 from store.customers where id = :cu)
  and (select status = 'success' and decided_by = 'core' and finished_at is not null from store.flexy_jobs where id = :j1));
select pg_temp.check('final stays final', public.store_flexy_mark(:j1, 'failed', null) = 'success'
  and (select balance = 10000 - 937 from store.customers where id = :cu));

select job_id as j2 from public.store_flexy_create(:'tok', '630', '0661000002', 400, null, null, gen_random_uuid()) \gset
select public.store_flexy_mark(:j2, 'failed', 'Vous n''avez pas suffisamment de crédit') \g /dev/null
select pg_temp.check('failed refunds once', (select balance = 10000 - 937 from store.customers where id = :cu)
  and (select count(*) = 1 from store.wallet_entries w where w.kind = 'flexy_refund'
         and w.reverses_id = (select entry_id from store.flexy_jobs where id = :j2)));
select public.store_flexy_mark(:j2, 'failed', null) \g /dev/null
select pg_temp.check('second failed: no second refund', (select balance = 10000 - 937 from store.customers where id = :cu));

select job_id as j3 from public.store_flexy_create(:'tok', '630', '0661000003', 200, null, null, gen_random_uuid()) \gset
select public.store_flexy_mark(:j3, 'not_sent', null) \g /dev/null
select pg_temp.check('not sent refunds', (select balance = 10000 - 937 from store.customers where id = :cu));

select job_id as j4 from public.store_flexy_create(:'tok', '630', '0661000004', 2000, null, null, gen_random_uuid()) \gset
select public.store_flexy_mark(:j4, 'sent', null) \g /dev/null
select public.store_flexy_mark(:j4, 'review', 'رد غير مفهوم') \g /dev/null
select pg_temp.check('review holds', (select balance = 10000 - 937 - 1875 from store.customers where id = :cu));
select pg_temp.check('review does not go back to sent', public.store_flexy_mark(:j4, 'sent', null) = 'review');

select job_id as j5 from public.store_flexy_create(:'tok', '630', '0661000005', 100, null, null, gen_random_uuid()) \gset
select public.store_flexy_mark(:j5, 'sent', null) \g /dev/null
select public.store_flexy_mark(:j5, 'review', null) \g /dev/null
reset role;

-- ===== owner decides reviews; a flexy entry cannot be reversed by hand =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('review count 2', public.store_admin_flexy_review_count() = 2);
select pg_temp.check('owner list shows charge', (select charged = 1875 and customer_name = 'محل فليكسي'
  from public.store_admin_flexy_jobs('review', 20, null) where job_id = :j4));
select pg_temp.check('owner: sent', public.store_admin_flexy_resolve(:j4, true) = 'success');
select pg_temp.check('owner: not sent', public.store_admin_flexy_resolve(:j5, false) = 'failed');
select pg_temp.check('not in review any more', pg_temp.err(format('select public.store_admin_flexy_resolve(%s, true)', :j5)) = 'NOT_IN_REVIEW');
reset role;
select entry_id as e4 from store.flexy_jobs where id = :j4 \gset
select pg_temp.check('owner not sent refunds', (select balance = 10000 - 937 - 1875 from store.customers where id = :cu));
set role authenticated;
select pg_temp.check('flexy entry not reversible by hand', pg_temp.err(format(
  'select * from public.store_admin_reverse(%s, null, gen_random_uuid())', :e4)) = 'NOT_REVERSIBLE');
reset role;

-- ===== the shop sees amounts, statuses and replies, never the charge =====
set role anon;
select pg_temp.check('shop list newest first', (select array_agg(job_id order by job_id desc) from public.store_flexy_jobs(:'tok', 10, null))
  = array[:j5, :j4, :j3, :j2, :j1]::bigint[]);
select pg_temp.check('shop list has the reply', (select network_reply like 'credit transmis%' from public.store_flexy_jobs(:'tok', 10, null) where job_id = :j1));
select pg_temp.check('shop list columns: no charge', (select count(*) = 0 from information_schema.routines r
  join information_schema.parameters p on p.specific_name = r.specific_name
  where r.routine_name = 'store_flexy_jobs' and p.parameter_mode = 'OUT' and p.parameter_name in ('charged', 'rate', 'role')));
select pg_temp.check('paging', (select count(*) = 2 from public.store_flexy_jobs(:'tok', 10, :j3)));
select pg_temp.check('other shop sees nothing', (select count(*) = 0 from public.store_flexy_jobs(:'tok2', 10, null)));
select pg_temp.check('status open now', (select enabled and open from public.store_flexy_status(:'tok')));
reset role;

-- ===== offers (v1.35): the price is the name's number; the open list says the kind =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_set_customer_flexy(:cu, true, 'trader', null, 5, null);
reset role;
set role service_role;
select pg_temp.check('offer: price must be the name''s number', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, %L, gen_random_uuid())', :'tok', 'offer', '0661000006', 'Sama Mix 2000')) = 'FLEXY_OFFER_INVALID');
select pg_temp.check('offer: a name is required', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, null, gen_random_uuid())', :'tok', 'offer', '0661000006')) = 'FLEXY_OFFER_INVALID');
select pg_temp.check('630 refuses an offer name', pg_temp.err(format(
  'select * from public.store_flexy_create(%L, %L, %L, 100, null, %L, gen_random_uuid())', :'tok', '630', '0661000006', 'Sama Mix 100')) = 'FLEXY_BAD_REQUEST');
select balance as b0 from store.customers where id = :cu \gset
select job_id as jo from public.store_flexy_create(:'tok', 'offer', '0661000006', 100, null, 'Sama Mix 100', gen_random_uuid()) \gset
select pg_temp.check('offer: charged at the offers rate (5%)', (select charged = 95 and kind = 'offer' and offer_label = 'Sama Mix 100'
  and offer_code = 'Sama Mix 100' from store.flexy_jobs where id = :jo)
  and (select balance = :b0 - 95 from store.customers where id = :cu));
select pg_temp.check('open list says kind and offer', (select kind = 'offer' and offer_label = 'Sama Mix 100'
  from public.store_flexy_open_jobs(null) where job_id = :jo));
reset role;

select name, detail from c_results where not ok;
select ok, count(*) from c_results group by ok;
