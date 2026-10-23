-- Behavioural tests for v1.27 (server-side «تم نسخها»). Run after all migrations and the other tests.
\set ON_ERROR_STOP on
\set QUIET on
create temp table y_results (name text, ok boolean, detail text);
grant all on y_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into y_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== owner: a product with codes, two customers with balance, shop balance =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_product(null, (select brand_id from public.store_admin_brands() where name = 'PUBG'), 'PUBG copy test', 500, 9, true) as cp \gset
select public.store_admin_set_price(null, :cp, 'fixed', 480);
select added from public.store_admin_add_codes(:cp, null, 450, E'CPY-1\nCPY-2\nCPY-3\nCPY-4\nCPY-5\nCPY-6') \g /dev/null
select public.store_admin_create_customer('ناسخ', '0770999101', 'secret123') as yc \gset
select public.store_admin_create_customer('غيره', '0770999102', 'secret123') as yc2 \gset
select entry_id from public.store_admin_transfer(:yc, 'cash', 5000, null, gen_random_uuid()) \g /dev/null
select entry_id from public.store_admin_shop_topup(5000, null, gen_random_uuid()) \g /dev/null
select order_id as sord from public.store_admin_shop_buy(:cp, 1, gen_random_uuid()) \gset
select code_id as sk from public.store_admin_order_codes(:sord) \gset

-- ===== customer buys 2 and copies =====
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select session_token as tok from public.store_login('0770999101', 'secret123') \gset
select session_token as tok2 from public.store_login('0770999102', 'secret123') \gset
select order_id as ord from public.store_buy(:'tok', :cp, 2, gen_random_uuid()) \gset
select min(code_id) as k1, max(code_id) as k2 from public.store_order_codes_v2(:'tok', :ord) \gset

select pg_temp.check('nothing copied yet', (select count(*) from public.store_order_copies(:'tok', :ord)) = 0);
select public.store_mark_copied(:'tok', :k1) as first1 \gset
select pg_temp.check('copy saved', (select copy_count = 1 and copied_at = :'first1' from public.store_order_copies(:'tok', :ord) where code_id = :k1));
select pg_temp.check('other card not marked', not exists (select 1 from public.store_order_copies(:'tok', :ord) where code_id = :k2));
select pg_temp.check('repeat copy keeps first time', public.store_mark_copied(:'tok', :k1) = :'first1');
select pg_temp.check('repeat copy counted', (select copy_count = 2 from public.store_order_copies(:'tok', :ord) where code_id = :k1));
select pg_temp.check('copy does not change sale status', (select status = 'sold' from public.store_order_codes_v2(:'tok', :ord) where code_id = :k1));
select pg_temp.check('copied card still reportable', (select can_report from public.store_order_codes_v2(:'tok', :ord) where code_id = :k1));

-- ===== isolation =====
select pg_temp.check('other customer cannot mark', pg_temp.err(format($$select public.store_mark_copied(%L, %s)$$, :'tok2', :k2)) like '%CODE_NOT_FOUND%');
select pg_temp.check('other customer cannot read copies', pg_temp.err(format($$select * from public.store_order_copies(%L, %s)$$, :'tok2', :ord)) like '%ORDER_NOT_FOUND%');
select pg_temp.check('customer cannot mark shop card', pg_temp.err(format($$select public.store_mark_copied(%L, %s)$$, :'tok', :sk)) like '%CODE_NOT_FOUND%');
select pg_temp.check('bad session', pg_temp.err(format($$select public.store_mark_copied('nope', %s)$$, :k2)) like '%INVALID_SESSION%');
select pg_temp.check('missing card', pg_temp.err(format($$select public.store_mark_copied(%L, -1)$$, :'tok')) like '%CODE_NOT_FOUND%');
select pg_temp.check('anon cannot read copies table', pg_temp.err($$select * from store.code_copies$$) like '%permission denied%');
select pg_temp.check('anon cannot call core helper', pg_temp.err(format($$select private.store_copy_mark(%s, %s)$$, :yc, :k2)) like '%permission denied%');
select pg_temp.check('anon cannot call admin mark', pg_temp.err(format($$select public.store_admin_mark_copied(%s)$$, :sk)) like '%permission denied%');
select pg_temp.check('anon cannot call admin read', pg_temp.err(format($$select * from public.store_admin_order_copies(%s)$$, :ord)) like '%permission denied%');
reset role;

-- ===== owner: shop cards only; reads any order =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('admin marks shop card', public.store_admin_mark_copied(:sk) is not null);
select pg_temp.check('admin sees shop copy', (select copy_count = 1 from public.store_admin_order_copies(:sord) where code_id = :sk));
select pg_temp.check('admin cannot mark customer card', pg_temp.err(format($$select public.store_admin_mark_copied(%s)$$, :k2)) like '%CODE_NOT_FOUND%');
select pg_temp.check('admin sees customer copy, read-only', (select count(*) = 1 from public.store_admin_order_copies(:ord)));
select pg_temp.check('customer codes still masked for admin', (select bool_and(masked_code like '****%') from public.store_admin_order_codes(:ord)));
select pg_temp.check('anon/authenticated cannot read copies table', pg_temp.err($$select * from store.code_copies$$) like '%permission denied%');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin blocked from admin mark', pg_temp.err(format($$select public.store_admin_mark_copied(%s)$$, :sk)) like '%NOT_ADMIN%');
select pg_temp.check('non-admin blocked from admin read', pg_temp.err(format($$select * from public.store_admin_order_copies(%s)$$, :ord)) like '%NOT_ADMIN%');
reset role;

-- ===== not copyable: top-up orders, refunded order =====
reset role;
update store.orders set idoom_line = '029000000' where id = :ord;
set role anon;
select pg_temp.check('IDOOM top-up card not copyable', pg_temp.err(format($$select public.store_mark_copied(%L, %s)$$, :'tok', :k2)) like '%NOT_COPYABLE%');
reset role;
update store.orders set idoom_line = null, player_id = '123456789' where id = :ord;
set role anon;
select pg_temp.check('game top-up card not copyable', pg_temp.err(format($$select public.store_mark_copied(%L, %s)$$, :'tok', :k2)) like '%NOT_COPYABLE%');
reset role;
update store.orders set player_id = null where id = :ord;

set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select entry_id from public.store_admin_reverse((select entry_id from public.store_admin_entries(:yc, 'purchase', null, null, 10, 0, null) limit 1), null, gen_random_uuid()) \g /dev/null
reset role;
set role anon;
select pg_temp.check('refunded card not copyable', pg_temp.err(format($$select public.store_mark_copied(%L, %s)$$, :'tok', :k2)) like '%NOT_COPYABLE%');
select pg_temp.check('earlier copy kept after refund', (select count(*) = 1 from public.store_order_copies(:'tok', :ord)));
reset role;

select pg_temp.check('no copy row for uncopied cards', (select count(*) from store.code_copies) = 2);

\set QUIET off
select ok, count(*) from y_results group by ok;
select name, detail from y_results where not ok;
