-- v1.25 — شحن الألعاب بمعرّف اللاعب (Free Fire) — owner decisions 2026-10-23
-- Decision record: developer/projects/card-store/FREE-FIRE-TOPUP-2026-10-23.md
--  * The top-up uses a card from our stock (e.g. a Garena card). A card marked «يُشحن بالمعرّف»
--    (store.products.player_topup) stays in the store as usual: a customer who wants the code buys it there.
--  * The service has one switch: it is open while at least one operator pressed «متاح» (owner or worker).
--    An operator who forgets is switched off after 30 minutes without his page open.
--  * Workers: customer accounts the owner marks as operators (store.customers.game_operator). They log in
--    like customers and see only the top-up queue. The owner works the same queue from his own session.
--  * The customer pays his usual price for that card when he orders; the card is taken from stock at once and
--    is never shown to him. An operator takes the order («أبدأ»), redeems the card for the player id by hand,
--    then: done (with the site's transaction number) / used card → another card from stock / not done → full
--    refund, the card back to stock if it was not used.
--  * The customer may cancel only while the order waits (full refund, card back to stock).
-- Additive only: new columns, new tables, new functions, create or replace of existing ones (same signatures).

alter table store.products add column player_topup boolean not null default false;
alter table store.customers add column game_operator boolean not null default false;
alter table store.orders add column player_id text;
alter table store.settings add column game_topup_url text
  check (game_topup_url is null or (game_topup_url ~ '^https://[^\s]+$' and length(game_topup_url) <= 300));

-- Who pressed «متاح»: the owner (admin_id) or a worker account (customer_id)
create table store.game_presence (
  id bigint generated always as identity primary key,
  admin_id uuid unique,
  customer_id bigint unique references store.customers(id),
  available boolean not null default false,
  last_seen_at timestamptz not null default now(),
  check ((admin_id is null) <> (customer_id is null))
);

create table store.game_orders (
  id bigint generated always as identity primary key,
  customer_id bigint not null references store.customers(id),
  product_id bigint not null references store.products(id),
  order_id bigint not null unique references store.orders(id),
  code_id bigint references store.codes(id),
  player_id text not null check (player_id ~ '^[0-9]{5,15}$'),
  status text not null default 'queued' check (status in ('queued', 'claimed', 'done', 'failed', 'cancelled')),
  txn_ref text check (txn_ref is null or length(txn_ref) <= 60),
  reason text check (reason is null or length(reason) <= 300),
  cards_used int not null default 0,         -- cards found already used and replaced
  request_id uuid not null unique,
  claimed_admin uuid,
  claimed_operator bigint references store.customers(id),
  claimed_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);
create index on store.game_orders (customer_id, id desc);
create index game_orders_open on store.game_orders (id) where status in ('queued', 'claimed');

alter table store.game_presence enable row level security;
alter table store.game_orders enable row level security;
revoke all on store.game_presence from public, anon, authenticated;
revoke all on store.game_orders from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create function private.store_game_player_id(p text) returns text
language plpgsql immutable set search_path = '' as $$
declare v text := regexp_replace(coalesce(p, ''), '\s', '', 'g');
begin
  if v !~ '^[0-9]{5,15}$' then raise exception 'INVALID_PLAYER_ID'; end if;
  return v;
end;
$$;

create function private.store_game_open() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from store.game_presence g where g.available and g.last_seen_at > now() - interval '30 minutes');
$$;

-- The operator calling: the owner (no token, his Supabase session) or a worker (his customer token).
create function private.store_game_operator(p_token text, out admin_id uuid, out operator_id bigint)
language plpgsql security definer set search_path = '' as $$
begin
  if p_token is null then
    admin_id := private.store_require_admin();
    return;
  end if;
  operator_id := private.store_session_customer(p_token);
  if not exists (select 1 from store.customers c where c.id = operator_id and c.game_operator and not c.is_shop) then
    raise exception 'NOT_OPERATOR';
  end if;
end;
$$;

-- Refund once; the card goes back to stock when p_card_back (it was not redeemed).
create function private.store_game_refund(p_game_id bigint, p_card_back boolean, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  g store.game_orders;
  e store.wallet_entries;
begin
  select * into g from store.game_orders where id = p_game_id for update;
  select * into e from store.wallet_entries w where w.order_id = g.order_id and w.kind = 'purchase';
  if found and not exists (select 1 from store.wallet_entries x where x.reverses_id = e.id) then
    perform private.store_post_entry(e.customer_id, 'purchase_refund', e.amount, p_note, e.order_id, e.id, null, null);
  end if;
  update store.orders set status = 'refunded' where id = g.order_id;
  if p_card_back and g.code_id is not null then
    update store.codes set status = 'available', order_id = null, sold_at = null where id = g.code_id and status = 'sold';
    update store.game_orders set code_id = null where id = g.id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Customer
-- ---------------------------------------------------------------------
-- is_open: the service is on now; is_operator: this account works the queue
create function private.store_game_status_impl(p_token text) returns table (is_open boolean, is_operator boolean)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return query select private.store_game_open(),
                      coalesce((select c.game_operator and not c.is_shop from store.customers c where c.id = v), false);
end;
$$;

-- Cards that can be topped up by player id, with stock
create function private.store_game_cards_impl(p_token text) returns setof bigint
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_session_customer(p_token);
  return query
  select p.id from store.products p join store.brands b on b.id = p.brand_id
  where p.player_topup and p.active and b.active
  order by b.sort, p.sort, p.base_price;
end;
$$;

-- Pay now (the usual price of that card), take a card from stock, queue the order. Idempotent on p_request_id.
create function private.store_game_create_impl(p_token text, p_product_id bigint, p_player_id text, p_request_id uuid)
returns table (game_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  g store.game_orders;
  v_player text;
  b record;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into g from store.game_orders x where x.request_id = p_request_id;
  if found then
    if g.customer_id <> v then raise exception 'REQUEST_ID_CONFLICT'; end if;
  else
    v_player := private.store_game_player_id(p_player_id);
    if exists (select 1 from store.customers c where c.id = v and c.is_shop) then raise exception 'CUSTOMER_NOT_FOUND'; end if;
    if not exists (select 1 from store.products p where p.id = p_product_id and p.player_topup) then raise exception 'NOT_GAME_CARD'; end if;
    if not private.store_game_open() then raise exception 'GAME_CLOSED'; end if;
    if exists (select 1 from store.game_orders x where x.customer_id = v and x.player_id = v_player and x.status in ('queued', 'claimed')) then
      raise exception 'GAME_PLAYER_BUSY';
    end if;
    if (select count(*) from store.game_orders x where x.customer_id = v and x.status in ('queued', 'claimed')) >= 5
       or (select count(*) from store.game_orders x where x.customer_id = v and x.created_at > now() - interval '1 hour') >= 20 then
      raise exception 'GAME_TOO_MANY';
    end if;
    -- own request id for the purchase, so the card can never be read back through store_buy
    select * into b from private.store_buy_core(v, p_product_id, 1, gen_random_uuid());
    update store.orders set player_id = v_player where id = b.order_id;
    insert into store.game_orders (customer_id, product_id, order_id, code_id, player_id, request_id)
    select v, p_product_id, b.order_id, k.id, v_player, p_request_id from store.codes k where k.order_id = b.order_id
    returning * into g;
  end if;
  return query select g.id, g.status;
end;
$$;

create function private.store_game_orders_impl(p_token text, p_limit int, p_offset int)
returns table (game_id bigint, player_id text, product_name text, status text, charged_amount bigint, txn_ref text,
               created_at timestamptz, finished_at timestamptz, total_count bigint)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select g.id, g.player_id, p.name, g.status, o.charged_amount, g.txn_ref, g.created_at, g.finished_at, count(*) over ()
  from store.game_orders g
  join store.products p on p.id = g.product_id
  join store.orders o on o.id = g.order_id
  where g.customer_id = v
  order by g.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- Player ids of his own recent orders (suggestions only)
create function private.store_game_recent_ids_impl(p_token text) returns setof text
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select x.player_id from (
    select g.player_id, max(g.id) as last_id from store.game_orders g
    where g.customer_id = v and g.status <> 'cancelled' group by g.player_id) x
  order by x.last_id desc limit 5;
end;
$$;

-- Only while it waits: once an operator started it, the card may be redeemed already.
create function private.store_game_cancel_impl(p_token text, p_game_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  v_status text;
begin
  update store.game_orders g set status = 'cancelled', finished_at = now()
   where g.id = p_game_id and g.customer_id = v and g.status = 'queued'
  returning g.status into v_status;
  if v_status is null then raise exception 'NOT_CANCELLABLE'; end if;
  perform private.store_game_refund(p_game_id, true, 'شحن لعبة: أُلغي الطلب، أُعيد المبلغ');
  return v_status;
end;
$$;

-- ---------------------------------------------------------------------
-- Operators (owner: p_token null; worker: his token)
-- ---------------------------------------------------------------------
create function private.store_game_presence_impl(p_token text, p_available boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare o record;
begin
  select * into o from private.store_game_operator(p_token);
  if o.admin_id is not null then
    insert into store.game_presence (admin_id, available, last_seen_at) values (o.admin_id, coalesce(p_available, false), now())
    on conflict (admin_id) do update set available = coalesce(p_available, store.game_presence.available), last_seen_at = now();
  else
    insert into store.game_presence (customer_id, available, last_seen_at) values (o.operator_id, coalesce(p_available, false), now())
    on conflict (customer_id) do update set available = coalesce(p_available, store.game_presence.available), last_seen_at = now();
  end if;
  -- p_available null = «I am still here» (sent every minute while the queue page is open)
  return (select g.available and g.last_seen_at > now() - interval '30 minutes' from store.game_presence g
          where g.admin_id is not distinct from o.admin_id and g.customer_id is not distinct from o.operator_id);
end;
$$;

-- Who is available now (names only), and the top-up site link
create function private.store_game_board_impl(p_token text)
returns table (is_open boolean, me_available boolean, available_names text[], url text)
language plpgsql security definer set search_path = '' as $$
declare o record;
begin
  select * into o from private.store_game_operator(p_token);
  return query select
    private.store_game_open(),
    coalesce((select g.available and g.last_seen_at > now() - interval '30 minutes' from store.game_presence g
              where g.admin_id is not distinct from o.admin_id and g.customer_id is not distinct from o.operator_id), false),
    array(select coalesce(c.name, 'المدير') from store.game_presence g left join store.customers c on c.id = g.customer_id
          where g.available and g.last_seen_at > now() - interval '30 minutes' order by g.id),
    (select s.game_topup_url from store.settings s where s.id = 1);
end;
$$;

-- Queue: p_open true = waiting / in progress (oldest first), false = finished (newest first).
-- The card code is shown only to the operator who took the order.
create function private.store_game_queue_impl(p_token text, p_open boolean, p_limit int, p_offset int)
returns table (game_id bigint, customer_name text, player_id text, product_name text, status text, charged_amount bigint,
               code text, serial text, mine boolean, taken_by text, txn_ref text, reason text, cards_used int,
               created_at timestamptz, claimed_at timestamptz, finished_at timestamptz, total_count bigint)
language plpgsql security definer set search_path = '' as $$
declare o record;
begin
  select * into o from private.store_game_operator(p_token);
  return query
  select g.id, c.name, g.player_id, p.name, g.status, ord.charged_amount,
         case when g.status = 'claimed' and mine.v then k.code end,
         case when g.status = 'claimed' and mine.v then k.serial end,
         mine.v,
         case when g.claimed_operator is not null then oc.name when g.claimed_admin is not null then 'المدير' end,
         g.txn_ref, g.reason, g.cards_used, g.created_at, g.claimed_at, g.finished_at, count(*) over ()
  from store.game_orders g
  join store.customers c on c.id = g.customer_id
  join store.products p on p.id = g.product_id
  join store.orders ord on ord.id = g.order_id
  left join store.codes k on k.id = g.code_id
  left join store.customers oc on oc.id = g.claimed_operator
  cross join lateral (select (g.claimed_admin is not distinct from o.admin_id and g.claimed_operator is not distinct from o.operator_id
                              and (g.claimed_admin is not null or g.claimed_operator is not null)) as v) mine
  where (g.status in ('queued', 'claimed')) = coalesce(p_open, true)
  order by case when coalesce(p_open, true) then g.id end asc, g.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 200) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create function private.store_game_open_count_impl(p_token text) returns bigint
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_game_operator(p_token);
  return (select count(*) from store.game_orders g where g.status = 'queued');
end;
$$;

-- «أبدأ» takes a waiting order (from now on the customer cannot cancel); «تراجع» gives it back to the queue.
create function private.store_game_claim_impl(p_token text, p_game_id bigint, p_claim boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  o record;
  v text;
begin
  select * into o from private.store_game_operator(p_token);
  if coalesce(p_claim, true) then
    update store.game_orders set status = 'claimed', claimed_admin = o.admin_id, claimed_operator = o.operator_id, claimed_at = now()
     where id = p_game_id and status = 'queued' returning status into v;
  else
    update store.game_orders set status = 'queued', claimed_admin = null, claimed_operator = null, claimed_at = null
     where id = p_game_id and status = 'claimed'
       and ((claimed_admin is not distinct from o.admin_id and claimed_operator is not distinct from o.operator_id) or o.admin_id is not null)
    returning status into v;
  end if;
  if v is null then raise exception 'GAME_NOT_OPEN'; end if;
  return v;
end;
$$;

-- p_result: 'done' (txn number), 'used_card' (card already used: refund if no other card, else the next card),
--           'failed' (not done: refund; p_card_back = the card was not redeemed and returns to stock).
-- Only the operator who took it (or the owner).
create function private.store_game_finish_impl(p_token text, p_game_id bigint, p_result text, p_txn_ref text, p_reason text, p_card_back boolean)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  o record;
  g store.game_orders;
  v_next bigint;
begin
  select * into o from private.store_game_operator(p_token);
  select * into g from store.game_orders x where x.id = p_game_id and x.status = 'claimed'
     and ((x.claimed_admin is not distinct from o.admin_id and x.claimed_operator is not distinct from o.operator_id) or o.admin_id is not null)
  for update;
  if not found then raise exception 'GAME_NOT_OPEN'; end if;
  if p_result = 'done' then
    update store.game_orders set status = 'done', txn_ref = nullif(left(btrim(coalesce(p_txn_ref, '')), 60), ''), finished_at = now()
     where id = g.id;
    return 'done';
  elsif p_result = 'used_card' then
    -- the shop's loss: that card is voided, the customer keeps his order with the next card
    update store.codes set status = 'void', void_reason = 'شحن لعبة: البطاقة مستعملة (طلب ' || g.id || ')', voided_at = now()
     where id = g.code_id;
    select k.id into v_next from store.codes k
     where k.product_id = g.product_id and k.status = 'available' and not k.frozen order by k.id limit 1 for update skip locked;
    if v_next is null then
      update store.game_orders set status = 'failed', cards_used = cards_used + 1, finished_at = now(),
             reason = left('البطاقة مستعملة ولا توجد بطاقة أخرى' || coalesce(' · ' || nullif(btrim(p_reason), ''), ''), 300)
       where id = g.id;
      perform private.store_game_refund(g.id, false, 'شحن لعبة: لم يتم، أُعيد المبلغ');
      return 'failed';
    end if;
    update store.codes set status = 'sold', order_id = g.order_id, sold_at = now() where id = v_next;
    update store.game_orders set code_id = v_next, cards_used = cards_used + 1 where id = g.id;
    return 'claimed';
  elsif p_result = 'failed' then
    update store.game_orders set status = 'failed', reason = nullif(left(btrim(coalesce(p_reason, '')), 300), ''), finished_at = now()
     where id = g.id;
    perform private.store_game_refund(g.id, coalesce(p_card_back, false), 'شحن لعبة: لم يتم، أُعيد المبلغ');
    return 'failed';
  end if;
  raise exception 'INVALID_RESULT';
end;
$$;

-- ---------------------------------------------------------------------
-- Owner settings
-- ---------------------------------------------------------------------
create function private.store_admin_set_game_operator_impl(p_customer_id bigint, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.customers c set game_operator = coalesce(p_enabled, false) where c.id = p_customer_id and not c.is_shop;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  if not coalesce(p_enabled, false) then
    update store.game_presence set available = false where customer_id = p_customer_id;
  end if;
end;
$$;

create function private.store_admin_game_operators_impl() returns setof bigint
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select c.id from store.customers c where c.game_operator and not c.is_shop order by c.id;
end;
$$;

create function private.store_admin_set_player_topup_impl(p_product_id bigint, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.products p set player_topup = coalesce(p_enabled, false) where p.id = p_product_id;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
end;
$$;

create function private.store_admin_player_topup_products_impl() returns setof bigint
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select p.id from store.products p where p.player_topup order by p.id;
end;
$$;

create function private.store_admin_set_game_url_impl(p_url text) returns void
language plpgsql security definer set search_path = '' as $$
declare v text := nullif(btrim(coalesce(p_url, '')), '');
begin
  perform private.store_require_admin();
  if v is not null and (v !~ '^https://[^\s]+$' or length(v) > 300) then raise exception 'INVALID_LINK'; end if;
  update store.settings set game_topup_url = v, updated_at = now() where id = 1;
end;
$$;

-- ---------------------------------------------------------------------
-- Existing functions, same signatures (create or replace)
-- ---------------------------------------------------------------------
-- The card of a top-up order is never shown to the customer (he could redeem it himself before the operator).
create or replace function private.store_order_codes_impl(p_token text, p_order_id bigint)
returns table (code text, serial text, status text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v bigint := private.store_session_customer(p_token);
  v_line text;
  v_player text;
begin
  select o.idoom_line, o.player_id into v_line, v_player from store.orders o where o.id = p_order_id and o.customer_id = v;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  return query
  select case when v_line is not null then 'تعبئة إيدوم للخط ' || v_line
              when v_player is not null then 'شحن بمعرّف اللاعب ' || v_player
              else k.code end,
         case when v_line is null and v_player is null then k.serial end, k.status
  from store.codes k where k.order_id = p_order_id order by k.id;
end;
$$;

create or replace function private.store_order_codes_v2_impl(p_token text, p_order_id bigint)
returns table (code_id bigint, code text, serial text, status text, report_status text, report_reason text, can_report boolean)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
declare v_days int := (select s.report_days from store.settings s where s.id = 1);
declare v_player text;
begin
  select o.player_id into v_player from store.orders o where o.id = p_order_id and o.customer_id = v;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_player is not null then
    -- top-up order: no code, its state instead (a voided «used» card stays hidden too)
    return query
    select null::bigint, 'شحن بمعرّف اللاعب ' || g.player_id,
           case g.status when 'done' then 'تم الشحن' || coalesce(' · رقم العملية ' || g.txn_ref, '')
                         when 'failed' then 'لم يتم — أُعيد المبلغ'
                         when 'cancelled' then 'أُلغي — أُعيد المبلغ'
                         when 'claimed' then 'قيد التنفيذ'
                         else 'في الانتظار' end,
           'sold'::text, null::text, null::text, false
    from store.game_orders g where g.order_id = p_order_id;
    return;
  end if;
  return query
  select k.id,
         case when o.idoom_line is null then k.code else 'تعبئة إيدوم للخط ' || o.idoom_line end,
         case when o.idoom_line is null then k.serial end,
         k.status, r.status, r.reason,
         (o.idoom_line is null and r.id is null and k.status = 'sold' and o.status = 'done'
          and k.sold_at > now() - make_interval(days => v_days))
  from store.codes k join store.orders o on o.id = k.order_id
  left join store.card_reports r on r.code_id = k.id
  where k.order_id = p_order_id order by k.id;
end;
$$;

-- Reports: a top-up card is not the customer's card to report (its result is the order's status).
create or replace function private.store_report_code_impl(p_token text, p_code_id bigint, p_reason text, p_note text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  v_days int := (select s.report_days from store.settings s where s.id = 1);
  k record;
  v_id bigint;
begin
  if p_reason is null or p_reason not in ('used', 'not_found', 'rejected', 'other') then raise exception 'INVALID_REASON'; end if;
  select c.id, c.status, c.sold_at, o.status as order_status, o.idoom_line, o.player_id into k
  from store.codes c join store.orders o on o.id = c.order_id
  where c.id = p_code_id and o.customer_id = v
  for update of c;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if k.status <> 'sold' or k.order_status <> 'done' or k.idoom_line is not null or k.player_id is not null then
    raise exception 'NOT_REPORTABLE';
  end if;
  if k.sold_at <= now() - make_interval(days => v_days) then raise exception 'REPORT_WINDOW_CLOSED'; end if;
  if exists (select 1 from store.card_reports r where r.code_id = p_code_id) then raise exception 'ALREADY_REPORTED'; end if;
  insert into store.card_reports (code_id, customer_id, reason, note)
  values (p_code_id, v, p_reason, nullif(left(btrim(coalesce(p_note, '')), 500), '')) returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------
create function public.store_game_status(p_token text) returns table (is_open boolean, is_operator boolean)
language sql set search_path = '' as $$ select * from private.store_game_status_impl(p_token); $$;
create function public.store_game_cards(p_token text) returns setof bigint
language sql set search_path = '' as $$ select * from private.store_game_cards_impl(p_token); $$;
create function public.store_game_create(p_token text, p_product_id bigint, p_player_id text, p_request_id uuid)
returns table (game_id bigint, status text)
language sql set search_path = '' as $$ select * from private.store_game_create_impl(p_token, p_product_id, p_player_id, p_request_id); $$;
create function public.store_game_orders(p_token text, p_limit int, p_offset int)
returns table (game_id bigint, player_id text, product_name text, status text, charged_amount bigint, txn_ref text,
               created_at timestamptz, finished_at timestamptz, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_game_orders_impl(p_token, p_limit, p_offset); $$;
create function public.store_game_recent_ids(p_token text) returns setof text
language sql set search_path = '' as $$ select * from private.store_game_recent_ids_impl(p_token); $$;
create function public.store_game_cancel(p_token text, p_game_id bigint) returns text
language sql set search_path = '' as $$ select private.store_game_cancel_impl(p_token, p_game_id); $$;
create function public.store_game_presence(p_token text, p_available boolean) returns boolean
language sql set search_path = '' as $$ select private.store_game_presence_impl(p_token, p_available); $$;
create function public.store_game_board(p_token text)
returns table (is_open boolean, me_available boolean, available_names text[], url text)
language sql set search_path = '' as $$ select * from private.store_game_board_impl(p_token); $$;
create function public.store_game_queue(p_token text, p_open boolean, p_limit int, p_offset int)
returns table (game_id bigint, customer_name text, player_id text, product_name text, status text, charged_amount bigint,
               code text, serial text, mine boolean, taken_by text, txn_ref text, reason text, cards_used int,
               created_at timestamptz, claimed_at timestamptz, finished_at timestamptz, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_game_queue_impl(p_token, p_open, p_limit, p_offset); $$;
create function public.store_game_open_count(p_token text) returns bigint
language sql set search_path = '' as $$ select private.store_game_open_count_impl(p_token); $$;
create function public.store_game_claim(p_token text, p_game_id bigint, p_claim boolean) returns text
language sql set search_path = '' as $$ select private.store_game_claim_impl(p_token, p_game_id, p_claim); $$;
create function public.store_game_finish(p_token text, p_game_id bigint, p_result text, p_txn_ref text, p_reason text, p_card_back boolean)
returns text
language sql set search_path = '' as $$ select private.store_game_finish_impl(p_token, p_game_id, p_result, p_txn_ref, p_reason, p_card_back); $$;
create function public.store_admin_set_game_operator(p_customer_id bigint, p_enabled boolean) returns void
language sql set search_path = '' as $$ select private.store_admin_set_game_operator_impl(p_customer_id, p_enabled); $$;
create function public.store_admin_game_operators() returns setof bigint
language sql set search_path = '' as $$ select * from private.store_admin_game_operators_impl(); $$;
create function public.store_admin_set_player_topup(p_product_id bigint, p_enabled boolean) returns void
language sql set search_path = '' as $$ select private.store_admin_set_player_topup_impl(p_product_id, p_enabled); $$;
create function public.store_admin_player_topup_products() returns setof bigint
language sql set search_path = '' as $$ select * from private.store_admin_player_topup_products_impl(); $$;
create function public.store_admin_set_game_url(p_url text) returns void
language sql set search_path = '' as $$ select private.store_admin_set_game_url_impl(p_url); $$;

-- ---------------------------------------------------------------------
-- Grants: helpers private to the functions; store_admin_* to authenticated; the rest (customer and
-- operator calls: a worker is anon with his token, the owner is authenticated) to anon and authenticated.
-- ---------------------------------------------------------------------
revoke all on function private.store_game_player_id(text) from public, anon, authenticated;
revoke all on function private.store_game_open() from public, anon, authenticated;
revoke all on function private.store_game_operator(text) from public, anon, authenticated;
revoke all on function private.store_game_refund(bigint, boolean, text) from public, anon, authenticated;
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_game_status_impl', 'store_game_status', 'store_game_cards_impl', 'store_game_cards',
                        'store_game_create_impl', 'store_game_create', 'store_game_orders_impl', 'store_game_orders',
                        'store_game_recent_ids_impl', 'store_game_recent_ids', 'store_game_cancel_impl', 'store_game_cancel',
                        'store_game_presence_impl', 'store_game_presence', 'store_game_board_impl', 'store_game_board',
                        'store_game_queue_impl', 'store_game_queue', 'store_game_open_count_impl', 'store_game_open_count',
                        'store_game_claim_impl', 'store_game_claim', 'store_game_finish_impl', 'store_game_finish',
                        'store_admin_set_game_operator_impl', 'store_admin_set_game_operator',
                        'store_admin_game_operators_impl', 'store_admin_game_operators',
                        'store_admin_set_player_topup_impl', 'store_admin_set_player_topup',
                        'store_admin_player_topup_products_impl', 'store_admin_player_topup_products',
                        'store_admin_set_game_url_impl', 'store_admin_set_game_url')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.name like 'store\_admin\_%' then
      if f.sch = 'public' or f.name like '%\_impl' then
        execute format('grant execute on function %s to authenticated', f.sig);
      end if;
    elsif f.name like '%\_impl' or f.sch = 'public' then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end;
$$;
