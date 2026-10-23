-- Behavioural tests for v1.28 (restore voided cards as «مشكوك فيها», use one by one). Run after all migrations and the other tests.
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

-- ===== owner: a product with one batch of 6, a DEMO product sharing a code, a customer, shop balance =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Mobilis'), 'Mobilis suspect test', 1000, 9, true) as sp \gset
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'Mobilis'), 'DEMO suspect test', 1000, 9, true) as dp \gset
select public.store_admin_set_price(null, :sp, 'fixed', 980);
select batch_id as sb from public.store_admin_add_codes(:sp, null, 950, E'SUS-1\nSUS-2\nSUS-3\nSUS-4\nSUS-5\nSUS-6') \gset
select batch_id as db from public.store_admin_add_codes(:dp, null, 950, E'SUS-1') \gset
select public.store_admin_create_customer('زبون عادي', '0770999201', 'secret123') as uc \gset
select entry_id from public.store_admin_transfer(:uc, 'cash', 10000, null, gen_random_uuid()) \g /dev/null
select entry_id from public.store_admin_shop_topup(10000, null, gen_random_uuid()) \g /dev/null

-- customer buys SUS-1 and the owner refunds it: a card that reached a buyer
reset role;
set role anon;
select session_token as tok from public.store_login('0770999201', 'secret123') \gset
select order_id as uord from public.store_buy(:'tok', :sp, 1, gen_random_uuid()) \gset
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select entry_id from public.store_admin_reverse((select entry_id from public.store_admin_entries(:uc, 'purchase', null, null, 10, 0, null) limit 1), null, gen_random_uuid()) \g /dev/null
reset role;
-- make sure the refunded card is void with its order (whatever reverse does to it), like a delivered card
update store.codes set status = 'void', void_reason = 'مسترجع' where order_id = :uord;

-- owner wrongly voids the rest of the batch (SUS-2..6) and the DEMO copy
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('void 5 in stock', public.store_admin_codes_void((select array_agg(code_id) from public.store_admin_batch_codes_v2(:sb) where status = 'available'), 'مستخدم') = 5);
select public.store_admin_codes_void((select array_agg(code_id) from public.store_admin_batch_codes_v2(:db)), 'تجربة') \g /dev/null

-- ===== restore by pasting the good ones =====
select pg_temp.check('reason required', pg_temp.err(format($$select * from public.store_admin_batch_restore(%s, 'SUS-2', '  ')$$, :sb)) like '%REASON_REQUIRED%');
select pg_temp.check('empty paste', pg_temp.err(format($$select * from public.store_admin_batch_restore(%s, E'\n  \n', 'x')$$, :sb)) like '%NO_CODES%');
select pg_temp.check('unknown batch', pg_temp.err($$select * from public.store_admin_batch_restore(-1, 'SUS-2', 'x')$$) like '%BATCH_NOT_FOUND%');
select * from public.store_admin_batch_restore(:sb, E'SUS-2\n SUS-3 ;serial\nSUS-4\nSUS-4\nSUS-1\nNOPE-9\n', 'صحيحة؛ أُلغيت خطأ') \gset r_
select pg_temp.check('restored 3 (dup ignored)', :r_restored = 3, :'r_restored');
select pg_temp.check('card that reached a buyer not restored', :r_not_void = 1, :'r_not_void');
select pg_temp.check('unknown code reported', :r_not_found = 1, :'r_not_found');
select pg_temp.check('restored = available + frozen + suspect', (select count(*) = 3 from public.store_admin_batch_codes_v2(:sb)
  where status = 'available' and frozen and suspect and restored_at is not null and void_reason is null));
select pg_temp.check('DEMO copy untouched', (select status = 'void' and not suspect from public.store_admin_batch_codes_v2(:db)));
select pg_temp.check('batch v2 counts', (select available = 0 and frozen = 0 and suspect = 3 and voided = 3 from public.store_admin_batches_v2(:sp, 10, 0)));
select pg_temp.check('suspect stock', (select suspect = 3 from public.store_admin_suspect_stock() where product_id = :sp));
select pg_temp.check('old batches read unchanged shape', (select frozen = 3 from public.store_admin_batches(:sp, 10, 0)));
reset role;
select pg_temp.check('restore logged with old reason', (select count(*) = 3 and bool_and(void_reason_before = 'مستخدم') from store.code_restores r
  join store.codes k on k.id = r.code_id where k.batch_id = :sb));
select pg_temp.check('restore log append-only', pg_temp.err('delete from store.code_restores') like '%APPEND_ONLY%');

-- ===== nobody else gets them =====
set role anon;
select pg_temp.check('customer cannot buy suspect', pg_temp.err(format($$select * from public.store_buy(%L, %s, 1, gen_random_uuid())$$, :'tok', :sp)) like '%OUT_OF_STOCK%');
select pg_temp.check('customer catalog: not available', (select not available from public.store_catalog_v2(:'tok') where product_id = :sp));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('normal shop buy skips suspect', pg_temp.err(format($$select * from public.store_admin_shop_buy(%s, 1, gen_random_uuid())$$, :sp)) like '%OUT_OF_STOCK%');
select pg_temp.check('unfreeze does not release suspect', public.store_admin_codes_freeze((select array_agg(code_id) from public.store_admin_batch_codes_v2(:sb)), false) = 0);
select pg_temp.check('still suspect after unfreeze', (select count(*) = 3 from public.store_admin_batch_codes_v2(:sb) where frozen and suspect));

-- ===== owner uses them one by one =====
reset role;
select balance as bal0 from store.customers where is_shop \gset
set role authenticated;
select * from public.store_admin_use_suspect(:sp, '44444444-4444-4444-4444-444444444444') \gset u_
select pg_temp.check('one card, full code', :u_qty = 1 and jsonb_array_length(:'u_codes'::jsonb) = 1 and (:'u_codes'::jsonb->0->>'code') = 'SUS-2');
select * from public.store_admin_use_suspect(:sp, '44444444-4444-4444-4444-444444444444') \gset u2_
select pg_temp.check('same request id = same card', :u2_order_id = :u_order_id);
reset role;
select pg_temp.check('charged at cost once', (select balance = :bal0 - 950 from store.customers where is_shop));
set role authenticated;
select pg_temp.check('in shop operations', exists (select 1 from public.store_admin_orders(null, null, null, null, null, 50, 0, 'shop') where order_id = :u_order_id));
select pg_temp.check('used card sold, not frozen', (select status = 'sold' and not frozen and suspect from public.store_admin_batch_codes_v2(:sb) where code_id = (:'u_codes'::jsonb->0->>'code_id')::bigint));
select pg_temp.check('2 suspect left', (select suspect = 2 from public.store_admin_suspect_stock() where product_id = :sp));

-- ===== manual move to normal =====
select pg_temp.check('set normal', public.store_admin_codes_set_suspect((select array_agg(code_id) from public.store_admin_batch_codes_v2(:sb) where suspect and status = 'available' and masked_code = '****US-3'), false) = 1);
reset role;
set role anon;
select pg_temp.check('normal card sells to customer again', (select (codes->0->>'code') = 'SUS-3' from public.store_buy(:'tok', :sp, 1, gen_random_uuid())));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('last suspect used', (select (codes->0->>'code') = 'SUS-4' from public.store_admin_use_suspect(:sp, gen_random_uuid())));
select pg_temp.check('none left', pg_temp.err(format($$select * from public.store_admin_use_suspect(%s, gen_random_uuid())$$, :sp)) like '%NO_SUSPECT_CARD%');
select pg_temp.check('suspect stock empty', not exists (select 1 from public.store_admin_suspect_stock() where product_id = :sp));
-- a card left void can be restored by id later, voided again, and restored again: never lost
select pg_temp.check('restore by id', public.store_admin_codes_restore((select array_agg(code_id) from public.store_admin_batch_codes_v2(:sb) where masked_code = '****US-5'), 'تحقق') = 1);
select pg_temp.check('void again', public.store_admin_codes_void((select array_agg(code_id) from public.store_admin_batch_codes_v2(:sb) where masked_code = '****US-5'), 'مستخدم') = 1);
select pg_temp.check('restore again', public.store_admin_codes_restore((select array_agg(code_id) from public.store_admin_batch_codes_v2(:sb) where masked_code = '****US-5'), 'تحقق') = 1);
select pg_temp.check('restore twice does nothing', public.store_admin_codes_restore((select array_agg(code_id) from public.store_admin_batch_codes_v2(:sb) where masked_code = '****US-5'), 'تحقق') = 0);
reset role;

-- ===== access =====
set role anon;
select pg_temp.check('anon cannot restore', pg_temp.err(format($$select * from public.store_admin_batch_restore(%s, 'SUS-6', 'x')$$, :sb)) like '%permission denied%');
select pg_temp.check('anon cannot use suspect', pg_temp.err(format($$select * from public.store_admin_use_suspect(%s, gen_random_uuid())$$, :sp)) like '%permission denied%');
select pg_temp.check('anon cannot call core helper', pg_temp.err($$select private.store_restore_codes(null, '{1}', 'x')$$) like '%permission denied%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin cannot restore', pg_temp.err(format($$select * from public.store_admin_batch_restore(%s, 'SUS-6', 'x')$$, :sb)) like '%NOT_ADMIN%');
select pg_temp.check('non-admin cannot use suspect', pg_temp.err(format($$select * from public.store_admin_use_suspect(%s, gen_random_uuid())$$, :sp)) like '%NOT_ADMIN%');
select pg_temp.check('non-admin cannot set suspect', pg_temp.err($$select public.store_admin_codes_set_suspect('{1}', false)$$) like '%NOT_ADMIN%');
select pg_temp.check('authenticated cannot call core helper', pg_temp.err($$select private.store_restore_codes(null, '{1}', 'x')$$) like '%permission denied%');
reset role;

\set QUIET off
select ok, count(*) from u_results group by ok;
select name, detail from u_results where not ok;
