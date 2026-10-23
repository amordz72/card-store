-- v1.29 — «لم تعمل»: بطاقة واحدة من مشتريات المحل لم تعمل (owner decision 2026-10-23 «نعم»)
-- Testing a card consumes it, so success needs no record: the shop paid for a card it used.
-- Only a failure is recorded: the card becomes void («فُحصت: …»), its cost goes back to the shop balance
-- as a separate purchase_refund (reverses_id stays null: the order's one full reversal stays possible),
-- and the check is logged once per card (append-only).
-- Scope: the shop account's own cards from a plain purchase. Customer cards keep the report flow (v1.20,
-- no automatic compensation); IDOOM and game cards keep their own refund flows, so they are refused here.
-- Replaced: store_admin_reverse_impl (a later full reversal refunds only what is left) and
-- store_admin_shop_summary_impl (a failed card is not counted as consumed or as profit).

create table store.card_checks (
  id bigint generated always as identity primary key,
  code_id bigint not null unique references store.codes(id),   -- one recorded failure per card
  admin_id uuid not null,
  result text not null check (result in ('used', 'not_found', 'other')),
  note text check (note is null or length(note) <= 500),
  entry_id bigint not null references store.wallet_entries(id),
  created_at timestamptz not null default now()
);
create trigger card_checks_append_only before update or delete on store.card_checks
  for each row execute function private.store_block_change();
alter table store.card_checks enable row level security;
revoke all on store.card_checks from public, anon, authenticated;

create function private.store_admin_card_failed_impl(p_code_id bigint, p_result text, p_note text, p_request_id uuid)
returns table (entry_id bigint, balance_after bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  a uuid := private.store_require_admin();
  v_shop bigint := private.store_shop_id();
  r store.wallet_entries;
  k record;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into r from store.wallet_entries w where w.request_id = p_request_id;
  if not found then
    if p_result is null or p_result not in ('used', 'not_found', 'other') then raise exception 'INVALID_REASON'; end if;
    select c.id, c.status, c.cost, right(c.code, 4) as last4, o.id as order_id, o.status as order_status,
           o.customer_id, o.idoom_line, o.player_id into k
    from store.codes c join store.orders o on o.id = c.order_id
    where c.id = p_code_id
    for update of c;
    if not found or k.customer_id <> v_shop then raise exception 'CODE_NOT_FOUND'; end if;
    if exists (select 1 from store.card_checks x where x.code_id = p_code_id) then raise exception 'ALREADY_REPORTED'; end if;
    if k.status <> 'sold' or k.order_status <> 'done' or k.idoom_line is not null or k.player_id is not null
       or exists (select 1 from store.idoom_jobs j where j.code_id = p_code_id or j.order_id = k.order_id)
       or exists (select 1 from store.game_orders g where g.code_id = p_code_id or g.order_id = k.order_id) then
      raise exception 'NOT_REPORTABLE';
    end if;
    if k.cost is null then raise exception 'COST_MISSING'; end if;
    r := private.store_post_entry(v_shop, 'purchase_refund', k.cost,
           'بطاقة لم تعمل ****' || k.last4, k.order_id, null, p_request_id, a);
    update store.codes set status = 'void', voided_at = now(),
           void_reason = case p_result when 'used' then 'فُحصت: مستعملة' when 'not_found' then 'فُحصت: غير موجودة' else 'فُحصت: رد آخر' end
    where id = p_code_id;
    insert into store.card_checks (code_id, admin_id, result, note, entry_id)
    values (p_code_id, a, p_result, nullif(left(btrim(coalesce(p_note, '')), 500), ''), r.id);
  end if;
  return query select r.id, r.balance_after;
end;
$$;

-- A purchase reversal refunds only what single-card refunds have not already returned
create or replace function private.store_admin_reverse_impl(p_entry_id bigint, p_note text, p_request_id uuid)
returns table (entry_id bigint, kind text, balance_after bigint, debt_after bigint)
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

-- Shop summary: a failed card is neither consumed nor profit (its order stays «done» for the other cards)
create or replace function private.store_admin_shop_summary_impl(p_from date, p_to date)
returns table (scope text, topups bigint, consumed bigint, orders_count bigint, profit_pct bigint, real_profit bigint,
               unknown_cost_orders bigint, balance bigint, last_topup_at timestamptz, last_topup_amount bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v bigint;
  v_last store.wallet_entries;
begin
  perform private.store_require_admin();
  v := private.store_shop_id();
  select * into v_last from store.wallet_entries e
  where e.customer_id = v and e.kind = 'shop_topup' and not exists (select 1 from store.wallet_entries x where x.reverses_id = e.id)
  order by e.id desc limit 1;
  return query
  with scopes(scope, t_from, t_to) as (values
    ('all', null::timestamptz, null::timestamptz),
    ('since_last', v_last.created_at, null::timestamptz),
    ('range', p_from::timestamptz, (p_to + 1)::timestamptz)
  ),
  failed as (   -- per order: refunded amount, base value and cost of its failed cards
    select k.order_id, sum(w.amount) as refunded, sum(o2.base_amount / o2.qty) as base, sum(k.cost) as cost
    from store.card_checks x
    join store.codes k on k.id = x.code_id
    join store.orders o2 on o2.id = k.order_id
    join store.wallet_entries w on w.id = x.entry_id
    group by k.order_id
  )
  select s.scope,
         coalesce((select sum(e.d_balance) from store.wallet_entries e
                   where e.customer_id = v and e.kind in ('shop_topup', 'shop_topup_refund')
                     and (s.t_from is null or e.created_at >= s.t_from) and (s.t_to is null or e.created_at < s.t_to)), 0)::bigint,
         coalesce(sum(o.charged_amount - coalesce(f.refunded, 0)), 0)::bigint,
         count(o.id),
         coalesce(sum((o.base_amount - coalesce(f.base, 0)) - (o.charged_amount - coalesce(f.refunded, 0))), 0)::bigint,
         coalesce(sum((o.base_amount - coalesce(f.base, 0)) - (o.cost_amount - coalesce(f.cost, 0))) filter (where o.cost_amount is not null), 0)::bigint,
         count(o.id) filter (where o.cost_amount is null),
         (select c.balance from store.customers c where c.id = v),
         v_last.created_at, v_last.amount
  from scopes s
  left join store.orders o on o.customer_id = v and o.status = 'done'
    and (s.t_from is null or o.created_at >= s.t_from) and (s.t_to is null or o.created_at < s.t_to)
  left join failed f on f.order_id = o.id
  group by s.scope, s.t_from, s.t_to
  order by array_position(array['all', 'since_last', 'range'], s.scope);
end;
$$;

create function public.store_admin_card_failed(p_code_id bigint, p_result text, p_note text, p_request_id uuid)
returns table (entry_id bigint, balance_after bigint)
language sql set search_path = '' as $$ select * from private.store_admin_card_failed_impl(p_code_id, p_result, p_note, p_request_id); $$;

-- ---------------------------------------------------------------------
-- Grants (same rule as v1) for the new/replaced functions only
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_admin_card_failed_impl', 'store_admin_card_failed',
                        'store_admin_reverse_impl', 'store_admin_shop_summary_impl')
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
end $$;
