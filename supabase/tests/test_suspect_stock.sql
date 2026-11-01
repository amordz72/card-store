-- Behavioural tests for s167 (suspect stock: four states, the 2-bad rule, the old-stock supplier, reveal and find).
-- Run after all migrations and the external scripts through s167.
\set ON_ERROR_STOP on
\set QUIET on
create temp table u_results (name text, ok boolean, detail text);
grant all on u_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into u_results values (n, coalesce(cond, false), d);
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
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Mobilis'), 'Mobilis s167 test', 1000, 9, true) as sp \gset
select public.store_admin_set_price(null, :sp, 'fixed', 980);
select batch_id as b1 from public.store_admin_add_codes(:sp, null, 950, E'S167-AAAA-1001\nS167-AAAA-1002\nS167-AAAA-1003\nS167-AAAA-1004') \gset
reset role;
select id as oldsup from store.suppliers where name = 'مخزون قديم · مشكوك فيها' \gset
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select batch_id as b2 from public.store_admin_add_codes(:sp, :oldsup, 950, E'S167-OLD-2001\nS167-OLD-2002') \gset
reset role;

select pg_temp.check('old-stock supplier exists and is suspect by default', (select suspect_default from store.suppliers where id = :oldsup));
select pg_temp.check('codes added under it come in suspect and frozen',
  (select bool_and(suspect and frozen) from store.codes where batch_id = :b2));
select pg_temp.check('a normal batch is not suspect', (select not bool_or(suspect) from store.codes where batch_id = :b1));
-- a batch moved to the old-stock supplier with «عدّل»: its stock becomes suspect
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select batch_id as b3 from public.store_admin_add_codes(:sp, null, 950, E'S167-MOV-3001\nS167-MOV-3002') \gset
select public.store_admin_batch_edit(:b3, :oldsup, null) \g /dev/null
reset role;
select pg_temp.check('moved to old stock: suspect', (select bool_and(suspect and frozen) from store.codes where batch_id = :b3));

set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
-- masked by default, whole on reveal (stock only), logged
select pg_temp.check('masked by default', (select bool_and(shown_code like '****%' and not full_shown) from public.store_admin_batch_codes_v3(:b1, false)));
select pg_temp.check('revealed whole', (select bool_and(shown_code like 'S167-AAAA-%' and full_shown) from public.store_admin_batch_codes_v3(:b1, true)));
reset role;
select pg_temp.check('reveal logged', (select count(*) = 4 from store.code_reveals r join store.codes k on k.id = r.code_id where k.batch_id = :b1));
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);

-- find: whole code shows it whole; last 4 finds it masked; too short refused
select pg_temp.check('find whole', (select shown_code = 'S167-AAAA-1003' and exact and batch_id = :b1 from public.store_admin_code_find('S167 AAAA 1003')));
select pg_temp.check('find by last 4', (select count(*) = 1 and bool_and(shown_code = '****1003') from public.store_admin_code_find('1003')));
select pg_temp.check('too short refused', pg_temp.err('select * from public.store_admin_code_find(''12'')') like '%CODE_TOO_SHORT%');

-- one bad code: voided as تالف, batch not yet suspect
select public.store_admin_codes_state(array[(select code_id from public.store_admin_code_find('S167-AAAA-1001'))], 'used') as n1 \gset
reset role;
select pg_temp.check('used: voided with its reason', (select status = 'void' and bad = 'used' and void_reason = 'تالف' from store.codes where code = 'S167-AAAA-1001'));
select pg_temp.check('one bad: the rest still on sale', (select count(*) = 3 from store.codes where batch_id = :b1 and status = 'available' and not suspect));
select pg_temp.check('one bad: no alert', (select count(*) = 0 from store.batch_alerts where batch_id = :b1));
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
-- second bad (return to supplier): the batch becomes suspect + alert
select public.store_admin_codes_state(array[(select code_id from public.store_admin_code_find('S167-AAAA-1002'))], 'return') \g /dev/null
reset role;
select pg_temp.check('return: its reason', (select bad = 'return' and void_reason = 'خاطئة — ترجع للمورّد' from store.codes where code = 'S167-AAAA-1002'));
select pg_temp.check('two bad: the rest is suspect', (select bool_and(suspect and frozen) from store.codes where batch_id = :b1 and status = 'available'));
select pg_temp.check('two bad: alert with 2 bad and 2 moved', (select bad_count = 2 and moved = 2 and seen_at is null from store.batch_alerts where batch_id = :b1));
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('alerts listed', (select jsonb_array_length(public.store_admin_batch_alerts()) = 1));
select pg_temp.check('extra: bad count and first code', (select bad = 2 and first_code = '****1001' from public.store_admin_batches_extra(array[:b1]::bigint[])));
select public.store_admin_batch_alerts_seen(null) \g /dev/null
select pg_temp.check('alert seen', (select jsonb_array_length(public.store_admin_batch_alerts()) = 0));
-- ok: a suspect code back on sale
select public.store_admin_codes_state(array[(select code_id from public.store_admin_code_find('S167-AAAA-1003'))], 'ok') \g /dev/null
reset role;
select pg_temp.check('ok: back on sale', (select status = 'available' and not suspect and not frozen from store.codes where code = 'S167-AAAA-1003'));
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('invalid state refused', pg_temp.err('select public.store_admin_codes_state(array[1]::bigint[], ''gone'')') like '%INVALID_VALUE%');
reset role;
set role anon;
select pg_temp.check('anon cannot find codes', pg_temp.err('select * from public.store_admin_code_find(''1003'')') <> 'NO_ERROR');
reset role;

select name, ok, detail from u_results order by ok, name;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from u_results;
