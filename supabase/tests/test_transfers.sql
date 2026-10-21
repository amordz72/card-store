-- Behavioural tests for v1.5 (transfers separate from purchases). Run after the other suites.
\set ON_ERROR_STOP on
\set QUIET on
create temp table x_results (name text, ok boolean, detail text);
grant all on x_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into x_results values (n, coalesce(cond, false), d);
$$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- customer سمير from test_pricing: 1 cash + 2 purchases
set role anon;
select session_token as tok from public.store_login('0770000010', 'secret123') \gset
select pg_temp.check('transfers exclude purchases', (select count(*) = 1 and bool_and(kind = 'cash') from public.store_transfers(:'tok', null, null, null, 10, 0)));
select pg_temp.check('kind filter', (select count(*) from public.store_transfers(:'tok', 'debt', null, null, 10, 0)) = 0);
select pg_temp.check('totals', (select total_count = 1 and total_amount = 10000 from public.store_transfers(:'tok', 'cash', current_date, current_date, 10, 0)));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('admin transfers kind', (select bool_and(kind not in ('purchase', 'purchase_refund')) and count(*) > 0 from public.store_admin_entries(null, 'transfers', null, null, 100, 0)));
select pg_temp.check('admin shop incoming', (select bool_and(kind like 'shop_topup%') from public.store_admin_entries(null, 'transfers', null, null, 100, 0, 'shop')));
reset role;

\set QUIET off
select ok, count(*) from x_results group by ok;
select name, detail from x_results where not ok;
