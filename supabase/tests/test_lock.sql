-- Behavioural tests for v1.8 (device lock PIN). Run after the other suites.
\set ON_ERROR_STOP on
\set QUIET on
create temp table l_results (name text, ok boolean, detail text);
grant all on l_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into l_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- customer سمير (from test_pricing)
set role anon;
select session_token as tok from public.store_login('0770000010', 'secret123') \gset
select pg_temp.check('no pin yet', not public.store_lock_status(:'tok'));
select pg_temp.check('check without pin', public.store_check_pin(:'tok', '1234') = 'no_pin');
select pg_temp.check('pin must be 4-6 digits', pg_temp.err(format($$select public.store_set_pin(%L, '12a4')$$, :'tok')) like '%INVALID_PIN%');
select public.store_set_pin(:'tok', '2580');
select pg_temp.check('pin set', public.store_lock_status(:'tok'));
select pg_temp.check('right pin', public.store_check_pin(:'tok', '2580') = 'ok');
select pg_temp.check('wrong pin 1-4', (select bool_and(public.store_check_pin(:'tok', '0000') = 'wrong') from generate_series(1, 4)));
select pg_temp.check('right pin resets counter', public.store_check_pin(:'tok', '2580') = 'ok');
select pg_temp.check('4 wrong still wrong', (select bool_and(public.store_check_pin(:'tok', '0000') = 'wrong') from generate_series(1, 4)));
select pg_temp.check('5th wrong locks out', public.store_check_pin(:'tok', '0000') = 'locked_out');
select pg_temp.check('session revoked after lock-out', pg_temp.err(format($$select * from public.store_me(%L)$$, :'tok')) like '%INVALID_SESSION%');
reset role;
select pg_temp.check('pin stored hashed', (select pin_hash like '$2%' and pin_hash <> '2580' from store.lock_pins limit 1));
set role anon;
select pg_temp.check('anon cannot read pins', pg_temp.err($$select * from store.lock_pins$$) like '%permission denied%');
reset role;

-- owner
create temp table store_tmp_c as select id from store.customers where phone = '0770000010';
grant select on store_tmp_c to authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('owner no pin', not public.store_admin_lock_status());
select public.store_admin_set_pin('135790');
select pg_temp.check('owner pin ok', public.store_admin_check_pin('135790') = 'ok');
select pg_temp.check('owner pin wrong', public.store_admin_check_pin('111111') = 'wrong');
-- v1.9: owner turns a customer's lock off; the customer sets a PIN again; then turns it off himself
select pg_temp.check('owner turns customer lock off', public.store_admin_customer_lock_off((select id from store_tmp_c)));
select public.store_admin_lock_off();
select pg_temp.check('owner own lock off', not public.store_admin_lock_status());
reset role;
set role anon;
select session_token as tok2 from public.store_login('0770000010', 'secret123') \gset
select pg_temp.check('customer lock is off', not public.store_lock_status(:'tok2') and public.store_check_pin(:'tok2', '9999') = 'no_pin');
select public.store_set_pin(:'tok2', '1357');
select pg_temp.check('new pin turns it on', public.store_lock_status(:'tok2') and public.store_check_pin(:'tok2', '1357') = 'ok');
select public.store_lock_off(:'tok2');
select pg_temp.check('customer turns his lock off', not public.store_lock_status(:'tok2'));
reset role;
set role authenticated;
reset role;

\set QUIET off
select ok, count(*) from l_results group by ok;
select name, detail from l_results where not ok;
