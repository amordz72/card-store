-- =====================================================================
-- Card Store v1.5 — «التحويلات» separate from «العمليات» (unified interface, item 0)
--  * Customer: store_transfers() = wallet movements that are not purchases
--    (debt / cash / pay / self and their refunds), with optional kind and date filters.
--  * Admin: store_admin_entries(p_kind => 'transfers') = the same split for any account.
-- Additive only.
-- =====================================================================

create or replace function private.store_admin_entries_impl(
  p_customer_id bigint, p_kind text, p_from date, p_to date, p_limit int, p_offset int, p_scope text default null)
returns table (entry_id bigint, customer_id bigint, customer_name text, kind text, amount bigint, d_balance bigint, d_debt bigint,
               balance_after bigint, debt_after bigint, note text, order_id bigint, reversed boolean, reverses_id bigint,
               created_at timestamptz, total_count bigint, total_amount numeric, is_shop boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.store_require_admin();
  return query
  select e.id, e.customer_id, c.name, e.kind, e.amount, e.d_balance, e.d_debt, e.balance_after, e.debt_after, e.note,
         e.order_id, exists (select 1 from store.wallet_entries x where x.reverses_id = e.id), e.reverses_id, e.created_at,
         count(*) over (), sum(e.amount) over (), c.is_shop
  from store.wallet_entries e join store.customers c on c.id = e.customer_id
  where (p_customer_id is null or e.customer_id = p_customer_id)
    and (p_scope is null or p_scope = 'all' or (p_scope = 'shop') = c.is_shop)
    and (p_kind is null
         or (p_kind = 'refund' and e.kind like '%\_refund')
         or (p_kind = 'transfers' and e.kind not in ('purchase', 'purchase_refund'))
         or e.kind = p_kind)
    and (p_from is null or e.created_at >= p_from)
    and (p_to is null or e.created_at < p_to + 1)
  order by e.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- p_kind: null = all transfers; 'debt' | 'cash' | 'pay' | 'self' = that kind and its refunds
create function private.store_transfers_impl(p_token text, p_kind text, p_from date, p_to date, p_limit int, p_offset int)
returns table (entry_id bigint, kind text, amount bigint, d_balance bigint, d_debt bigint, note text,
               reversed boolean, reverses_id bigint, created_at timestamptz, total_count bigint, total_amount numeric)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select e.id, e.kind, e.amount, e.d_balance, e.d_debt, e.note,
         exists (select 1 from store.wallet_entries x where x.reverses_id = e.id), e.reverses_id, e.created_at,
         count(*) over (), sum(e.amount) over ()
  from store.wallet_entries e
  where e.customer_id = v
    and e.kind not in ('purchase', 'purchase_refund')
    and (p_kind is null or e.kind = p_kind or e.kind = p_kind || '_refund')
    and (p_from is null or e.created_at >= p_from)
    and (p_to is null or e.created_at < p_to + 1)
  order by e.id desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create function public.store_transfers(p_token text, p_kind text, p_from date, p_to date, p_limit int, p_offset int)
returns table (entry_id bigint, kind text, amount bigint, d_balance bigint, d_debt bigint, note text,
               reversed boolean, reverses_id bigint, created_at timestamptz, total_count bigint, total_amount numeric)
language sql set search_path = '' as $$ select * from private.store_transfers_impl(p_token, p_kind, p_from, p_to, p_limit, p_offset); $$;

-- Grants (same rule as before)
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
