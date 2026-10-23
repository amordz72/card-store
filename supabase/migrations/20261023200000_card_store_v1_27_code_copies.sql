-- v1.27 — تتبّع نسخ البطاقات على الخادم (PR #27؛ owner decision 2026-10-23 «نفذ»)
-- «تم نسخها» is a display hint only: the buyer copied the code from the app.
-- It is NOT proof the card was redeemed, and never changes store.codes.status, stock, sales or the ledger.
-- Copyable = the same cards a customer may report, without the report window:
-- sold, order done, not an IDOOM top-up card, not a game top-up card.
-- Additive only: new table, new functions; existing functions untouched.

create table store.code_copies (
  code_id bigint primary key references store.codes(id),
  customer_id bigint not null references store.customers(id),   -- the buyer (the shop account for the owner's own purchases)
  first_copied_at timestamptz not null default now(),
  last_copied_at timestamptz not null default now(),
  copy_count int not null default 1 check (copy_count > 0)
);
create index on store.code_copies (customer_id);

alter table store.code_copies enable row level security;
revoke all on store.code_copies from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Core: one row per card; repeat copies only bump last_copied_at / copy_count
-- ---------------------------------------------------------------------
create function private.store_copy_mark(p_customer bigint, p_code_id bigint) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  k record;
  v_first timestamptz;
begin
  select c.id, c.status, o.status as order_status, o.idoom_line, o.player_id into k
  from store.codes c join store.orders o on o.id = c.order_id
  where c.id = p_code_id and o.customer_id = p_customer;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if k.status <> 'sold' or k.order_status <> 'done' or k.idoom_line is not null or k.player_id is not null then
    raise exception 'NOT_COPYABLE';
  end if;
  insert into store.code_copies as x (code_id, customer_id) values (p_code_id, p_customer)
  on conflict (code_id) do update set last_copied_at = now(), copy_count = x.copy_count + 1
  returning x.first_copied_at into v_first;
  return v_first;
end;
$$;

create function private.store_mark_copied_impl(p_token text, p_code_id bigint) returns timestamptz
language plpgsql security definer set search_path = '' as $$
begin
  return private.store_copy_mark(private.store_session_customer(p_token), p_code_id);
end;
$$;

create function private.store_order_copies_impl(p_token text, p_order_id bigint)
returns table (code_id bigint, copied_at timestamptz, copy_count int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  if not exists (select 1 from store.orders o where o.id = p_order_id and o.customer_id = v) then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  return query select x.code_id, x.first_copied_at, x.copy_count
  from store.code_copies x join store.codes k on k.id = x.code_id
  where k.order_id = p_order_id order by x.code_id;
end;
$$;

-- The owner marks only the shop account's own cards; a customer's card is the customer's to mark.
create function private.store_admin_mark_copied_impl(p_code_id bigint) returns timestamptz
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return private.store_copy_mark(private.store_shop_id(), p_code_id);
end;
$$;

-- Read-only for any order: whether/when the buyer copied, never the code itself.
create function private.store_admin_order_copies_impl(p_order_id bigint)
returns table (code_id bigint, copied_at timestamptz, copy_count int)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query select x.code_id, x.first_copied_at, x.copy_count
  from store.code_copies x join store.codes k on k.id = x.code_id
  where k.order_id = p_order_id order by x.code_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------
create function public.store_mark_copied(p_token text, p_code_id bigint) returns timestamptz
language sql set search_path = '' as $$ select private.store_mark_copied_impl(p_token, p_code_id); $$;
create function public.store_order_copies(p_token text, p_order_id bigint)
returns table (code_id bigint, copied_at timestamptz, copy_count int)
language sql set search_path = '' as $$ select * from private.store_order_copies_impl(p_token, p_order_id); $$;
create function public.store_admin_mark_copied(p_code_id bigint) returns timestamptz
language sql set search_path = '' as $$ select private.store_admin_mark_copied_impl(p_code_id); $$;
create function public.store_admin_order_copies(p_order_id bigint)
returns table (code_id bigint, copied_at timestamptz, copy_count int)
language sql set search_path = '' as $$ select * from private.store_admin_order_copies_impl(p_order_id); $$;

-- ---------------------------------------------------------------------
-- Grants (same rule as v1) for the new functions only; store_copy_mark is never granted
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_copy_mark', 'store_mark_copied_impl', 'store_mark_copied',
                        'store_order_copies_impl', 'store_order_copies',
                        'store_admin_mark_copied_impl', 'store_admin_mark_copied',
                        'store_admin_order_copies_impl', 'store_admin_order_copies')
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
