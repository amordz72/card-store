-- Behavioural tests for s170 (feed and Idoom from suspect cards; verdicts count in the batch). Run after s170.
\set ON_ERROR_STOP on
\set QUIET on
create temp table v_results (name text, ok boolean, detail text);
grant all on v_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into v_results values (n, coalesce(cond, false), d);
$$;
grant execute on all functions in schema pg_temp to anon, authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'IDOOM s170', 'net', 5, true) \g /dev/null
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'IDOOM s170'), 'IDOOM ADSL 500', 500, 1, true) as idm \gset
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Mobilis'), 'Mobilis 1000', 1000, 1, true) as mob \gset
reset role;
select id as oldsup from store.suppliers where name = 'مخزون قديم · مشكوك فيها' \gset
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select batch_id as ib from public.store_admin_add_codes(:idm, :oldsup, 450, E'S170-I-1111222233\nS170-I-4444555566\nS170-I-7777888899') \gset
select batch_id as mb from public.store_admin_add_codes(:mob, :oldsup, 950, E'11112222333344445\n55556666777788889') \gset
select batch_id as mn from public.store_admin_add_codes(:mob, null, 950, E'99990000111122223') \gset
select * from public.store_admin_shop_topup(10000, 's170', gen_random_uuid()) \g /dev/null
select * from public.store_admin_executor_create('هاتف s170') \gset e_
-- Idoom from a suspect card
select job_id as j1 from public.store_admin_idoom_create_suspect(:idm, '029669458', gen_random_uuid()) \gset
reset role;
select pg_temp.check('idoom: job queued with a suspect card and its order',
  (select status = 'queued' and from_suspect and code_id is not null and order_id is not null and kind = 'charge' from store.idoom_jobs where id = :j1));
select pg_temp.check('idoom: the card is a suspect one of the batch',
  (select k.batch_id = :ib and k.suspect and k.status = 'sold' from store.idoom_jobs j join store.codes k on k.id = j.code_id where j.id = :j1));
set role anon;
select job_id as cj from public.store_exec_claim_v2(:'e_token') \gset
select public.store_exec_take_code(:'e_token', :cj, null) as code1 \gset
select public.store_exec_report(:'e_token', :cj, 'VOUCHER_USED', null, 'used') \g /dev/null
reset role;
select pg_temp.check('idoom: the phone gets that suspect card', :'code1' like 'S170-I-%');
select pg_temp.check('idoom: a used card is marked bad', (select bad = 'used' from store.codes where code = :'code1'));
-- second used card of the same batch → the rest of the batch stays suspect, alert
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select job_id as j2 from public.store_admin_idoom_create_suspect(:idm, '029669458', gen_random_uuid()) \gset
reset role;
set role anon;
select job_id as cj2 from public.store_exec_claim_v2(:'e_token') \gset
select public.store_exec_take_code(:'e_token', :cj2, null) \g /dev/null
select public.store_exec_report(:'e_token', :cj2, 'VOUCHER_USED', null, 'used') \g /dev/null
reset role;
select pg_temp.check('two used: batch alert', (select bad_count >= 2 from store.batch_alerts where batch_id = :ib));
-- feeding: suspect take only from suspect cards (a revealed one allowed); ordinary never takes a suspect one
insert into store.code_reveals (code_id, admin_id) select id, '60e166af-1366-47cc-81f9-791a4585c66e' from store.codes where batch_id = :mb;
select private.store_feed_take_v2(1000, 'sama-test', true) as f1 \gset
select pg_temp.check('feed suspect: a suspect card (revealed is fine)', (:'f1'::jsonb->>'batch_id')::bigint = :mb and (:'f1'::jsonb->>'from_suspect')::boolean);
select private.store_feed_take_v2(1000, 'sama-test', false) as f2 \gset
select pg_temp.check('feed ordinary: the normal card, never a suspect one', (:'f2'::jsonb->>'batch_id')::bigint = :mn and not (:'f2'::jsonb->>'from_suspect')::boolean);
select pg_temp.check('feed ordinary: none left (suspect ones untouched)', private.store_feed_take_v2(1000, 'sama-test', false) is null);
-- a suspect fed card back to ready is taken again only by a suspect feeding
update store.feed_cards set state = 'ready' where id = (:'f1'::jsonb->>'card_id')::bigint;
select pg_temp.check('ready suspect card: not for ordinary feeding', private.store_feed_take_v2(1000, 'sama-test', false) is null);
select private.store_feed_take_v2(1000, 'sama-test', true) as f5 \gset
select pg_temp.check('ready suspect card: back for suspect feeding', (:'f5'::jsonb->>'card_id') = (:'f1'::jsonb->>'card_id'));
-- refused fed cards count in the batch
select private.store_feed_set((:'f5'::jsonb->>'card_id')::bigint, 'refused') \g /dev/null
select private.store_feed_take_v2(1000, 'sama-test', true) as f6 \gset
select private.store_feed_set((:'f6'::jsonb->>'card_id')::bigint, 'refused') \g /dev/null
select pg_temp.check('two refused fed cards: batch alert', (select bad_count >= 2 from store.batch_alerts where batch_id = :mb));
select pg_temp.check('revealed suspect card fed: voided, kept with its log',
  (select status = 'void' and void_reason = 'نُقلت إلى تغذية الشرائح' from store.codes where id = (:'f1'::jsonb->>'card_id')::bigint));
select name, ok, detail from v_results order by ok, name;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from v_results;
