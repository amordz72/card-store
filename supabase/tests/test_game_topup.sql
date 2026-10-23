-- Behavioural tests for v1.25 (game top-up by player id). Run after all migrations and the other tests.
\set ON_ERROR_STOP on
\set QUIET on
create temp table g_results (name text, ok boolean, detail text);
grant all on g_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into g_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

select id as shop from store.customers where is_shop \gset

-- ===== owner: a Garena card with 4 codes, a plain card, two customers, a worker =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'Garena G', 'game', 9, true) \g /dev/null
select brand_id as gb from public.store_admin_brands() where name = 'Garena G' \gset
select public.store_admin_save_product(null, :gb, '100 جوهرة', 250, 1, true) as p100 \gset
select public.store_admin_save_product(null, :gb, '210 جوهرة', 500, 2, true) as p210 \gset
select added from public.store_admin_add_codes(:p100, null, 200, E'G-0001\nG-0002\nG-0003\nG-0004') \g /dev/null
select added from public.store_admin_add_codes(:p210, null, 400, E'H-0001') \g /dev/null
select public.store_admin_create_customer('زبون لعبة', '0779000251', 'secret123') as cu \gset
select public.store_admin_create_customer('زبون آخر', '0779000252', 'secret123') as cu2 \gset
select public.store_admin_create_customer('عامل الشحن', '0779000253', 'secret123') as wk \gset
select entry_id from public.store_admin_transfer(:cu, 'cash', 1000, null, gen_random_uuid()) \g /dev/null
select entry_id from public.store_admin_transfer(:cu2, 'cash', 1000, null, gen_random_uuid()) \g /dev/null
select public.store_admin_set_player_topup(:p100, true) \g /dev/null
select pg_temp.check('marked list', array(select public.store_admin_player_topup_products()) = array[:p100]::bigint[]);
select public.store_admin_set_game_operator(:wk, true) \g /dev/null
select pg_temp.check('shop account cannot be a worker', pg_temp.err(format('select public.store_admin_set_game_operator(%s, true)', :shop)) like '%CUSTOMER_NOT_FOUND%');
select pg_temp.check('worker list', array(select public.store_admin_game_operators()) = array[:wk]::bigint[]);
reset role;

select set_config('request.jwt.claim.sub', '', false);
set role anon;
select session_token as tok from public.store_login('0779000251', 'secret123') \gset
select session_token as tok2 from public.store_login('0779000252', 'secret123') \gset
select session_token as wtok from public.store_login('0779000253', 'secret123') \gset
select pg_temp.check('marked card still in the store', exists (select 1 from public.store_catalog_v2(:'tok') where product_id = :p100 and available));
select pg_temp.check('top-up cards', array(select public.store_game_cards(:'tok')) = array[:p100]::bigint[]);
select pg_temp.check('closed at first', (select not is_open and not is_operator from public.store_game_status(:'tok')));
select pg_temp.check('closed refuses', pg_temp.err(format($$select * from public.store_game_create(%L, %s, '8743900001', gen_random_uuid())$$, :'tok', :p100)) like '%GAME_CLOSED%');
select pg_temp.check('unmarked card refused', pg_temp.err(format($$select * from public.store_game_create(%L, %s, '8743900001', gen_random_uuid())$$, :'tok', :p210)) like '%NOT_GAME_CARD%');
select pg_temp.check('customer is not an operator', pg_temp.err(format('select public.store_game_presence(%L, true)', :'tok')) like '%NOT_OPERATOR%');
select pg_temp.check('anon without token is not the owner', pg_temp.err('select public.store_game_presence(null, true)') like '%NOT_ADMIN%');
select pg_temp.check('customer cannot read the queue', pg_temp.err(format('select * from public.store_game_queue(%L, true, 10, 0)', :'tok')) like '%NOT_OPERATOR%');
select pg_temp.check('anon cannot mark cards', pg_temp.err(format('select public.store_admin_set_player_topup(%s, true)', :p210)) like '%permission denied%');
-- the worker presses «متاح»
select pg_temp.check('worker status', (select is_operator from public.store_game_status(:'wtok')));
select pg_temp.check('worker available', public.store_game_presence(:'wtok', true));
select pg_temp.check('open now', (select is_open from public.store_game_status(:'tok')));
select pg_temp.check('board names', (select available_names = array['عامل الشحن'] and me_available from public.store_game_board(:'wtok')));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin cannot mark cards', pg_temp.err(format('select public.store_admin_set_player_topup(%s, true)', :p210)) like '%NOT_ADMIN%');
select pg_temp.check('non-admin session is not an operator', pg_temp.err('select * from public.store_game_queue(null, true, 10, 0)') like '%NOT_ADMIN%');
reset role;

-- ===== customer orders =====
set role anon;
select pg_temp.check('bad player id', pg_temp.err(format($$select * from public.store_game_create(%L, %s, '12ab', gen_random_uuid())$$, :'tok', :p100)) like '%INVALID_PLAYER_ID%');
select * from public.store_game_create(:'tok', :p100, ' 8743 900001 ', 'aaaaaaaa-0000-0000-0000-000000000001') \gset g1_
select pg_temp.check('order queued', :'g1_status' = 'queued');
select pg_temp.check('id cleaned', (select player_id from public.store_game_orders(:'tok', 10, 0) where game_id = :g1_game_id) = '8743900001');
select pg_temp.check('charged once at the card price', (select balance from public.store_me(:'tok')) = 750);
select * from public.store_game_create(:'tok', :p100, '8743900001', 'aaaaaaaa-0000-0000-0000-000000000001') \gset g1b_
select pg_temp.check('same request id = same order', :g1b_game_id = :g1_game_id and (select balance from public.store_me(:'tok')) = 750);
select pg_temp.check('same player busy', pg_temp.err(format($$select * from public.store_game_create(%L, %s, '8743900001', gen_random_uuid())$$, :'tok', :p100)) like '%GAME_PLAYER_BUSY%');
select pg_temp.check('other customer cannot reuse request id', pg_temp.err(format($$select * from public.store_game_create(%L, %s, '8743900009', 'aaaaaaaa-0000-0000-0000-000000000001')$$, :'tok2', :p100)) like '%REQUEST_ID_CONFLICT%');
reset role;
select order_id as g1_order from store.game_orders where id = :g1_game_id \gset
select code_id as g1_card from store.game_orders where id = :g1_game_id \gset
select pg_temp.check('purchase has its own request id', (select request_id <> 'aaaaaaaa-0000-0000-0000-000000000001'::uuid from store.orders where id = :g1_order));
set role anon;
select pg_temp.check('code hidden in operation dialog', (select string_agg(code, ',') from public.store_order_codes_v2(:'tok', :g1_order)) = 'شحن بمعرّف اللاعب 8743900001');
select pg_temp.check('code hidden in old dialog', (select string_agg(code, ',') from public.store_order_codes(:'tok', :g1_order)) not like '%G-000%');
select pg_temp.check('card not reportable', pg_temp.err(format($$select public.store_report_code(%L, %s, 'used', null)$$, :'tok', :g1_card)) <> 'NO_ERROR');
-- cancel while waiting: refund, card back
select pg_temp.check('other customer cannot cancel', pg_temp.err(format('select public.store_game_cancel(%L, %s)', :'tok2', :g1_game_id)) like '%NOT_CANCELLABLE%');
select pg_temp.check('cancel while waiting', public.store_game_cancel(:'tok', :g1_game_id) = 'cancelled');
reset role;
select pg_temp.check('cancel refunds and returns the card', (select balance from store.customers where id = :cu) = 1000
  and (select count(*) from store.codes where product_id = :p100 and status = 'available') = 4);
select pg_temp.check('refunded once', (select count(*) from store.wallet_entries where order_id = :g1_order and kind = 'purchase_refund') = 1);

-- ===== worker takes, finishes; owner sees =====
set role anon;
select * from public.store_game_create(:'tok', :p100, '8743900002', gen_random_uuid()) \gset g2_
select * from public.store_game_create(:'tok', :p100, '8743900003', gen_random_uuid()) \gset g3_
select pg_temp.check('bell counts waiting', public.store_game_open_count(:'wtok') = 2);
select pg_temp.check('queue oldest first, no code before taking', (select array_agg(game_id order by 1) = array[:g2_game_id, :g3_game_id]::bigint[] and bool_and(code is null)
  from public.store_game_queue(:'wtok', true, 10, 0)));
select pg_temp.check('take', public.store_game_claim(:'wtok', :g2_game_id, true) = 'claimed');
select pg_temp.check('code shown to the taker', (select code like 'G-000%' and mine from public.store_game_queue(:'wtok', true, 10, 0) where game_id = :g2_game_id));
select pg_temp.check('take twice refused', pg_temp.err(format('select public.store_game_claim(%L, %s, true)', :'wtok', :g2_game_id)) like '%GAME_NOT_OPEN%');
select pg_temp.check('customer cannot cancel once taken', pg_temp.err(format('select public.store_game_cancel(%L, %s)', :'tok', :g2_game_id)) like '%NOT_CANCELLABLE%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('owner sees who took it, not the code', (select taken_by = 'عامل الشحن' and code is null and not mine from public.store_game_queue(null, true, 10, 0) where game_id = :g2_game_id));
select pg_temp.check('owner available too', public.store_game_presence(null, true));
select pg_temp.check('owner takes the other', public.store_game_claim(null, :g3_game_id, true) = 'claimed');
reset role;
select order_id as g2_order from store.game_orders where id = :g2_game_id \gset
select code_id as g2_card from store.game_orders where id = :g2_game_id \gset
select code_id as g3_card from store.game_orders where id = :g3_game_id \gset
set role anon;
select pg_temp.check('worker cannot finish the owner''s order', pg_temp.err(format($$select public.store_game_finish(%L, %s, 'done', null, null, null)$$, :'wtok', :g3_game_id)) like '%GAME_NOT_OPEN%');
select pg_temp.check('used card → next card', public.store_game_finish(:'wtok', :g2_game_id, 'used_card', null, null, null) = 'claimed');
reset role;
select pg_temp.check('used card voided, another card on the order', (select status = 'void' from store.codes where id = :g2_card)
  and (select code_id <> :g2_card and cards_used = 1 from store.game_orders where id = :g2_game_id));
set role anon;
select pg_temp.check('done with txn', public.store_game_finish(:'wtok', :g2_game_id, 'done', ' 605261762771722 ', null, null) = 'done');
select pg_temp.check('finish twice refused', pg_temp.err(format($$select public.store_game_finish(%L, %s, 'failed', null, null, true)$$, :'wtok', :g2_game_id)) like '%GAME_NOT_OPEN%');
select pg_temp.check('customer sees txn', (select txn_ref = '605261762771722' and status = 'done' from public.store_game_orders(:'tok', 10, 0) where game_id = :g2_game_id));
select pg_temp.check('dialog shows done', (select serial from public.store_order_codes_v2(:'tok', :g2_order)) like 'تم الشحن%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('not done, card not used → back to stock', public.store_game_finish(null, :g3_game_id, 'failed', null, 'معرّف خاطئ', true) = 'failed');
select pg_temp.check('finished list has reason', (select reason from public.store_game_queue(null, false, 10, 0) where game_id = :g3_game_id) = 'معرّف خاطئ');
select pg_temp.check('bad result refused', pg_temp.err(format($$select public.store_game_finish(null, %s, 'maybe', null, null, null)$$, :g2_game_id)) like '%GAME_NOT_OPEN%');
reset role;
select pg_temp.check('card back in stock', (select status = 'available' and order_id is null from store.codes where id = :g3_card));
select pg_temp.check('balance: one charged', (select balance from store.customers where id = :cu) = 750);
set role anon;
select pg_temp.check('recent ids, newest first, cancelled skipped', array(select public.store_game_recent_ids(:'tok')) = array['8743900003', '8743900002']);
reset role;

-- ===== used card with no other card: refund =====
update store.codes set frozen = true where product_id = :p100 and status = 'available' and id <> (select min(id) from store.codes where product_id = :p100 and status = 'available');
set role anon;
select * from public.store_game_create(:'tok2', :p100, '18095470001', gen_random_uuid()) \gset g4_
select public.store_game_claim(:'wtok', :g4_game_id, true) \g /dev/null
select pg_temp.check('used card, no other card → failed and refunded', public.store_game_finish(:'wtok', :g4_game_id, 'used_card', null, null, null) = 'failed'
  and (select balance from public.store_me(:'tok2')) = 1000);
select pg_temp.check('out of stock refuses', pg_temp.err(format($$select * from public.store_game_create(%L, %s, '18095470002', gen_random_uuid())$$, :'tok2', :p100)) like '%OUT_OF_STOCK%');
reset role;
update store.codes set frozen = false where product_id = :p100;

-- ===== the switch, limits =====
set role anon;
select pg_temp.check('worker off', not public.store_game_presence(:'wtok', false));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_game_presence(null, false) \g /dev/null
reset role;
set role anon;
select pg_temp.check('closed again', (select not is_open from public.store_game_status(:'tok')));
select public.store_game_presence(:'wtok', true) \g /dev/null
reset role;
update store.game_presence set last_seen_at = now() - interval '31 minutes';
set role anon;
select pg_temp.check('forgotten «متاح» expires after 30 minutes', (select not is_open from public.store_game_status(:'tok')));
select pg_temp.check('a ping keeps it', public.store_game_presence(:'wtok', null) and (select is_open from public.store_game_status(:'tok')));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_set_game_operator(:wk, false) \g /dev/null
reset role;
set role anon;
select pg_temp.check('removed worker: closed and refused', (select not is_open from public.store_game_status(:'tok'))
  and pg_temp.err(format('select public.store_game_presence(%L, true)', :'wtok')) like '%NOT_OPERATOR%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_game_presence(null, true) \g /dev/null
select public.store_admin_set_game_url('https://example.com/topup') \g /dev/null
select pg_temp.check('url on the board', (select url from public.store_game_board(null)) = 'https://example.com/topup');
select pg_temp.check('bad url refused', pg_temp.err($$select public.store_admin_set_game_url('http://x')$$) like '%INVALID_LINK%');
reset role;
update store.customers set balance = 10 where id = :cu2;
set role anon;
select pg_temp.check('insufficient balance, no order', pg_temp.err(format($$select * from public.store_game_create(%L, %s, '18095470003', gen_random_uuid())$$, :'tok2', :p100)) like '%INSUFFICIENT_BALANCE%'
  and not exists (select 1 from public.store_game_orders(:'tok2', 100, 0) where player_id = '18095470003'));
select pg_temp.check('bad token', pg_temp.err($$select * from public.store_game_status('nope')$$) like '%INVALID_SESSION%');
reset role;
update store.customers set balance = (select coalesce(sum(d_balance), 0) from store.wallet_entries where customer_id = :cu2) where id = :cu2;
select pg_temp.check('ledger matches the balance', (select balance from store.customers where id = :cu) = (select sum(d_balance) from store.wallet_entries where customer_id = :cu));

\set QUIET off
select ok, count(*) from g_results group by ok;
select name, detail from g_results where not ok;
