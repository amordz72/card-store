-- Behavioural tests for s172 (the owner picks the batch of an Idoom card or a fed card). Run after s172.
\set ON_ERROR_STOP on
\set QUIET on
create temp table k_results (name text, ok boolean, detail text);
grant all on k_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into k_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin execute sqltext; return 'NO_ERROR'; exception when others then return sqlerrm; end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'IDOOM s172', 'net', 5, true) \g /dev/null
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'IDOOM s172'), 'IDOOM ADSL 500', 500, 1, true) as idm \gset
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Mobilis'), 'Mobilis 2000', 2000, 1, true) as mob \gset
select batch_id as ia from public.store_admin_add_codes(:idm, null, 450, E'S172-IA-1\nS172-IA-2') \gset
select batch_id as ib from public.store_admin_add_codes(:idm, null, 460, E'S172-IB-1') \gset
select batch_id as ma from public.store_admin_add_codes(:mob, null, 1900, E'72000000000000001') \gset
select batch_id as mb from public.store_admin_add_codes(:mob, null, 1900, E'72000000000000002') \gset
select * from public.store_admin_shop_topup(10000, 's172', gen_random_uuid()) \g /dev/null
select pg_temp.check('batches for the product: both, with their counts',
  (select jsonb_array_length(x) = 2 and (x->0->>'n')::int = 2 and (x->1->>'n')::int = 1 and x->0->>'code' is not null
     from (select public.store_admin_batches_for_product(:idm, false) as x) y));
select job_id as j from public.store_admin_idoom_create_from_batch(:idm, '029669458', gen_random_uuid(), :ib, false) \gset
reset role;
select pg_temp.check('idoom from the chosen batch (not the oldest)',
  (select k.batch_id = :ib and k.status = 'sold' and j.code_id is not null and not j.from_suspect
     from store.idoom_jobs j join store.codes k on k.id = j.code_id where j.id = :j));
select pg_temp.check('charged at the card cost', (select charged_amount = 460 from store.orders o join store.idoom_jobs j on j.order_id = o.id where j.id = :j));
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('an empty batch is refused',
  pg_temp.err('select * from public.store_admin_idoom_create_from_batch(' || :idm || ', ''029669458'', gen_random_uuid(), ' || :ib || ', false)') like '%BATCH_EMPTY%');
select pg_temp.check('batches for a feeding value', (select jsonb_array_length(public.store_admin_batches_for_face(2000, false)) = 2));
reset role;
select private.store_feed_take_v3(2000, 'sama-x', false, :mb) as f \gset
select pg_temp.check('feed from the chosen batch (not the oldest)', (:'f'::jsonb->>'batch_id')::bigint = :mb);
select pg_temp.check('feed without a batch: the oldest', (private.store_feed_take_v3(2000, 'sama-x', false, null)->>'batch_id')::bigint = :ma);
select name, ok, detail from k_results order by ok, name;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from k_results;
