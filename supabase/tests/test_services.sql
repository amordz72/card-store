-- Behavioural tests for the services (stage 1). Run after all migrations and supabase/external-pending/card_store_services_stage1.sql.
\set ON_ERROR_STOP on
\set QUIET on
create temp table s_results (name text, ok boolean, detail text);
grant all on s_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into s_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== owner: «منتجات أخرى», a hard disk as a service, a customer with 20000 =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_brand(null, 'منتجات أخرى', 'other', 99, true) \g /dev/null
select brand_id as ob from public.store_admin_brands() where name = 'منتجات أخرى' \gset
select public.store_admin_save_product(null, :ob, 'قرص صلب', 8000, 1, true) as hd \gset
select public.store_admin_save_product(null, :ob, 'شراء من موقع', 1000, 2, true) as web \gset
select public.store_admin_create_customer('زبون خدمات', '0779000351', 'secret123') as cu \gset
select public.store_admin_create_customer('زبون ثانٍ', '0779000352', 'secret123') as cu2 \gset
select entry_id from public.store_admin_transfer(:cu, 'cash', 20000, null, gen_random_uuid()) \g /dev/null
select entry_id from public.store_admin_transfer(:cu2, 'cash', 5000, null, gen_random_uuid()) \g /dev/null
-- the price this customer pays: fixed 8000 for the disk, fixed 1000 for the web purchase
select public.store_admin_set_price(:cu, :hd, 'fixed', 8000) \g /dev/null
select public.store_admin_set_price(:cu, :web, 'fixed', 1000) \g /dev/null
select public.store_admin_set_price(:cu2, :web, 'fixed', 1000) \g /dev/null

select pg_temp.check('a service needs its usual cost',
  pg_temp.err(format('select public.store_admin_service_save(%s, true, true, null, null)', :hd)) like '%SERVICE_COST_REQUIRED%');
select pg_temp.check('bad field list refused',
  pg_temp.err(format($$select public.store_admin_service_save(%s, true, true, '[{"key":"A B","label":"x"}]', 7000)$$, :hd)) like '%INVALID_SERVICE_FIELDS%');
select pg_temp.check('a choice needs options',
  pg_temp.err(format($$select public.store_admin_service_save(%s, true, true, '[{"key":"g","label":"اللعبة","type":"choice"}]', 7000)$$, :hd)) like '%INVALID_SERVICE_FIELDS%');
select public.store_admin_service_save(:hd, true, true,
  '[{"key":"specs","label":"المواصفات","type":"long","required":true},
    {"key":"brand","label":"الماركة","type":"choice","options":["WD","Seagate"],"required":true},
    {"key":"link","label":"رابط المنتج","type":"link"},
    {"key":"phone","label":"هاتف","type":"phone"}]', 7000) \g /dev/null
select public.store_admin_service_save(:web, true, true, '[{"key":"link","label":"الرابط","type":"link","required":true}]', 900) \g /dev/null
select pg_temp.check('owner list', (select jsonb_array_length(public.store_admin_services())) = 2);
reset role;

select set_config('request.jwt.claim.sub', '', false);
set role anon;
select session_token as tok from public.store_login('0779000351', 'secret123') \gset
select session_token as tok2 from public.store_login('0779000352', 'secret123') \gset
select pg_temp.check('customer sees the services', (select count(*) from jsonb_array_elements(public.store_services(:'tok')) x where (x->>'product_id')::bigint in (:hd, :web)) = 2);
select pg_temp.check('anon cannot save a service', pg_temp.err(format('select public.store_admin_service_save(%s, false, null, null, null)', :hd)) like '%permission denied%');
select pg_temp.check('customer cannot read the queue', pg_temp.err('select public.store_admin_service_queue(true, 10, 0)') like '%permission denied%');

-- ===== ordering =====
select pg_temp.check('required field', pg_temp.err(format($$select public.store_service_create(%L, %s, 2, '{"brand":"WD"}', null, gen_random_uuid())$$, :'tok', :hd)) like '%SERVICE_FIELD_REQUIRED%');
select pg_temp.check('choice outside the list', pg_temp.err(format($$select public.store_service_create(%L, %s, 2, '{"specs":"1TB","brand":"Sony"}', null, gen_random_uuid())$$, :'tok', :hd)) like '%SERVICE_FIELD_INVALID%');
select pg_temp.check('bad link', pg_temp.err(format($$select public.store_service_create(%L, %s, 2, '{"specs":"1TB","brand":"WD","link":"abc"}', null, gen_random_uuid())$$, :'tok', :hd)) like '%SERVICE_FIELD_INVALID%');
select pg_temp.check('qty over 500', pg_temp.err(format($$select public.store_service_create(%L, %s, 501, '{"link":"https://x.dz/a"}', null, gen_random_uuid())$$, :'tok', :web)) like '%INVALID_QTY%');
select pg_temp.check('balance must cover the whole order', pg_temp.err(format($$select public.store_service_create(%L, %s, 3, '{"specs":"1TB","brand":"WD"}', null, gen_random_uuid())$$, :'tok', :hd)) like '%INSUFFICIENT_BALANCE%');

select (public.store_service_create(:'tok', :hd, 2, '{"specs":"1TB SSD","brand":"WD","phone":"0770 12 34 56","extra":"ignored"}', ' عاجل ', 'bbbbbbbb-0000-0000-0000-000000000001')->>'id')::bigint as s1 \gset
reset role;
select pg_temp.check('order held 16000', (select total = 16000 and paid = 16000 and debt = 0 and status = 'queued' from store.service_orders where id = :s1));
select pg_temp.check('fields kept with labels, unknown keys dropped, phone cleaned',
  (select fields = '[{"key":"specs","label":"المواصفات","value":"1TB SSD"},{"key":"brand","label":"الماركة","value":"WD"},{"key":"phone","label":"هاتف","value":"0770123456"}]'::jsonb
     and note = 'عاجل' from store.service_orders where id = :s1));
set role anon;
select pg_temp.check('same request id: same order, charged once',
  (public.store_service_create(:'tok', :hd, 2, '{"specs":"x","brand":"WD"}', null, 'bbbbbbbb-0000-0000-0000-000000000001')->>'id')::bigint = :s1);
select pg_temp.check('request id of another customer', pg_temp.err(format($$select public.store_service_create(%L, %s, 1, '{"link":"https://x.dz"}', null, 'bbbbbbbb-0000-0000-0000-000000000001')$$, :'tok2', :web)) like '%REQUEST_ID_CONFLICT%');
reset role;
select pg_temp.check('balance 4000 after the hold', (select balance from store.customers where id = :cu) = 4000);
select pg_temp.check('order row 2 × 8000', (select qty = 2 and charged_amount = 16000 and cost_amount = 14000 and status = 'done' from store.orders where id = (select order_id from store.service_orders where id = :s1)));

-- closing
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_service_save(:web, null, false, null, null) \g /dev/null
reset role;
set role anon;
select pg_temp.check('closed service shown as closed', (select (x->>'open')::boolean = false from jsonb_array_elements(public.store_services(:'tok')) x where (x->>'product_id')::bigint = :web));
select pg_temp.check('closed service refused', pg_temp.err(format($$select public.store_service_create(%L, %s, 1, '{"link":"https://x.dz/a"}', null, gen_random_uuid())$$, :'tok2', :web)) like '%SERVICE_CLOSED%');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_service_save(:web, null, true, null, null) \g /dev/null
reset role;

-- cancel while waiting: everything back
set role anon;
select (public.store_service_create(:'tok2', :web, 3, '{"link":"https://shop.example/item"}', null, gen_random_uuid())->>'id')::bigint as s2 \gset
select pg_temp.check('other customer cannot cancel it', pg_temp.err(format('select public.store_service_cancel(%L, %s)', :'tok', :s2)) like '%SERVICE_ORDER_NOT_FOUND%');
select pg_temp.check('cancel', public.store_service_cancel(:'tok2', :s2)->>'status' = 'cancelled');
select pg_temp.check('cancel twice is harmless', public.store_service_cancel(:'tok2', :s2)->>'status' = 'cancelled');
reset role;
select pg_temp.check('cancel refunded 3000', (select balance from store.customers where id = :cu2) = 5000
  and (select status from store.orders where id = (select order_id from store.service_orders where id = :s2)) = 'refunded');

-- ===== the owner works the queue =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('queue shows the open order', exists (select 1 from jsonb_array_elements(public.store_admin_service_queue(true, 50, 0)) x where (x->>'id')::bigint = :s1 and x->>'customer_name' = 'زبون خدمات'));
select pg_temp.check('open count', public.store_admin_service_open_count() = 1);
select pg_temp.check('claim', public.store_admin_service_claim(:s1)->>'status' = 'claimed');
reset role;
set role anon;
select pg_temp.check('customer cannot cancel after «أبدأ»', pg_temp.err(format('select public.store_service_cancel(%L, %s)', :'tok', :s1)) like '%SERVICE_STARTED%');
reset role;

-- price up: 2 × 11000 = 22000, 6000 more; the balance has 4000, the rest (2000) becomes debt
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('a reason is required', pg_temp.err(format('select public.store_admin_service_price(%s, 11000, %L)', :s1, ' ')) like '%SERVICE_REASON_REQUIRED%');
select public.store_admin_service_price(:s1, 11000, 'ارتفع سعر المورد') \g /dev/null
reset role;
select pg_temp.check('increase: balance first, then debt', (select total = 22000 and paid = 20000 and debt = 2000 from store.service_orders where id = :s1)
  and (select balance = 0 and debt = 2000 from store.customers where id = :cu));
select pg_temp.check('customer sees the reason', exists (select 1 from jsonb_array_elements((select x2 from jsonb_array_elements(public.store_service_orders(:'tok', 10, 0)) x2 where (x2->>'id')::bigint = :s1)->'changes') x
  where x->>'what' = 'price' and x->>'reason' = 'ارتفع سعر المورد' and (x->>'new_total')::bigint = 22000));

-- the usual reversal refuses a service order
select min(id) as pe from store.wallet_entries where kind = 'purchase' and order_id = (select order_id from store.service_orders where id = :s1) \gset
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('reverse refused on a service order', pg_temp.err(format('select * from public.store_admin_reverse(%s, null, gen_random_uuid())', :pe)) like '%SERVICE_ORDER_USE_QUEUE%');

-- «تم» with 1 of 2: only 11000 is charged; 11000 back, the debt part (2000) cancelled first
select public.store_admin_service_done(:s1, 1, 7500, 'وصل القرص، تعال خذه') \g /dev/null
reset role;
select pg_temp.check('done 1 of 2', (select status = 'done' and qty_done = 1 and total = 11000 and paid = 11000 and debt = 0 and cost_total = 7500 and reply = 'وصل القرص، تعال خذه'
  from store.service_orders where id = :s1));
select pg_temp.check('debt cancelled first, then 9000 back', (select balance = 9000 and debt = 0 from store.customers where id = :cu));
select pg_temp.check('order row now 1 × 11000, real cost', (select qty = 1 and charged_amount = 11000 and cost_amount = 7500 and base_amount = 8000 from store.orders where id = (select order_id from store.service_orders where id = :s1)));

-- price down after «تم»: 11000 → 10000, 1000 back
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_service_price(:s1, 10000, 'تخفيض') \g /dev/null
select pg_temp.check('done twice is harmless', public.store_admin_service_done(:s1, 2, null, null)->>'qty_done' = '1');
reset role;
select pg_temp.check('decrease after done', (select total from store.service_orders where id = :s1) = 10000 and (select balance from store.customers where id = :cu) = 10000);

-- «لم يتم»: everything back, after a price increase that made debt
set role anon;
select (public.store_service_create(:'tok', :web, 2, '{"link":"https://x.dz/b"}', null, gen_random_uuid())->>'id')::bigint as s3 \gset
reset role;
update store.customers set balance = 0 where id = :cu;  -- spent elsewhere (test shortcut; ledger restored below)
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('debt beyond the debt limit allowed (owner decision)', (public.store_admin_service_price(:s3, 1500, 'رسوم الشحن')->>'debt')::bigint = 1000);
select public.store_admin_service_fail(:s3, 'نفد عند المورد') \g /dev/null
reset role;
select pg_temp.check('fail: nothing charged', (select status = 'failed' and total = 0 and paid = 0 and debt = 0 from store.service_orders where id = :s3));
select pg_temp.check('fail: order refunded', (select status from store.orders where id = (select order_id from store.service_orders where id = :s3)) = 'refunded');
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select pg_temp.check('no price change after fail', pg_temp.err(format('select public.store_admin_service_price(%s, 100, %L)', :s3, 'x')) like '%SERVICE_FINISHED%');
select pg_temp.check('no done after fail', pg_temp.err(format('select public.store_admin_service_done(%s, 1, null, null)', :s3)) like '%SERVICE_FINISHED%');
reset role;
update store.customers set balance = (select coalesce(sum(d_balance), 0) from store.wallet_entries where customer_id = :cu) where id = :cu;

-- ===== the ledger =====
select pg_temp.check('ledger matches the balance', (select balance from store.customers where id = :cu) = (select sum(d_balance) from store.wallet_entries where customer_id = :cu));
select pg_temp.check('ledger matches the debt', (select debt from store.customers where id = :cu) = (select sum(d_debt) from store.wallet_entries where customer_id = :cu));
select pg_temp.check('ledger matches for the second customer', (select balance from store.customers where id = :cu2) = (select sum(d_balance) from store.wallet_entries where customer_id = :cu2));
select pg_temp.check('every order: charged = its ledger', not exists (
  select 1 from store.service_orders s
  where s.total <> coalesce((select sum(-w.d_balance + w.d_debt) from store.wallet_entries w where w.order_id = s.order_id), 0)));
select pg_temp.check('changes are append-only', pg_temp.err('delete from store.service_changes') like '%APPEND_ONLY%');

\set QUIET off
select ok, count(*) from s_results group by ok;
select name, detail from s_results where not ok;
