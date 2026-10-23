-- v1.28 — لا تضيع أي بطاقة: استرجاع الملغاة كـ«مشكوك فيها» واستعمالها واحدة بواحدة
-- Owner decision 2026-10-23 (pattern 17, item 13, phase 1): a voided card that was never delivered to
-- anyone can come back as «مشكوك فيها». A suspect card is internal to the owner:
--   * it is stored as available + frozen + suspect, so every automatic path (customer purchase, catalog,
--     cost, IDOOM, game top-up) already skips it — those paths only take `available and not frozen`;
--   * «فك التجميد» never touches it; only «اعتبرها عادية» (set_suspect false) returns it to normal sale;
--   * the owner takes it one card at a time through the shop account (store_admin_use_suspect),
--     charged at its cost like any shop purchase, so it shows in «مشترياتي».
-- A void card that belongs to an order (delivered to a buyer, refunded, game «used card») is never restored.
-- Every restore is logged (append-only). Existing behaviour of other functions is unchanged,
-- except freeze/unfreeze, which now skips suspect cards.

alter table store.codes add column suspect boolean not null default false;
alter table store.codes add column restored_at timestamptz;

create table store.code_restores (
  id bigint generated always as identity primary key,
  code_id bigint not null references store.codes(id),
  admin_id uuid not null,
  reason text not null check (length(reason) between 1 and 300),
  void_reason_before text,
  voided_at_before timestamptz,
  created_at timestamptz not null default now()
);
create index on store.code_restores (code_id);
create trigger code_restores_append_only before update or delete on store.code_restores
  for each row execute function private.store_block_change();
alter table store.code_restores enable row level security;
revoke all on store.code_restores from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Restore: void and never in an order → available, frozen, suspect
-- ---------------------------------------------------------------------
create function private.store_restore_codes(p_admin uuid, p_code_ids bigint[], p_reason text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if nullif(btrim(p_reason), '') is null then raise exception 'REASON_REQUIRED'; end if;
  with picked as (
    select k.id, k.void_reason, k.voided_at from store.codes k
    where k.id = any (p_code_ids) and k.status = 'void' and k.order_id is null
    for update
  ), logged as (
    insert into store.code_restores (code_id, admin_id, reason, void_reason_before, voided_at_before)
    select id, p_admin, left(btrim(p_reason), 300), void_reason, voided_at from picked
  )
  update store.codes k set status = 'available', frozen = true, suspect = true,
         void_reason = null, voided_at = null, restored_at = now()
  from picked where k.id = picked.id;
  get diagnostics n = row_count;
  return n;
end;
$$;

create function private.store_admin_codes_restore_impl(p_code_ids bigint[], p_reason text) returns int
language plpgsql security definer set search_path = '' as $$
begin
  return private.store_restore_codes(private.store_require_admin(), p_code_ids, p_reason);
end;
$$;

-- The owner pastes the codes he knows are good (one per line; a serial after ; , | is ignored).
-- Only that batch is searched, so a same code in another product (e.g. DEMO) is never touched.
create function private.store_admin_batch_restore_impl(p_batch_id bigint, p_lines text, p_reason text)
returns table (restored int, not_void int, not_found int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  a uuid := private.store_require_admin();
  v_ids bigint[];
  v_lines int;
  v_found int;
  v_restored int;
begin
  if not exists (select 1 from store.code_batches b where b.id = p_batch_id) then raise exception 'BATCH_NOT_FOUND'; end if;
  with pasted as (
    select distinct btrim(split_part(l, coalesce(substring(l from '[;,|]'), ';'), 1)) as code
    from regexp_split_to_table(coalesce(p_lines, ''), E'\r?\n') as l
  )
  select count(*) filter (where p.code <> ''), count(k.id), array_agg(k.id) filter (where k.status = 'void' and k.order_id is null)
  into v_lines, v_found, v_ids
  from pasted p left join store.codes k on k.batch_id = p_batch_id and k.code = p.code
  where p.code <> '';
  if coalesce(v_lines, 0) = 0 then raise exception 'NO_CODES'; end if;
  v_restored := private.store_restore_codes(a, coalesce(v_ids, '{}'), p_reason);
  return query select v_restored, v_found - v_restored, v_lines - v_found;
end;
$$;

-- Manual move in or out of «مشكوك فيها» (in stock only).
-- true: available card → frozen + suspect. false: suspect → normal, back on sale.
create function private.store_admin_codes_set_suspect_impl(p_code_ids bigint[], p_suspect boolean) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.store_require_admin();
  if p_suspect is null then raise exception 'INVALID_VALUE'; end if;
  update store.codes set suspect = p_suspect, frozen = p_suspect
  where id = any (p_code_ids) and status = 'available' and suspect <> p_suspect;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Freeze/unfreeze never changes a suspect card (unfreezing it would put it on sale to customers)
create or replace function private.store_admin_codes_freeze_impl(p_code_ids bigint[], p_frozen boolean) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.store_require_admin();
  update store.codes set frozen = coalesce(p_frozen, true)
  where id = any (p_code_ids) and status = 'available' and not suspect and frozen <> coalesce(p_frozen, true);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- Use one suspect card: a shop purchase of exactly that card, at its cost
-- ---------------------------------------------------------------------
create function private.store_admin_use_suspect_impl(p_product_id bigint, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_shop bigint;
  o store.orders;
  p record;
  c store.customers;
  k record;
begin
  perform private.store_require_admin();
  v_shop := private.store_shop_id();
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into o from store.orders where request_id = p_request_id;
  if found then
    if o.customer_id <> v_shop then raise exception 'REQUEST_ID_CONFLICT'; end if;
  else
    select pr.id, pr.base_price into p from store.products pr where pr.id = p_product_id;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    select * into c from store.customers where id = v_shop for update;
    select k2.id, k2.cost into k from store.codes k2
    where k2.product_id = p.id and k2.status = 'available' and k2.suspect
    order by k2.id limit 1 for update skip locked;
    if not found then raise exception 'NO_SUSPECT_CARD'; end if;
    if k.cost is null then raise exception 'COST_MISSING'; end if;
    if c.balance < k.cost then raise exception 'INSUFFICIENT_BALANCE'; end if;
    insert into store.orders (customer_id, product_id, qty, base_amount, pct, charged_amount, cost_amount, balance_after, request_id, price_mode, price_value)
    values (v_shop, p.id, 1, p.base_price, 0, k.cost, k.cost, c.balance - k.cost, p_request_id, 'cost', null)
    returning * into o;
    update store.codes set status = 'sold', order_id = o.id, sold_at = now(), frozen = false where id = k.id;
    perform private.store_post_entry(v_shop, 'purchase', k.cost, 'بطاقة مشكوك فيها', o.id, null, null, null);
  end if;
  return query select o.id, pr.name, o.qty,
         coalesce((select jsonb_agg(jsonb_build_object('code_id', k5.id, 'code', k5.code, 'serial', k5.serial) order by k5.id)
                   from store.codes k5 where k5.order_id = o.id), '[]'::jsonb)
  from store.products pr where pr.id = o.product_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Reads for the stock page
-- ---------------------------------------------------------------------
create function private.store_admin_suspect_stock_impl()
returns table (product_id bigint, product_name text, brand text, suspect bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select p.id, p.name, b.name, count(*)
  from store.codes k join store.products p on p.id = k.product_id join store.brands b on b.id = p.brand_id
  where k.status = 'available' and k.suspect
  group by p.id, b.id order by b.sort, p.sort, p.id;
end;
$$;

-- v2: «frozen» no longer counts suspect cards; suspect is its own count
create function private.store_admin_batches_v2_impl(p_product_id bigint, p_limit int, p_offset int)
returns table (batch_id bigint, product_id bigint, product_name text, brand text, supplier text, cost bigint, created_at timestamptz,
               added int, available bigint, frozen bigint, suspect bigint, sold bigint, voided bigint, total_count bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select bt.id, p.id, p.name, b.name, s.name, bt.cost, bt.created_at, bt.added,
         count(k.id) filter (where k.status = 'available' and not k.frozen),
         count(k.id) filter (where k.status = 'available' and k.frozen and not k.suspect),
         count(k.id) filter (where k.status = 'available' and k.suspect),
         count(k.id) filter (where k.status = 'sold'),
         count(k.id) filter (where k.status = 'void'),
         count(*) over ()
  from store.code_batches bt
  join store.products p on p.id = bt.product_id
  join store.brands b on b.id = p.brand_id
  join store.suppliers s on s.id = bt.supplier_id
  left join store.codes k on k.batch_id = bt.id
  where p_product_id is null or bt.product_id = p_product_id
  group by bt.id, p.id, b.id, s.id
  order by bt.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create function private.store_admin_batch_codes_v2_impl(p_batch_id bigint)
returns table (code_id bigint, masked_code text, serial text, status text, frozen boolean, suspect boolean,
               cost bigint, sold_at timestamptz, void_reason text, restored_at timestamptz)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select k.id, '****' || right(k.code, 4), k.serial, k.status, k.frozen, k.suspect,
         k.cost, k.sold_at, k.void_reason, k.restored_at
  from store.codes k where k.batch_id = p_batch_id order by k.id;
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------
create function public.store_admin_codes_restore(p_code_ids bigint[], p_reason text) returns int
language sql set search_path = '' as $$ select private.store_admin_codes_restore_impl(p_code_ids, p_reason); $$;
create function public.store_admin_batch_restore(p_batch_id bigint, p_lines text, p_reason text)
returns table (restored int, not_void int, not_found int)
language sql set search_path = '' as $$ select * from private.store_admin_batch_restore_impl(p_batch_id, p_lines, p_reason); $$;
create function public.store_admin_codes_set_suspect(p_code_ids bigint[], p_suspect boolean) returns int
language sql set search_path = '' as $$ select private.store_admin_codes_set_suspect_impl(p_code_ids, p_suspect); $$;
create function public.store_admin_use_suspect(p_product_id bigint, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language sql set search_path = '' as $$ select * from private.store_admin_use_suspect_impl(p_product_id, p_request_id); $$;
create function public.store_admin_suspect_stock()
returns table (product_id bigint, product_name text, brand text, suspect bigint)
language sql set search_path = '' as $$ select * from private.store_admin_suspect_stock_impl(); $$;
create function public.store_admin_batches_v2(p_product_id bigint, p_limit int, p_offset int)
returns table (batch_id bigint, product_id bigint, product_name text, brand text, supplier text, cost bigint, created_at timestamptz,
               added int, available bigint, frozen bigint, suspect bigint, sold bigint, voided bigint, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_admin_batches_v2_impl(p_product_id, p_limit, p_offset); $$;
create function public.store_admin_batch_codes_v2(p_batch_id bigint)
returns table (code_id bigint, masked_code text, serial text, status text, frozen boolean, suspect boolean,
               cost bigint, sold_at timestamptz, void_reason text, restored_at timestamptz)
language sql set search_path = '' as $$ select * from private.store_admin_batch_codes_v2_impl(p_batch_id); $$;

-- ---------------------------------------------------------------------
-- Grants (same rule as v1) for the new/replaced functions only; store_restore_codes is never granted
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_restore_codes',
                        'store_admin_codes_restore_impl', 'store_admin_codes_restore',
                        'store_admin_batch_restore_impl', 'store_admin_batch_restore',
                        'store_admin_codes_set_suspect_impl', 'store_admin_codes_set_suspect',
                        'store_admin_codes_freeze_impl',
                        'store_admin_use_suspect_impl', 'store_admin_use_suspect',
                        'store_admin_suspect_stock_impl', 'store_admin_suspect_stock',
                        'store_admin_batches_v2_impl', 'store_admin_batches_v2',
                        'store_admin_batch_codes_v2_impl', 'store_admin_batch_codes_v2')
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
