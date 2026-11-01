-- Behavioural tests for s168 («العمليات» shows an Idoom top-up as one, with its line and state). Run after s168.
\set ON_ERROR_STOP on
\set QUIET on
create temp table o_results (name text, ok boolean, detail text);
grant all on o_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into o_results values (n, coalesce(cond, false), d);
$$;
grant execute on all functions in schema pg_temp to anon, authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'IDOOM s168', 'net', 5, true) \g /dev/null
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'IDOOM s168'), 'IDOOM s168 500', 500, 1, true) as idm \gset
select added from public.store_admin_add_codes(:idm, null, 480, E'S168-1111222233334444') \g /dev/null
select * from public.store_admin_shop_topup(5000, 's168', gen_random_uuid()) \g /dev/null
select * from public.store_admin_idoom_create(:idm, '029669458', gen_random_uuid()) \g /dev/null

select pg_temp.check('v2: the Idoom top-up is kind idoom with its line',
  exists (select 1 from public.store_admin_ops_v2('shop', null, null, null, null, null, 100, 0) where kind = 'idoom' and target = '029669458' and job_status = 'queued'));
select pg_temp.check('v2: found by its line',
  exists (select 1 from public.store_admin_ops_v2(null, null, null, null, null, '669458', 100, 0) where kind = 'idoom'));
select pg_temp.check('v2: plain cards stay kind card',
  not exists (select 1 from public.store_admin_ops_v2(null, null, null, null, null, null, 100, 0) where source = 'card' and kind is null));
select pg_temp.check('v2: every v1 row, plus top-ups waiting without an order',
  (select count(*) from public.store_admin_ops_v2(null, null, null, null, null, null, 100, 0)) = 1 + (select count(*) from public.store_admin_ops(null, null, null, null, null, null, 100, 0)));
reset role;
select name, ok, detail from o_results order by ok, name;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from o_results;
