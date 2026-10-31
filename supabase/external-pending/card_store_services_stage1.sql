-- card-store — الخدمات (المرحلة الأولى). قرار المالك 2026-10-31:
--   developer/projects/card-store/SERVICES-2026-10-31.md (البنود 1–15، 20–21، 23–27)
--
-- مكان هذا الملف: يُنقل كما هو إلى flexy-core `supabase/external/sNNN_card_store_services.sql` (الرقم التالي لحظة الدمج)،
-- ثم `node scripts/gen-migrations.mjs`. كُتب في جلسة لا تصل إلى flexy-core.
-- الدوال القائمة التي يستبدلها (create or replace) أُخذت من القاعدة الحية 2026-10-31 بالقراءة فقط:
--   private.store_kind_effect, private.store_admin_reverse_impl — لم تتغيرا منذ v1.33/v1.29. إن تغيّرت قبل التطبيق: أعد القراءة.
-- لا يلمس store_buy_core ولا الكتالوج: الخدمة مسار مستقل.
--
-- الخدمة = منتج بلا أكواد (products.is_service). الزبون يطلب: العدد (1–500)، حقول الخدمة، ملاحظة. يُحجز المال عند الطلب
-- (purchase). المالك وحده ينفّذ: «أبدأ» ← «تم» بالعدد المؤكَّد والتكلفة الحقيقية والرد، أو «لم يتم» (إرجاع كامل).
-- الزبون يلغي ما دام الطلب لم يُبدأ. المالك يغيّر سعر الوحدة في أي وقت بسبب يراه الزبون: التخفيض يُعاد،
-- والزيادة تؤخذ من الرصيد والباقي دين (service_debt، يتجاوز حد الدين لأنه قرار المالك).
-- المحسوب على الزبون دائمًا = total = paid (من الرصيد) + debt (دين). كل تغيير حركة جديدة في الدفتر (append-only).
-- Additive: new columns, new tables, new functions; two existing functions replaced with the same signatures.

-- ---------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------
alter table store.products
  add column if not exists is_service boolean not null default false,
  add column if not exists service_open boolean not null default true,
  add column if not exists service_fields jsonb not null default '[]'::jsonb;
alter table store.products drop constraint if exists products_service_fields_check;
alter table store.products add constraint products_service_fields_check
  check (jsonb_typeof(service_fields) = 'array' and jsonb_array_length(service_fields) <= 20);

-- «منتجات أخرى»: a category of its own, the last section of the store
alter table store.brands drop constraint brands_category_check;
alter table store.brands add constraint brands_category_check check (category in ('phone', 'net', 'game', 'other'));

-- A service order may hold up to 500 (store_buy_core keeps its own limit of 20 for cards)
alter table store.orders drop constraint orders_qty_check;
alter table store.orders add constraint orders_qty_check check (qty between 1 and 500);

-- Debt added by a price increase the balance cannot cover, and its reversal
alter table store.wallet_entries drop constraint wallet_entries_kind_check;
alter table store.wallet_entries add constraint wallet_entries_kind_check check (kind in (
  'debt', 'debt_refund', 'cash', 'cash_refund', 'pay', 'pay_refund', 'self', 'purchase', 'purchase_refund',
  'shop_topup', 'shop_topup_refund', 'flexy', 'flexy_refund', 'service_debt', 'service_debt_refund'));

create or replace function private.store_kind_effect(p_kind text, out b integer, out d integer)
returns record language sql immutable set search_path = '' as $$
  select v.b, v.d from (values
    ('debt', 1, 1), ('debt_refund', -1, -1),
    ('cash', 1, 0), ('cash_refund', -1, 0),
    ('pay', 0, -1), ('pay_refund', 0, 1),
    ('self', 1, 1),
    ('purchase', -1, 0), ('purchase_refund', 1, 0),
    ('shop_topup', 1, 0), ('shop_topup_refund', -1, 0),
    ('flexy', -1, 0), ('flexy_refund', 1, 0),
    ('service_debt', 0, 1), ('service_debt_refund', 0, -1)
  ) v(k, b, d) where v.k = p_kind;
$$;

create table if not exists store.service_orders (
  id bigint generated always as identity primary key,
  order_id bigint not null unique references store.orders(id),
  customer_id bigint not null references store.customers(id),
  product_id bigint not null references store.products(id),
  qty int not null check (qty between 1 and 500),                 -- what the customer asked for
  qty_done int check (qty_done is null or qty_done between 1 and 500), -- what the owner confirmed sending
  unit_price bigint not null check (unit_price > 0),              -- per unit, the owner may change it
  total bigint not null check (total >= 0),                       -- charged now = paid + debt
  paid bigint not null default 0 check (paid >= 0),               -- taken from the balance
  debt bigint not null default 0 check (debt >= 0),               -- added to the debt (price increases)
  unit_cost bigint check (unit_cost is null or unit_cost > 0),    -- the service's usual cost when ordered
  cost_total bigint check (cost_total is null or cost_total >= 0),-- the real cost, written at «تم»
  fields jsonb not null default '[]'::jsonb,                      -- [{key,label,value}] as asked when ordered
  note text check (note is null or length(note) <= 1000),
  status text not null default 'queued' check (status in ('queued', 'claimed', 'done', 'failed', 'cancelled')),
  reply text check (reply is null or length(reply) <= 1000),      -- shown to the customer
  request_id uuid not null unique,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  finished_at timestamptz,
  check (total = paid + debt)
);
create index if not exists service_orders_customer on store.service_orders (customer_id, id desc);
create index if not exists service_orders_open on store.service_orders (id) where status in ('queued', 'claimed');

-- Every change the customer should see (price with its reason, count, end)
create table if not exists store.service_changes (
  id bigint generated always as identity primary key,
  service_order_id bigint not null references store.service_orders(id),
  what text not null check (what in ('price', 'claimed', 'done', 'failed', 'cancelled')),
  old_total bigint,
  new_total bigint,
  reason text check (reason is null or length(reason) <= 300),
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists service_changes_order on store.service_changes (service_order_id, id);
create trigger service_changes_append_only before update or delete on store.service_changes
  for each row execute function private.store_block_change();

alter table store.service_orders enable row level security;
alter table store.service_changes enable row level security;
revoke all on store.service_orders from public, anon, authenticated;
revoke all on store.service_changes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
-- The owner's field list for a service: [{key,label,type,required,options}]
create or replace function private.store_service_fields_check(p jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  f jsonb;
  v_keys text[] := '{}';
  v_out jsonb := '[]'::jsonb;
  v_key text;
  v_type text;
  v_opts jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) > 20 then raise exception 'INVALID_SERVICE_FIELDS'; end if;
  for f in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(f) <> 'object' then raise exception 'INVALID_SERVICE_FIELDS'; end if;
    v_key := f->>'key';
    v_type := coalesce(f->>'type', 'text');
    if v_key is null or v_key !~ '^[a-z0-9_]{1,30}$' or v_key = any (v_keys) then raise exception 'INVALID_SERVICE_FIELDS'; end if;
    if length(btrim(coalesce(f->>'label', ''))) not between 1 and 60 then raise exception 'INVALID_SERVICE_FIELDS'; end if;
    if v_type not in ('text', 'long', 'number', 'phone', 'link', 'choice') then raise exception 'INVALID_SERVICE_FIELDS'; end if;
    v_opts := '[]'::jsonb;
    if v_type = 'choice' then
      select coalesce(jsonb_agg(btrim(o)), '[]'::jsonb) into v_opts
      from jsonb_array_elements_text(case when jsonb_typeof(f->'options') = 'array' then f->'options' else '[]'::jsonb end) o
      where length(btrim(o)) between 1 and 60;
      if jsonb_array_length(v_opts) not between 1 and 50 then raise exception 'INVALID_SERVICE_FIELDS'; end if;
    end if;
    v_keys := v_keys || v_key;
    v_out := v_out || jsonb_build_array(jsonb_build_object('key', v_key, 'label', btrim(f->>'label'), 'type', v_type,
      'required', coalesce((f->>'required')::boolean, false), 'options', v_opts));
  end loop;
  return v_out;
end;
$$;

-- The customer's answers checked against the service's fields; returns [{key,label,value}] (empty optional ones left out)
create or replace function private.store_service_answers(p_defs jsonb, p_answers jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  f jsonb;
  v text;
  v_type text;
  v_out jsonb := '[]'::jsonb;
begin
  for f in select * from jsonb_array_elements(coalesce(p_defs, '[]'::jsonb)) loop
    v := btrim(coalesce(case when jsonb_typeof(p_answers) = 'object' then p_answers->>(f->>'key') end, ''));
    v_type := f->>'type';
    if v = '' then
      if (f->>'required')::boolean then raise exception 'SERVICE_FIELD_REQUIRED'; end if;
      continue;
    end if;
    if v_type = 'phone' then v := regexp_replace(v, '[^0-9]', '', 'g'); end if;
    if (v_type = 'long' and length(v) > 1000) or (v_type <> 'long' and length(v) > 300)
       or (v_type = 'number' and v !~ '^[0-9]+([.,][0-9]+)?$')
       or (v_type = 'phone' and v !~ '^0[5-7][0-9]{8}$')
       or (v_type = 'link' and v !~ '^https?://[^[:space:]]+$')
       or (v_type = 'choice' and not (f->'options') ? v) then
      raise exception 'SERVICE_FIELD_INVALID';
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('key', f->>'key', 'label', f->>'label', 'value', v));
  end loop;
  return v_out;
end;
$$;

-- Bring what the customer is charged to p_total: a decrease cancels the debt part first, then refunds the balance;
-- an increase takes the balance, then the rest becomes debt (beyond the debt limit: the owner's own decision).
create or replace function private.store_service_settle(p_id bigint, p_total bigint, p_note text)
returns store.service_orders language plpgsql security definer set search_path = '' as $$
declare
  s store.service_orders;
  v_bal bigint;
  v_delta bigint;
  v_x bigint;
  a uuid := auth.uid();
begin
  select * into s from store.service_orders where id = p_id for update;
  if p_total < 0 then raise exception 'INVALID_AMOUNT'; end if;
  v_delta := p_total - s.total;
  if v_delta < 0 then
    v_x := least(s.debt, -v_delta);
    if v_x > 0 then
      perform private.store_post_entry(s.customer_id, 'service_debt_refund', v_x, p_note, s.order_id, null, null, a);
      s.debt := s.debt - v_x;
    end if;
    v_x := -v_delta - v_x;
    if v_x > 0 then
      perform private.store_post_entry(s.customer_id, 'purchase_refund', v_x, p_note, s.order_id, null, null, a);
      s.paid := s.paid - v_x;
    end if;
  elsif v_delta > 0 then
    select greatest(c.balance, 0) into v_bal from store.customers c where c.id = s.customer_id for update;
    v_x := least(v_bal, v_delta);
    if v_x > 0 then
      perform private.store_post_entry(s.customer_id, 'purchase', v_x, p_note, s.order_id, null, null, a);
      s.paid := s.paid + v_x;
    end if;
    v_x := v_delta - v_x;
    if v_x > 0 then
      perform private.store_post_entry(s.customer_id, 'service_debt', v_x, p_note, s.order_id, null, null, a);
      s.debt := s.debt + v_x;
    end if;
  end if;
  update store.service_orders set total = p_total, paid = s.paid, debt = s.debt where id = p_id returning * into s;
  return s;
end;
$$;

-- What this customer pays for one unit of a service: his price rule, with the service's usual cost as the cost
create or replace function private.store_service_unit(p_customer bigint, p_product bigint) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  p store.products;
  v_mode text;
  v_value numeric;
  v bigint;
begin
  select * into p from store.products where id = p_product;
  select pr.mode, pr.value into v_mode, v_value from private.store_price_rule(p_customer, p.id) pr;
  v := private.store_unit_charge(v_mode, v_value, p.default_cost, p.base_price);
  if v is null or v <= 0 then raise exception 'INVALID_PRICE_RULE'; end if;
  return v;
end;
$$;

-- One service order as both sides read it, with its changes
create or replace function private.store_service_row(s store.service_orders) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', s.id, 'order_id', s.order_id, 'product_id', s.product_id, 'product_name', p.name, 'brand', b.name, 'category', b.category,
    'qty', s.qty, 'qty_done', s.qty_done, 'unit_price', s.unit_price, 'total', s.total, 'paid', s.paid, 'debt', s.debt,
    'fields', s.fields, 'note', s.note, 'status', s.status, 'reply', s.reply,
    'created_at', s.created_at, 'claimed_at', s.claimed_at, 'finished_at', s.finished_at,
    'changes', coalesce((select jsonb_agg(jsonb_build_object('what', x.what, 'old_total', x.old_total, 'new_total', x.new_total,
                                                             'reason', x.reason, 'at', x.created_at) order by x.id)
                         from store.service_changes x where x.service_order_id = s.id), '[]'::jsonb))
  from store.products p join store.brands b on b.id = p.brand_id where p.id = s.product_id;
$$;

-- ---------------------------------------------------------------------
-- Customer
-- ---------------------------------------------------------------------
-- The services a customer can order (closed ones shown as closed)
create or replace function private.store_services_impl(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_session_customer(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object(
      'product_id', p.id, 'brand', b.name, 'category', b.category, 'name', p.name, 'base_price', p.base_price,
      'open', p.service_open, 'fields', p.service_fields, 'image', p.image, 'brand_image', b.image)
      order by b.category, b.sort, p.sort, p.base_price)
    from store.products p join store.brands b on b.id = p.brand_id
    where p.is_service and p.active and b.active), '[]'::jsonb);
end;
$$;

-- Order a service: pay now (held), queue it for the owner. Idempotent on p_request_id.
create or replace function private.store_service_create_impl(p_token text, p_product_id bigint, p_qty integer,
  p_fields jsonb, p_note text, p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  s store.service_orders;
  p store.products;
  c store.customers;
  o store.orders;
  v_unit bigint;
  v_total bigint;
  v_answers jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into s from store.service_orders where request_id = p_request_id;
  if found then
    if s.customer_id <> v then raise exception 'REQUEST_ID_CONFLICT'; end if;
    return private.store_service_row(s);
  end if;
  if p_qty is null or p_qty < 1 or p_qty > 500 then raise exception 'INVALID_QTY'; end if;
  select pr.* into p from store.products pr join store.brands b on b.id = pr.brand_id
  where pr.id = p_product_id and pr.is_service and pr.active and b.active;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
  if not p.service_open then raise exception 'SERVICE_CLOSED'; end if;

  select * into c from store.customers where id = v for update;
  if c.is_shop then raise exception 'SERVICE_NOT_FOR_SHOP'; end if;
  v_unit := private.store_service_unit(v, p.id);
  v_total := v_unit * p_qty;
  if c.balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;
  v_answers := private.store_service_answers(p.service_fields, p_fields);

  insert into store.orders (customer_id, product_id, qty, base_amount, pct, charged_amount, cost_amount, balance_after, request_id)
  values (v, p.id, p_qty, p.base_price * p_qty, 0, v_total, p.default_cost * p_qty, c.balance - v_total, p_request_id)
  returning * into o;
  perform private.store_post_entry(v, 'purchase', v_total, null, o.id, null, null, null);
  insert into store.service_orders (order_id, customer_id, product_id, qty, unit_price, total, paid, unit_cost, fields, note, request_id)
  values (o.id, v, p.id, p_qty, v_unit, v_total, v_total, p.default_cost, v_answers, nullif(btrim(coalesce(p_note, '')), ''), p_request_id)
  returning * into s;
  return private.store_service_row(s);
end;
$$;

create or replace function private.store_service_orders_impl(p_token text, p_limit integer, p_offset integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return coalesce((select jsonb_agg(private.store_service_row(s) order by s.id desc) from (
    select * from store.service_orders x where x.customer_id = v order by x.id desc
    limit least(greatest(coalesce(p_limit, 20), 1), 100) offset greatest(coalesce(p_offset, 0), 0)) s), '[]'::jsonb);
end;
$$;

-- The customer cancels while the owner has not started: full refund
create or replace function private.store_service_cancel_impl(p_token text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  s store.service_orders;
  v_old bigint;
begin
  select * into s from store.service_orders where id = p_id and customer_id = v for update;
  if not found then raise exception 'SERVICE_ORDER_NOT_FOUND'; end if;
  if s.status = 'cancelled' then return private.store_service_row(s); end if;
  if s.status <> 'queued' then raise exception 'SERVICE_STARTED'; end if;
  v_old := s.total;
  s := private.store_service_settle(s.id, 0, 'إلغاء طلب خدمة');
  update store.service_orders set status = 'cancelled', finished_at = now() where id = s.id returning * into s;
  update store.orders set status = 'refunded' where id = s.order_id;
  insert into store.service_changes (service_order_id, what, old_total, new_total) values (s.id, 'cancelled', v_old, 0);
  return private.store_service_row(s);
end;
$$;

-- ---------------------------------------------------------------------
-- Owner
-- ---------------------------------------------------------------------
-- Every product marked as a service, with its settings and how many orders wait
create or replace function private.store_admin_services_impl() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'product_id', p.id, 'brand', b.name, 'category', b.category, 'name', p.name, 'base_price', p.base_price,
      'default_cost', p.default_cost, 'active', p.active and b.active, 'open', p.service_open, 'fields', p.service_fields,
      'waiting', (select count(*) from store.service_orders s where s.product_id = p.id and s.status in ('queued', 'claimed')))
      order by b.category, b.sort, p.sort, p.base_price)
    from store.products p join store.brands b on b.id = p.brand_id where p.is_service), '[]'::jsonb);
end;
$$;

-- Make a product a service (or not), open/close it, its fields and usual cost. null = keep.
create or replace function private.store_admin_service_save_impl(p_product_id bigint, p_is_service boolean, p_open boolean,
  p_fields jsonb, p_default_cost bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare p store.products;
begin
  perform private.store_require_admin();
  select * into p from store.products where id = p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
  if p_default_cost is not null and p_default_cost <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  if coalesce(p_is_service, p.is_service) and coalesce(p_default_cost, p.default_cost) is null then
    raise exception 'SERVICE_COST_REQUIRED';
  end if;
  update store.products set
    is_service = coalesce(p_is_service, is_service),
    service_open = coalesce(p_open, service_open),
    service_fields = case when p_fields is null then service_fields else private.store_service_fields_check(p_fields) end,
    default_cost = coalesce(p_default_cost, default_cost)
  where id = p_product_id;
end;
$$;

-- The queue: open orders (oldest first) or the finished ones (newest first)
create or replace function private.store_admin_service_queue_impl(p_open boolean, p_limit integer, p_offset integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return coalesce((select jsonb_agg(private.store_service_row(s) || jsonb_build_object('customer_id', c.id, 'customer_name', c.name,
                                    'customer_phone', c.phone, 'unit_cost', s.unit_cost, 'cost_total', s.cost_total)
                                    order by case when coalesce(p_open, true) then s.id else -s.id end)
    from (select * from store.service_orders x
          where (x.status in ('queued', 'claimed')) = coalesce(p_open, true)
          order by case when coalesce(p_open, true) then x.id else -x.id end
          limit least(greatest(coalesce(p_limit, 30), 1), 200) offset greatest(coalesce(p_offset, 0), 0)) s
    join store.customers c on c.id = s.customer_id), '[]'::jsonb);
end;
$$;

create or replace function private.store_admin_service_open_count_impl() returns integer
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return (select count(*) from store.service_orders where status in ('queued', 'claimed'));
end;
$$;

-- «أبدأ»: the customer can no longer cancel
create or replace function private.store_admin_service_claim_impl(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a uuid := private.store_require_admin();
  s store.service_orders;
begin
  select * into s from store.service_orders where id = p_id for update;
  if not found then raise exception 'SERVICE_ORDER_NOT_FOUND'; end if;
  if s.status = 'queued' then
    update store.service_orders set status = 'claimed', claimed_at = now() where id = p_id returning * into s;
    insert into store.service_changes (service_order_id, what, created_by) values (s.id, 'claimed', a);
  elsif s.status <> 'claimed' then
    raise exception 'SERVICE_FINISHED';
  end if;
  return private.store_service_row(s);
end;
$$;

-- The owner changes the unit price, at any time, with a reason the customer sees
create or replace function private.store_admin_service_price_impl(p_id bigint, p_unit_price bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a uuid := private.store_require_admin();
  s store.service_orders;
  v_old bigint;
  v_new bigint;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if p_unit_price is null or p_unit_price <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  if v_reason is null or length(v_reason) > 300 then raise exception 'SERVICE_REASON_REQUIRED'; end if;
  select * into s from store.service_orders where id = p_id for update;
  if not found then raise exception 'SERVICE_ORDER_NOT_FOUND'; end if;
  if s.status in ('failed', 'cancelled') then raise exception 'SERVICE_FINISHED'; end if;
  v_old := s.total;
  v_new := p_unit_price * coalesce(s.qty_done, s.qty);
  s := private.store_service_settle(s.id, v_new, 'تعديل سعر خدمة: ' || v_reason);
  update store.service_orders set unit_price = p_unit_price where id = s.id returning * into s;
  update store.orders set charged_amount = v_new where id = s.order_id and v_new > 0;
  insert into store.service_changes (service_order_id, what, old_total, new_total, reason, created_by)
  values (s.id, 'price', v_old, v_new, v_reason, a);
  return private.store_service_row(s);
end;
$$;

-- «تم»: the count actually sent (only that is charged), the real cost, the reply the customer reads
create or replace function private.store_admin_service_done_impl(p_id bigint, p_qty_done integer, p_cost_total bigint, p_reply text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a uuid := private.store_require_admin();
  s store.service_orders;
  p store.products;
  v_old bigint;
  v_new bigint;
  v_cost bigint;
begin
  if p_qty_done is null or p_qty_done < 1 or p_qty_done > 500 then raise exception 'INVALID_QTY'; end if;
  if p_cost_total is not null and p_cost_total < 0 then raise exception 'INVALID_AMOUNT'; end if;
  select * into s from store.service_orders where id = p_id for update;
  if not found then raise exception 'SERVICE_ORDER_NOT_FOUND'; end if;
  if s.status = 'done' then return private.store_service_row(s); end if;
  if s.status not in ('queued', 'claimed') then raise exception 'SERVICE_FINISHED'; end if;
  select * into p from store.products where id = s.product_id;
  v_old := s.total;
  v_new := s.unit_price * p_qty_done;
  v_cost := coalesce(p_cost_total, s.unit_cost * p_qty_done);
  s := private.store_service_settle(s.id, v_new, 'خدمة: تم ' || p_qty_done || ' من ' || s.qty);
  update store.service_orders set status = 'done', qty_done = p_qty_done, cost_total = v_cost,
    reply = nullif(btrim(coalesce(p_reply, '')), ''), claimed_at = coalesce(claimed_at, now()), finished_at = now()
  where id = s.id returning * into s;
  update store.orders set qty = p_qty_done, base_amount = p.base_price * p_qty_done, charged_amount = v_new, cost_amount = v_cost
  where id = s.order_id;
  insert into store.service_changes (service_order_id, what, old_total, new_total, created_by) values (s.id, 'done', v_old, v_new, a);
  return private.store_service_row(s);
end;
$$;

-- «لم يتم»: everything back to the customer
create or replace function private.store_admin_service_fail_impl(p_id bigint, p_reply text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a uuid := private.store_require_admin();
  s store.service_orders;
  v_old bigint;
begin
  select * into s from store.service_orders where id = p_id for update;
  if not found then raise exception 'SERVICE_ORDER_NOT_FOUND'; end if;
  if s.status = 'failed' then return private.store_service_row(s); end if;
  if s.status not in ('queued', 'claimed') then raise exception 'SERVICE_FINISHED'; end if;
  v_old := s.total;
  s := private.store_service_settle(s.id, 0, 'خدمة لم تتم');
  update store.service_orders set status = 'failed', reply = nullif(btrim(coalesce(p_reply, '')), ''), finished_at = now()
  where id = s.id returning * into s;
  update store.orders set status = 'refunded' where id = s.order_id;
  insert into store.service_changes (service_order_id, what, old_total, new_total, reason, created_by)
  values (s.id, 'failed', v_old, 0, s.reply, a);
  return private.store_service_row(s);
end;
$$;

-- The usual reversal must not touch a service order (its money moves only through the queue), otherwise the order
-- could stay waiting with its money back, or be refunded twice. Body as live on 2026-10-31, plus that one check.
create or replace function private.store_admin_reverse_impl(p_entry_id bigint, p_note text, p_request_id uuid)
returns table(entry_id bigint, kind text, balance_after bigint, debt_after bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  a uuid := private.store_require_admin();
  e store.wallet_entries;
  r store.wallet_entries;
  v_kind text;
  v_amount bigint;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into r from store.wallet_entries where request_id = p_request_id;
  if not found then
    select * into e from store.wallet_entries where id = p_entry_id;
    if not found then raise exception 'ENTRY_NOT_FOUND'; end if;
    if e.order_id is not null and exists (select 1 from store.service_orders so where so.order_id = e.order_id) then
      raise exception 'SERVICE_ORDER_USE_QUEUE';
    end if;
    v_kind := private.store_refund_kind(e.kind);
    if v_kind is null then raise exception 'NOT_REVERSIBLE'; end if;
    if exists (select 1 from store.wallet_entries x where x.reverses_id = e.id) then raise exception 'ALREADY_REVERSED'; end if;
    v_amount := e.amount;
    if e.kind = 'purchase' then
      v_amount := e.amount - coalesce((select sum(w.amount) from store.card_checks x join store.wallet_entries w on w.id = x.entry_id
                                       join store.codes k on k.id = x.code_id where k.order_id = e.order_id), 0);
      if v_amount <= 0 then raise exception 'ALREADY_REVERSED'; end if;
    end if;
    r := private.store_post_entry(e.customer_id, v_kind, v_amount, p_note, e.order_id, e.id, p_request_id, a);
    if e.kind = 'purchase' then
      update store.orders set status = 'refunded' where id = e.order_id;
      update store.codes set status = 'void' where order_id = e.order_id;
    end if;
  end if;
  return query select r.id, r.kind, r.balance_after, r.debt_after;
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers and grants
-- ---------------------------------------------------------------------
create or replace function public.store_services(p_token text) returns jsonb
language sql set search_path = '' as $$ select private.store_services_impl(p_token) $$;
create or replace function public.store_service_create(p_token text, p_product_id bigint, p_qty integer, p_fields jsonb, p_note text, p_request_id uuid)
returns jsonb language sql set search_path = '' as $$ select private.store_service_create_impl(p_token, p_product_id, p_qty, p_fields, p_note, p_request_id) $$;
create or replace function public.store_service_orders(p_token text, p_limit integer, p_offset integer) returns jsonb
language sql set search_path = '' as $$ select private.store_service_orders_impl(p_token, p_limit, p_offset) $$;
create or replace function public.store_service_cancel(p_token text, p_id bigint) returns jsonb
language sql set search_path = '' as $$ select private.store_service_cancel_impl(p_token, p_id) $$;

create or replace function public.store_admin_services() returns jsonb
language sql set search_path = '' as $$ select private.store_admin_services_impl() $$;
create or replace function public.store_admin_service_save(p_product_id bigint, p_is_service boolean, p_open boolean, p_fields jsonb, p_default_cost bigint)
returns void language sql set search_path = '' as $$ select private.store_admin_service_save_impl(p_product_id, p_is_service, p_open, p_fields, p_default_cost) $$;
create or replace function public.store_admin_service_queue(p_open boolean, p_limit integer, p_offset integer) returns jsonb
language sql set search_path = '' as $$ select private.store_admin_service_queue_impl(p_open, p_limit, p_offset) $$;
create or replace function public.store_admin_service_open_count() returns integer
language sql set search_path = '' as $$ select private.store_admin_service_open_count_impl() $$;
create or replace function public.store_admin_service_claim(p_id bigint) returns jsonb
language sql set search_path = '' as $$ select private.store_admin_service_claim_impl(p_id) $$;
create or replace function public.store_admin_service_price(p_id bigint, p_unit_price bigint, p_reason text) returns jsonb
language sql set search_path = '' as $$ select private.store_admin_service_price_impl(p_id, p_unit_price, p_reason) $$;
create or replace function public.store_admin_service_done(p_id bigint, p_qty_done integer, p_cost_total bigint, p_reply text) returns jsonb
language sql set search_path = '' as $$ select private.store_admin_service_done_impl(p_id, p_qty_done, p_cost_total, p_reply) $$;
create or replace function public.store_admin_service_fail(p_id bigint, p_reply text) returns jsonb
language sql set search_path = '' as $$ select private.store_admin_service_fail_impl(p_id, p_reply) $$;

-- Internal helpers: nobody calls them directly
revoke all on function private.store_service_fields_check(jsonb) from public, anon, authenticated;
revoke all on function private.store_service_answers(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.store_service_settle(bigint, bigint, text) from public, anon, authenticated;
revoke all on function private.store_service_unit(bigint, bigint) from public, anon, authenticated;
revoke all on function private.store_service_row(store.service_orders) from public, anon, authenticated;

-- Customer side: called with the customer token (anon or authenticated)
revoke all on function private.store_services_impl(text) from public, anon, authenticated;
revoke all on function private.store_service_create_impl(text, bigint, integer, jsonb, text, uuid) from public, anon, authenticated;
revoke all on function private.store_service_orders_impl(text, integer, integer) from public, anon, authenticated;
revoke all on function private.store_service_cancel_impl(text, bigint) from public, anon, authenticated;
revoke all on function public.store_services(text) from public, anon, authenticated;
revoke all on function public.store_service_create(text, bigint, integer, jsonb, text, uuid) from public, anon, authenticated;
revoke all on function public.store_service_orders(text, integer, integer) from public, anon, authenticated;
revoke all on function public.store_service_cancel(text, bigint) from public, anon, authenticated;
grant execute on function private.store_services_impl(text) to anon, authenticated;
grant execute on function private.store_service_create_impl(text, bigint, integer, jsonb, text, uuid) to anon, authenticated;
grant execute on function private.store_service_orders_impl(text, integer, integer) to anon, authenticated;
grant execute on function private.store_service_cancel_impl(text, bigint) to anon, authenticated;
grant execute on function public.store_services(text) to anon, authenticated;
grant execute on function public.store_service_create(text, bigint, integer, jsonb, text, uuid) to anon, authenticated;
grant execute on function public.store_service_orders(text, integer, integer) to anon, authenticated;
grant execute on function public.store_service_cancel(text, bigint) to anon, authenticated;

-- Owner side: authenticated, and the impl checks store.admins
revoke all on function private.store_admin_services_impl() from public, anon, authenticated;
revoke all on function private.store_admin_service_save_impl(bigint, boolean, boolean, jsonb, bigint) from public, anon, authenticated;
revoke all on function private.store_admin_service_queue_impl(boolean, integer, integer) from public, anon, authenticated;
revoke all on function private.store_admin_service_open_count_impl() from public, anon, authenticated;
revoke all on function private.store_admin_service_claim_impl(bigint) from public, anon, authenticated;
revoke all on function private.store_admin_service_price_impl(bigint, bigint, text) from public, anon, authenticated;
revoke all on function private.store_admin_service_done_impl(bigint, integer, bigint, text) from public, anon, authenticated;
revoke all on function private.store_admin_service_fail_impl(bigint, text) from public, anon, authenticated;
revoke all on function public.store_admin_services() from public, anon, authenticated;
revoke all on function public.store_admin_service_save(bigint, boolean, boolean, jsonb, bigint) from public, anon, authenticated;
revoke all on function public.store_admin_service_queue(boolean, integer, integer) from public, anon, authenticated;
revoke all on function public.store_admin_service_open_count() from public, anon, authenticated;
revoke all on function public.store_admin_service_claim(bigint) from public, anon, authenticated;
revoke all on function public.store_admin_service_price(bigint, bigint, text) from public, anon, authenticated;
revoke all on function public.store_admin_service_done(bigint, integer, bigint, text) from public, anon, authenticated;
revoke all on function public.store_admin_service_fail(bigint, text) from public, anon, authenticated;
grant execute on function private.store_admin_services_impl() to authenticated;
grant execute on function private.store_admin_service_save_impl(bigint, boolean, boolean, jsonb, bigint) to authenticated;
grant execute on function private.store_admin_service_queue_impl(boolean, integer, integer) to authenticated;
grant execute on function private.store_admin_service_open_count_impl() to authenticated;
grant execute on function private.store_admin_service_claim_impl(bigint) to authenticated;
grant execute on function private.store_admin_service_price_impl(bigint, bigint, text) to authenticated;
grant execute on function private.store_admin_service_done_impl(bigint, integer, bigint, text) to authenticated;
grant execute on function private.store_admin_service_fail_impl(bigint, text) to authenticated;
grant execute on function public.store_admin_services() to authenticated;
grant execute on function public.store_admin_service_save(bigint, boolean, boolean, jsonb, bigint) to authenticated;
grant execute on function public.store_admin_service_queue(boolean, integer, integer) to authenticated;
grant execute on function public.store_admin_service_open_count() to authenticated;
grant execute on function public.store_admin_service_claim(bigint) to authenticated;
grant execute on function public.store_admin_service_price(bigint, bigint, text) to authenticated;
grant execute on function public.store_admin_service_done(bigint, integer, bigint, text) to authenticated;
grant execute on function public.store_admin_service_fail(bigint, text) to authenticated;
