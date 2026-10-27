-- Behavioural tests for v1.39 (Free Fire top-up on the Rech-Doom phone). Run after all migrations and the other tests.
\set ON_ERROR_STOP on
\set QUIET on
create temp table p_results (name text, ok boolean, detail text);
grant all on p_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into p_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- nobody available from earlier suites; no IDOOM job waiting for phones
update store.game_presence set available = false;
update store.idoom_jobs set status = 'cancelled' where status in ('queued', 'claimed');

-- ===== owner: a Garena card with codes, a customer, a worker, a phone =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'Garena P', 'game', 10, true) \g /dev/null
select brand_id as gb from public.store_admin_brands() where name = 'Garena P' \gset
select public.store_admin_save_product(null, :gb, 'ف 100 جوهرة', 250, 1, true) as pp \gset
select added from public.store_admin_add_codes(:pp, null, 200, E'PH-00001\nPH-00002\nPH-00003\nPH-00004\nPH-00005\nPH-00006') \g /dev/null
select public.store_admin_set_player_topup(:pp, true) \g /dev/null
select public.store_admin_create_customer('زبون الهاتف', '0779000391', 'secret123') as cu \gset
select public.store_admin_create_customer('عامل الهاتف', '0779000392', 'secret123') as wk \gset
select entry_id from public.store_admin_transfer(:cu, 'cash', 3000, null, gen_random_uuid()) \g /dev/null
select public.store_admin_set_game_operator(:wk, true) \g /dev/null
select * from public.store_admin_executor_create('هاتف الألعاب') \gset e_
select * from public.store_admin_executor_create('هاتف آخر') \gset o_
select pg_temp.check('phone off for games by default', (select not game_enabled from public.store_admin_executors_v2() where id = :e_executor_id));
reset role;

set role anon;
select session_token as tok from public.store_login('0779000391', 'secret123') \gset
select session_token as wtok from public.store_login('0779000392', 'secret123') \gset
select pg_temp.check('phone not enabled gets nothing', not exists (select 1 from public.store_exec_game_claim(:'e_token')));
select pg_temp.check('closed while no game phone', (select not is_open from public.store_game_status(:'tok')));
select pg_temp.check('bad token', pg_temp.err($$select * from public.store_exec_game_claim('nope')$$) like '%INVALID_EXECUTOR%');
select pg_temp.check('anon cannot switch a phone', pg_temp.err(format('select public.store_admin_executor_set_game(%s, true)', :e_executor_id)) like '%permission denied%');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('switch on', public.store_admin_executor_set_game(:e_executor_id, true));
select pg_temp.check('listed on', (select game_enabled from public.store_admin_executors_v2() where id = :e_executor_id));
select pg_temp.check('unknown phone', pg_temp.err('select public.store_admin_executor_set_game(999999, true)') like '%PHONE_NOT_FOUND%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin cannot switch', pg_temp.err(format('select public.store_admin_executor_set_game(%s, false)', :e_executor_id)) like '%NOT_ADMIN%');
reset role;

-- ===== the phone receiving opens the service =====
set role anon;
select pg_temp.check('empty queue: nothing', not exists (select 1 from public.store_exec_game_claim(:'e_token')));
select pg_temp.check('open while the phone is seen', (select is_open from public.store_game_status(:'tok')));
select pg_temp.check('phone on the board', (select 'هاتف: هاتف الألعاب' = any(available_names) from public.store_game_board(:'wtok')));
reset role;
update store.executors set last_seen_at = now() - interval '3 minutes' where id = :e_executor_id;
set role anon;
select pg_temp.check('closed when the phone stops', (select not is_open from public.store_game_status(:'tok')));
select pg_temp.check('not on the board', not ((select 'هاتف: هاتف الألعاب' = any(available_names) from public.store_game_board(:'wtok'))));
select pg_temp.check('nothing yet', not exists (select 1 from public.store_exec_game_claim(:'e_token')));

-- ===== order 1: the phone stops before «تأكيد» → back to the queue for a person =====
select * from public.store_game_create(:'tok', :pp, '5500000001', gen_random_uuid()) \gset a_
select * from public.store_exec_game_claim(:'e_token') \gset ac_
select pg_temp.check('phone takes it with the card', :ac_game_id = :a_game_id and :'ac_player_id' = '5500000001' and :'ac_code' like 'PH-0000%');
select pg_temp.check('one at a time', not exists (select 1 from public.store_exec_game_claim(:'e_token')));
select pg_temp.check('busy phone gets no IDOOM job either', not exists (select 1 from public.store_exec_claim_v2(:'e_token')));
select pg_temp.check('customer cannot cancel', pg_temp.err(format('select public.store_game_cancel(%L, %s)', :'tok', :a_game_id)) like '%NOT_CANCELLABLE%');
select pg_temp.check('worker cannot take it', pg_temp.err(format('select public.store_game_claim(%L, %s, true)', :'wtok', :a_game_id)) like '%GAME_NOT_OPEN%');
select pg_temp.check('worker cannot finish it', pg_temp.err(format($$select public.store_game_finish(%L, %s, 'done', null, null, null)$$, :'wtok', :a_game_id)) like '%GAME_NOT_OPEN%');
select pg_temp.check('worker cannot give it back', pg_temp.err(format('select public.store_game_claim(%L, %s, false)', :'wtok', :a_game_id)) like '%PHONE_WORKING%');
select pg_temp.check('worker sees the phone took it, no code', (select taken_by = 'هاتف: هاتف الألعاب' and by_phone and auto_state = 'working' and code is null and not mine
  from public.store_game_queue_v2(:'wtok', true, 10, 0) where game_id = :a_game_id));
select pg_temp.check('another phone cannot report it', pg_temp.err(format($$select public.store_exec_game_report(%L, %s, 'sent', 'x', null)$$, :'o_token', :a_game_id)) like '%GAME_NOT_OPEN%');
select pg_temp.check('invalid outcome', pg_temp.err(format($$select public.store_exec_game_report(%L, %s, 'ok', 'x', null)$$, :'e_token', :a_game_id)) like '%INVALID_RESULT%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('owner cannot finish while the phone works', pg_temp.err(format($$select public.store_game_finish(null, %s, 'failed', null, null, true)$$, :a_game_id)) like '%PHONE_WORKING%');
select pg_temp.check('owner cannot give it back while the phone works', pg_temp.err(format('select public.store_game_claim(null, %s, false)', :a_game_id)) like '%PHONE_WORKING%');
select pg_temp.check('busy phone cannot be switched off', pg_temp.err(format('select public.store_admin_executor_set_active(%s, false)', :e_executor_id)) like '%PHONE_BUSY%');
reset role;
set role anon;
select pg_temp.check('not sent → queued', public.store_exec_game_report(:'e_token', :a_game_id, 'not_sent', 'لم يظهر اسم اللاعب ' || :'ac_code', null) = 'queued');
select pg_temp.check('report twice refused', pg_temp.err(format($$select public.store_exec_game_report(%L, %s, 'sent', 'x', null)$$, :'e_token', :a_game_id)) like '%GAME_NOT_OPEN%');
select pg_temp.check('the phone does not take it again', not exists (select 1 from public.store_exec_game_claim(:'e_token')));
select pg_temp.check('a person sees why, the code masked', (select status = 'queued' and taken_by is null and auto_note like 'الهاتف توقف قبل «تأكيد»%'
  and reply not like '%PH-0000%' and reply like '%****%' from public.store_game_queue_v2(:'wtok', true, 10, 0) where game_id = :a_game_id));
select pg_temp.check('the worker takes it by hand', public.store_game_claim(:'wtok', :a_game_id, true) = 'claimed');
select pg_temp.check('code shown to the worker', (select code = :'ac_code' and mine from public.store_game_queue_v2(:'wtok', true, 10, 0) where game_id = :a_game_id));
select pg_temp.check('worker finishes', public.store_game_finish(:'wtok', :a_game_id, 'done', 'T-1', null, null) = 'done');
reset role;
select pg_temp.check('card stayed sold once', (select count(*) from store.codes where id = (select code_id from store.game_orders where id = :a_game_id) and status = 'sold') = 1);

-- ===== order 2: sent, unknown reply → review; owner finishes =====
set role anon;
select * from public.store_game_create(:'tok', :pp, '5500000002', gen_random_uuid()) \gset b_
select * from public.store_exec_game_claim(:'e_token') \gset bc_
select pg_temp.check('takes the next order', :bc_game_id = :b_game_id);
select pg_temp.check('sent, no rule → review', public.store_exec_game_report(:'e_token', :b_game_id, 'sent', E'تم\n123456789 ' || :'bc_code', 'Rivoxa') = 'review');
select pg_temp.check('review stays with the phone', not exists (select 1 from public.store_exec_game_claim(:'e_token')));
select pg_temp.check('review visible with reply and name', (select status = 'claimed' and auto_state = 'review' and auto_note = 'رد غير معروف'
  and reply like '%123456789%' and reply not like '%PH-0000%' and player_name = 'Rivoxa' from public.store_game_queue_v2(:'wtok', true, 10, 0) where game_id = :b_game_id));
select pg_temp.check('worker cannot finish a review', pg_temp.err(format($$select public.store_game_finish(%L, %s, 'done', null, null, null)$$, :'wtok', :b_game_id)) like '%GAME_NOT_OPEN%');
reset role;
select pg_temp.check('customer charged once, no refund', (select count(*) from store.wallet_entries where order_id = (select order_id from store.game_orders where id = :b_game_id)) = 1);
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('owner sees the phone order without the code', (select by_phone and code is null and not mine from public.store_game_queue_v2(null, true, 10, 0) where game_id = :b_game_id));
select pg_temp.check('owner finishes the review', public.store_game_finish(null, :b_game_id, 'done', '123456789', null, null) = 'done');
reset role;
select pg_temp.check('done with the number', (select status = 'done' and txn_ref = '123456789' and auto_state is null from store.game_orders where id = :b_game_id));

-- ===== known replies (rules) =====
insert into store.game_reply_rules (pattern, outcome, txn_pattern, note) values
  ('تم الاسترداد بنجاح', 'done', 'رقم العملية[: ]*([0-9]+)', 'test'),
  ('مستعمل', 'used_card', null, 'test');
set role anon;
select * from public.store_game_create(:'tok', :pp, '5500000003', gen_random_uuid()) \gset c_
select * from public.store_exec_game_claim(:'e_token') \gset cc_
select pg_temp.check('known success → done', public.store_exec_game_report(:'e_token', :c_game_id, 'sent', 'تم الاسترداد بنجاح · رقم العملية: 998877', 'Rivoxa') = 'done');
reset role;
select pg_temp.check('done with the number from the reply', (select status = 'done' and txn_ref = '998877' and finished_at is not null from store.game_orders where id = :c_game_id));

set role anon;
select * from public.store_game_create(:'tok', :pp, '5500000004', gen_random_uuid()) \gset d_
select * from public.store_exec_game_claim(:'e_token') \gset dc_
select pg_temp.check('used card → back to the queue with the next card', public.store_exec_game_report(:'e_token', :d_game_id, 'sent', 'هذه البطاقة مستعملة', null) = 'queued');
reset role;
select pg_temp.check('first card voided', (select status = 'void' from store.codes where code = :'dc_code'));
select pg_temp.check('next card on the order', (select code_id is not null and cards_used = 1 and claimed_executor is null and not auto_skip from store.game_orders where id = :d_game_id));
set role anon;
select * from public.store_exec_game_claim(:'e_token') \gset dd_
select pg_temp.check('phone takes it again with another card', :dd_game_id = :d_game_id and :'dd_code' <> :'dc_code');
select pg_temp.check('unknown → review', public.store_exec_game_report(:'e_token', :d_game_id, 'unknown', '', null) = 'review');
select pg_temp.check('unknown note', (select auto_note = 'لا يُعرف هل ضُغط «تأكيد»' and reply is null from public.store_game_queue_v2(:'wtok', true, 10, 0) where game_id = :d_game_id));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('owner: not done, card back', public.store_game_finish(null, :d_game_id, 'failed', null, 'لم يتم', true) = 'failed');
reset role;
select pg_temp.check('refund once and card back', (select count(*) from store.wallet_entries where order_id = (select order_id from store.game_orders where id = :d_game_id) and kind = 'purchase_refund') = 1
  and (select status = 'available' from store.codes where code = :'dd_code'));

-- ===== the phone stopped answering: after 10 minutes the owner takes over =====
set role anon;
select * from public.store_game_create(:'tok', :pp, '5500000006', gen_random_uuid()) \gset h_
select * from public.store_exec_game_claim(:'e_token') \gset hc_
reset role;
update store.game_orders set claimed_at = now() - interval '11 minutes' where id = :h_game_id;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('owner gives back a stale phone order', public.store_game_claim(null, :h_game_id, false) = 'queued');
select pg_temp.check('then cancels it as not done, card back', public.store_game_claim(null, :h_game_id, true) = 'claimed'
  and public.store_game_finish(null, :h_game_id, 'failed', null, 'test', true) = 'failed');
reset role;
select pg_temp.check('given back clean', (select status = 'failed' and claimed_executor is null and auto_state is null from store.game_orders where id = :h_game_id));
set role anon;
select pg_temp.check('the late report is refused', pg_temp.err(format($$select public.store_exec_game_report(%L, %s, 'sent', 'x', null)$$, :'e_token', :h_game_id)) like '%GAME_NOT_OPEN%');
reset role;

-- ===== used card with no other card → failed with refund =====
update store.codes set status = 'void', void_reason = 'test', voided_at = now()
 where product_id = :pp and status = 'available' and id <> (select min(id) from store.codes where product_id = :pp and status = 'available');
set role anon;
select * from public.store_game_create(:'tok', :pp, '5500000005', gen_random_uuid()) \gset f_
select * from public.store_exec_game_claim(:'e_token') \gset fc_
select pg_temp.check('used card, none left → failed', public.store_exec_game_report(:'e_token', :f_game_id, 'sent', 'مستعملة', null) = 'failed');
reset role;
select pg_temp.check('refunded once, nothing left open', (select count(*) from store.wallet_entries where order_id = (select order_id from store.game_orders where id = :f_game_id) and kind = 'purchase_refund') = 1
  and (select status = 'failed' and auto_state is null from store.game_orders where id = :f_game_id));

-- ===== the phone switched off for games gets nothing; disabled phone refused =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('switch off', not public.store_admin_executor_set_game(:e_executor_id, false));
reset role;
set role anon;
select pg_temp.check('switched off: nothing', not exists (select 1 from public.store_exec_game_claim(:'e_token')));
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('idle phone can be disabled', not public.store_admin_executor_set_active(:e_executor_id, false));
reset role;
set role anon;
select pg_temp.check('disabled phone refused', pg_temp.err(format('select * from public.store_exec_game_claim(%L)', :'e_token')) like '%INVALID_EXECUTOR%');
reset role;

-- ===== ledger =====
select pg_temp.check('ledger matches the balance', (select balance from store.customers where id = :cu) = (select sum(d_balance) from store.wallet_entries where customer_id = :cu));

\set QUIET off
select ok, count(*) from p_results group by ok;
select name, detail from p_results where not ok;
