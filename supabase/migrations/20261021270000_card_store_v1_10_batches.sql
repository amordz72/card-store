-- v1.10 — batches: freeze / void / set cost / export (recovered 2026-10-23).
-- Applied to production 2026-10-21 as `card_store_v1_10_batches` but the file was missing from the repo;
-- the SQL below is copied verbatim from supabase_migrations.schema_migrations.

alter table store.codes add column frozen boolean not null default false;
alter table store.codes add column void_reason text;
alter table store.codes add column voided_at timestamptz;

create or replace function private.store_buy_core(p_customer bigint, p_product_id bigint, p_qty int, p_request_id uuid)
returns table (order_id bigint, product_name text, qty int, codes jsonb)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  o store.orders;
  p record;
  c store.customers;
  v_mode text;
  v_value numeric;
  v_charged bigint := 0;
  v_ids bigint[];
  v_cost bigint;
  k record;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into o from store.orders where request_id = p_request_id;
  if found then
    if o.customer_id <> p_customer then raise exception 'REQUEST_ID_CONFLICT'; end if;
  else
    if p_qty is null or p_qty < 1 or p_qty > 20 then raise exception 'INVALID_QTY'; end if;
    select pr.id, pr.base_price, pr.name into p
    from store.products pr join store.brands b on b.id = pr.brand_id
    where pr.id = p_product_id and pr.active and b.active;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

    select * into c from store.customers where id = p_customer for update;

    select array_agg(id order by id) into v_ids from (
      select k2.id from store.codes k2
      where k2.product_id = p.id and k2.status = 'available' and not k2.frozen
      order by k2.id limit p_qty
      for update skip locked) s;
    if coalesce(array_length(v_ids, 1), 0) < p_qty then raise exception 'OUT_OF_STOCK'; end if;

    select case when bool_and(k3.cost is not null) then sum(k3.cost) end into v_cost
    from store.codes k3 where k3.id = any (v_ids);

    if c.is_shop then
      if v_cost is null then raise exception 'COST_MISSING'; end if;
      v_charged := v_cost;
      v_mode := 'cost';
    else
      select pr2.mode, pr2.value into v_mode, v_value from private.store_price_rule(p_customer, p.id) pr2;
      for k in select k4.cost from store.codes k4 where k4.id = any (v_ids) order by k4.id loop
        v_charged := v_charged + private.store_unit_charge(v_mode, v_value, k.cost, p.base_price);
      end loop;
    end if;
    if v_charged <= 0 then raise exception 'INVALID_PRICE_RULE'; end if;
    if c.balance < v_charged then raise exception 'INSUFFICIENT_BALANCE'; end if;

    insert into store.orders (customer_id, product_id, qty, base_amount, pct, charged_amount, cost_amount, balance_after,
                              request_id, price_mode, price_value)
    values (p_customer, p.id, p_qty, p.base_price * p_qty, 0, v_charged, v_cost, c.balance - v_charged,
            p_request_id, v_mode, v_value)
    returning * into o;
    update store.codes set status = 'sold', order_id = o.id, sold_at = now() where id = any (v_ids);
    perform private.store_post_entry(p_customer, 'purchase', v_charged, null, o.id, null, null, null);
  end if;

  return query
  select o.id, pr.name, o.qty,
         coalesce((select jsonb_agg(jsonb_build_object('code', k5.code, 'serial', k5.serial) order by k5.id)
                   from store.codes k5 where k5.order_id = o.id), '[]'::jsonb)
  from store.products pr where pr.id = o.product_id;
end;
$$;

create or replace function private.store_catalog_core()
returns table (product_id bigint, brand text, category text, name text, base_price bigint, available boolean, brand_sort int, sort int)
language sql stable security definer set search_path = '' as $$
  select p.id, b.name, b.category, p.name, p.base_price,
         exists (select 1 from store.codes k where k.product_id = p.id and k.status = 'available' and not k.frozen),
         b.sort, p.sort
  from store.products p join store.brands b on b.id = p.brand_id
  where p.active and b.active
  order by b.category, b.sort, p.sort, p.base_price;
$$;

create or replace function private.store_current_cost(p_product bigint) returns bigint
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from store.codes k where k.product_id = p_product and k.status = 'available' and not k.frozen)
      then (select k.cost from store.codes k where k.product_id = p_product and k.status = 'available' and not k.frozen order by k.id limit 1)
    else coalesce(
      (select p.default_cost from store.products p where p.id = p_product),
      (select k.cost from store.codes k where k.product_id = p_product and k.cost is not null order by k.id desc limit 1))
  end;
$$;

create or replace function private.store_cost_source(p_product bigint) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from store.codes k where k.product_id = p_product and k.status = 'available' and not k.frozen) then 'stock'
    when (select p.default_cost from store.products p where p.id = p_product) is not null then 'usual'
    when exists (select 1 from store.codes k where k.product_id = p_product and k.cost is not null) then 'last'
  end;
$$;

create or replace function private.store_admin_stock_impl()
returns table (product_id bigint, brand_id bigint, brand text, category text, name text, base_price bigint, active boolean,
               brand_active boolean, available bigint, sold bigint, voided bigint, sort int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select p.id, b.id, b.name, b.category, p.name, p.base_price, p.active, b.active,
         count(k.id) filter (where k.status = 'available' and not k.frozen),
         count(k.id) filter (where k.status = 'sold'),
         count(k.id) filter (where k.status = 'void'), p.sort
  from store.products p join store.brands b on b.id = p.brand_id
  left join store.codes k on k.product_id = p.id
  group by p.id, b.id
  order by b.category, b.sort, p.sort, p.base_price;
end;
$$;

create function private.store_admin_batches_impl(p_product_id bigint, p_limit int, p_offset int)
returns table (batch_id bigint, product_id bigint, product_name text, brand text, supplier text, cost bigint, created_at timestamptz,
               added int, available bigint, frozen bigint, sold bigint, voided bigint, total_count bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select bt.id, p.id, p.name, b.name, s.name, bt.cost, bt.created_at, bt.added,
         count(k.id) filter (where k.status = 'available' and not k.frozen),
         count(k.id) filter (where k.status = 'available' and k.frozen),
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

create function private.store_admin_batch_codes_impl(p_batch_id bigint)
returns table (code_id bigint, masked_code text, serial text, status text, frozen boolean, cost bigint, sold_at timestamptz, void_reason text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select k.id, '****' || right(k.code, 4), k.serial, k.status, k.frozen, k.cost, k.sold_at, k.void_reason
  from store.codes k where k.batch_id = p_batch_id order by k.id;
end;
$$;

create function private.store_admin_codes_freeze_impl(p_code_ids bigint[], p_frozen boolean) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.store_require_admin();
  update store.codes set frozen = coalesce(p_frozen, true)
  where id = any (p_code_ids) and status = 'available' and frozen <> coalesce(p_frozen, true);
  get diagnostics n = row_count;
  return n;
end;
$$;

create function private.store_admin_codes_void_impl(p_code_ids bigint[], p_reason text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.store_require_admin();
  if nullif(btrim(p_reason), '') is null then raise exception 'REASON_REQUIRED'; end if;
  update store.codes set status = 'void', frozen = false, void_reason = btrim(p_reason), voided_at = now()
  where id = any (p_code_ids) and status = 'available';
  get diagnostics n = row_count;
  return n;
end;
$$;

create function private.store_admin_codes_set_cost_impl(p_code_ids bigint[], p_cost bigint) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.store_require_admin();
  if p_cost is null or p_cost <= 0 then raise exception 'INVALID_COST'; end if;
  update store.codes set cost = p_cost where id = any (p_code_ids) and status = 'available';
  get diagnostics n = row_count;
  return n;
end;
$$;

create function private.store_admin_batch_export_impl(p_batch_id bigint)
returns table (code text, serial text, status text, frozen boolean, cost bigint, void_reason text)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare a uuid := private.store_require_admin();
begin
  insert into store.code_reveals (code_id, admin_id) select k.id, a from store.codes k where k.batch_id = p_batch_id;
  return query
  select k.code, k.serial, k.status, k.frozen, k.cost, k.void_reason
  from store.codes k where k.batch_id = p_batch_id order by k.id;
end;
$$;

create function public.store_admin_batches(p_product_id bigint, p_limit int, p_offset int)
returns table (batch_id bigint, product_id bigint, product_name text, brand text, supplier text, cost bigint, created_at timestamptz,
               added int, available bigint, frozen bigint, sold bigint, voided bigint, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_admin_batches_impl(p_product_id, p_limit, p_offset); $$;
create function public.store_admin_batch_codes(p_batch_id bigint)
returns table (code_id bigint, masked_code text, serial text, status text, frozen boolean, cost bigint, sold_at timestamptz, void_reason text)
language sql set search_path = '' as $$ select * from private.store_admin_batch_codes_impl(p_batch_id); $$;
create function public.store_admin_codes_freeze(p_code_ids bigint[], p_frozen boolean) returns int
language sql set search_path = '' as $$ select private.store_admin_codes_freeze_impl(p_code_ids, p_frozen); $$;
create function public.store_admin_codes_void(p_code_ids bigint[], p_reason text) returns int
language sql set search_path = '' as $$ select private.store_admin_codes_void_impl(p_code_ids, p_reason); $$;
create function public.store_admin_codes_set_cost(p_code_ids bigint[], p_cost bigint) returns int
language sql set search_path = '' as $$ select private.store_admin_codes_set_cost_impl(p_code_ids, p_cost); $$;
create function public.store_admin_batch_export(p_batch_id bigint)
returns table (code text, serial text, status text, frozen boolean, cost bigint, void_reason text)
language sql set search_path = '' as $$ select * from private.store_admin_batch_export_impl(p_batch_id); $$;

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname in ('private', 'public') and p.proname like 'store\_%')
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
