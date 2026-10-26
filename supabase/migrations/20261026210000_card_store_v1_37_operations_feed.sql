-- card-store v1.37: «العمليات» is one list, like Hani Rohek (owner 2026-10-26).
-- Cards (store.orders) and the shops' Flexy (store.flexy_jobs: 630 and offers) together, newest
-- first, with one set of filters: scope (owner), customer (owner), type, dates and search.
-- type: null (all) | 'phone' | 'net' | 'game' (cards of that category) | 'flexy' (630) | 'offer'.
-- New functions beside the old ones: store_admin_orders and store_orders stay as they are.
-- The owner's own Flexy sends live in Flexy Core, not here; the page reads them from flexy-api.

create function private.store_admin_ops_impl(
  p_scope text, p_customer_id bigint, p_type text, p_from date, p_to date, p_query text, p_limit int, p_offset int)
returns table (source text, op_id bigint, customer_id bigint, customer_name text, is_shop boolean, brand text, category text,
               product_name text, qty int, phone text, offer_label text, base_amount bigint, charged_amount bigint,
               profit bigint, balance_after bigint, status text, network_reply text, created_at timestamptz, total_count bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare q text := nullif(btrim(p_query), '');
begin
  perform private.store_require_admin();
  return query
  with u as (
    select 'card'::text as src, o.id as oid, o.customer_id as cid, c.name as cname, c.is_shop as shop, b.name as bname,
           b.category as cat, p.name as pname, o.qty as n, null::text as ph, null::text as olabel, o.base_amount as base,
           o.charged_amount as charged, case when c.is_shop then o.base_amount - o.cost_amount else o.charged_amount - o.cost_amount end as gain,
           o.balance_after as bal, o.status as st, null::text as reply, o.created_at as at
    from store.orders o join store.customers c on c.id = o.customer_id
    join store.products p on p.id = o.product_id join store.brands b on b.id = p.brand_id
    where (p_type is null or p_type = b.category)
      and (q is null or p.name ilike '%' || q || '%' or c.name ilike '%' || q || '%' or o.id::text = q)
    union all
    select 'flexy', j.id, j.customer_id, c.name, c.is_shop, 'Mobilis',
           case when j.kind = 'offer' then 'offer' else 'flexy' end,
           case when j.kind = 'offer' then coalesce(j.offer_label, 'عرض') else 'فليكسي' end,
           1, j.phone, j.offer_label, j.amount::bigint, j.charged, null::bigint, e.balance_after, j.status, j.network_reply, j.created_at
    from store.flexy_jobs j join store.customers c on c.id = j.customer_id join store.wallet_entries e on e.id = j.entry_id
    where (p_type is null or p_type = case when j.kind = 'offer' then 'offer' else 'flexy' end)
      and (q is null or j.phone like '%' || q || '%' or j.offer_label ilike '%' || q || '%' or c.name ilike '%' || q || '%' or j.id::text = q)
  )
  select u.src, u.oid, u.cid, u.cname, u.shop, u.bname, u.cat, u.pname, u.n, u.ph, u.olabel, u.base, u.charged, u.gain,
         u.bal, u.st, u.reply, u.at, count(*) over ()
  from u
  where (p_customer_id is null or u.cid = p_customer_id)
    and (p_scope is null or p_scope = 'all' or (p_scope = 'shop') = u.shop)
    and (p_from is null or u.at >= p_from)
    and (p_to is null or u.at < p_to + 1)
  order by u.at desc, u.oid desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create function public.store_admin_ops(
  p_scope text, p_customer_id bigint, p_type text, p_from date, p_to date, p_query text, p_limit int, p_offset int)
returns table (source text, op_id bigint, customer_id bigint, customer_name text, is_shop boolean, brand text, category text,
               product_name text, qty int, phone text, offer_label text, base_amount bigint, charged_amount bigint,
               profit bigint, balance_after bigint, status text, network_reply text, created_at timestamptz, total_count bigint)
language sql set search_path = '' as $$
  select * from private.store_admin_ops_impl(p_scope, p_customer_id, p_type, p_from, p_to, p_query, p_limit, p_offset);
$$;

-- The customer's own list: the same rows, without other customers' names.
create function private.store_ops_impl(
  p_token text, p_type text, p_from date, p_to date, p_query text, p_limit int, p_offset int)
returns table (source text, op_id bigint, brand text, category text, product_name text, qty int, phone text, offer_label text,
               base_amount bigint, charged_amount bigint, profit bigint, balance_after bigint, status text, network_reply text,
               created_at timestamptz, total_count bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v bigint := private.store_session_customer(p_token);
  q text := nullif(btrim(p_query), '');
begin
  return query
  with u as (
    select 'card'::text as src, o.id as oid, b.name as bname, b.category as cat, p.name as pname, o.qty as n, null::text as ph,
           null::text as olabel, o.base_amount as base, o.charged_amount as charged, o.base_amount - o.charged_amount as gain,
           o.balance_after as bal, o.status as st, null::text as reply, o.created_at as at
    from store.orders o join store.products p on p.id = o.product_id join store.brands b on b.id = p.brand_id
    where o.customer_id = v
      and (p_type is null or p_type = b.category)
      and (q is null or p.name ilike '%' || q || '%' or o.id::text = q)
    union all
    select 'flexy', j.id, 'Mobilis', case when j.kind = 'offer' then 'offer' else 'flexy' end,
           case when j.kind = 'offer' then coalesce(j.offer_label, 'عرض') else 'فليكسي' end,
           1, j.phone, j.offer_label, j.amount::bigint, j.charged, null::bigint, e.balance_after, j.status, j.network_reply, j.created_at
    from store.flexy_jobs j join store.wallet_entries e on e.id = j.entry_id
    where j.customer_id = v
      and (p_type is null or p_type = case when j.kind = 'offer' then 'offer' else 'flexy' end)
      and (q is null or j.phone like '%' || q || '%' or j.offer_label ilike '%' || q || '%' or j.id::text = q)
  )
  select u.src, u.oid, u.bname, u.cat, u.pname, u.n, u.ph, u.olabel, u.base, u.charged, u.gain, u.bal, u.st, u.reply, u.at,
         count(*) over ()
  from u
  where (p_from is null or u.at >= p_from)
    and (p_to is null or u.at < p_to + 1)
  order by u.at desc, u.oid desc
  limit least(greatest(coalesce(p_limit, 10), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create function public.store_ops(
  p_token text, p_type text, p_from date, p_to date, p_query text, p_limit int, p_offset int)
returns table (source text, op_id bigint, brand text, category text, product_name text, qty int, phone text, offer_label text,
               base_amount bigint, charged_amount bigint, profit bigint, balance_after bigint, status text, network_reply text,
               created_at timestamptz, total_count bigint)
language sql set search_path = '' as $$
  select * from private.store_ops_impl(p_token, p_type, p_from, p_to, p_query, p_limit, p_offset);
$$;

revoke all on function private.store_admin_ops_impl(text, bigint, text, date, date, text, int, int) from public, anon, authenticated;
revoke all on function public.store_admin_ops(text, bigint, text, date, date, text, int, int) from public, anon, authenticated;
revoke all on function private.store_ops_impl(text, text, date, date, text, int, int) from public, anon, authenticated;
revoke all on function public.store_ops(text, text, date, date, text, int, int) from public, anon, authenticated;
grant execute on function private.store_admin_ops_impl(text, bigint, text, date, date, text, int, int) to authenticated;
grant execute on function public.store_admin_ops(text, bigint, text, date, date, text, int, int) to authenticated;
grant execute on function private.store_ops_impl(text, text, date, date, text, int, int) to anon, authenticated;
grant execute on function public.store_ops(text, text, date, date, text, int, int) to anon, authenticated;
