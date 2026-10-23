-- v1.20 — بلاغات البطاقات + عدد الجرس (patterns 19 + 18, phase 1; owner decision 2026-10-23)
-- A customer reports a card he bought that did not work; the owner accepts or rejects it.
-- No automatic compensation, no effect on batch quality (pattern 17 is separate).
-- Additive only: new table, new functions; existing functions untouched.
-- Production: applied in parts (v1_20a table, v1_20b customer, v1_20c owner) with the same content.

alter table store.settings add column report_days int not null default 7 check (report_days between 1 and 90);

create table store.card_reports (
  id bigint generated always as identity primary key,
  code_id bigint not null unique references store.codes(id),   -- one report per card
  customer_id bigint not null references store.customers(id),
  reason text not null check (reason in ('used', 'not_found', 'rejected', 'other')),
  note text check (note is null or length(note) <= 500),
  status text not null default 'open' check (status in ('open', 'accepted', 'rejected')),
  admin_note text check (admin_note is null or length(admin_note) <= 500),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid
);
create index on store.card_reports (customer_id);
create index on store.card_reports (status);
-- Same rule as every store table: RLS on, no policies, no grants; access via functions only.
alter table store.card_reports enable row level security;
revoke all on store.card_reports from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Customer
-- ---------------------------------------------------------------------
-- Codes of one of my orders, with the report state of each card
create function private.store_order_codes_v2_impl(p_token text, p_order_id bigint)
returns table (code_id bigint, code text, serial text, status text, report_status text, report_reason text, can_report boolean)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
declare v_days int := (select s.report_days from store.settings s where s.id = 1);
begin
  if not exists (select 1 from store.orders o where o.id = p_order_id and o.customer_id = v) then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  return query
  select k.id, k.code, k.serial, k.status, r.status, r.reason,
         (r.id is null and k.status = 'sold' and o.status = 'done' and k.sold_at > now() - make_interval(days => v_days))
  from store.codes k join store.orders o on o.id = k.order_id
  left join store.card_reports r on r.code_id = k.id
  where k.order_id = p_order_id order by k.id;
end;
$$;

create function private.store_report_code_impl(p_token text, p_code_id bigint, p_reason text, p_note text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  v_days int := (select s.report_days from store.settings s where s.id = 1);
  k record;
  v_id bigint;
begin
  if p_reason is null or p_reason not in ('used', 'not_found', 'rejected', 'other') then raise exception 'INVALID_REASON'; end if;
  select c.id, c.status, c.sold_at, o.status as order_status into k
  from store.codes c join store.orders o on o.id = c.order_id
  where c.id = p_code_id and o.customer_id = v
  for update of c;
  if not found then raise exception 'CODE_NOT_FOUND'; end if;
  if k.status <> 'sold' or k.order_status <> 'done' then raise exception 'NOT_REPORTABLE'; end if;
  if k.sold_at <= now() - make_interval(days => v_days) then raise exception 'REPORT_WINDOW_CLOSED'; end if;
  if exists (select 1 from store.card_reports r where r.code_id = p_code_id) then raise exception 'ALREADY_REPORTED'; end if;
  insert into store.card_reports (code_id, customer_id, reason, note)
  values (p_code_id, v, p_reason, nullif(left(btrim(coalesce(p_note, '')), 500), '')) returning id into v_id;
  return v_id;
end;
$$;

create function private.store_my_reports_impl(p_token text)
returns table (report_id bigint, product_name text, code text, serial text, reason text, note text, status text,
               admin_note text, created_at timestamptz, resolved_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return query
  select r.id, p.name, k.code, k.serial, r.reason, r.note, r.status, r.admin_note, r.created_at, r.resolved_at
  from store.card_reports r join store.codes k on k.id = r.code_id join store.products p on p.id = k.product_id
  where r.customer_id = v order by r.id desc limit 100;
end;
$$;

-- ---------------------------------------------------------------------
-- Owner
-- ---------------------------------------------------------------------
-- p_status null = all; codes are masked like other admin views (full code via store_admin_reveal_code)
create function private.store_admin_reports_impl(p_status text)
returns table (report_id bigint, customer_id bigint, customer_name text, product_name text, code_id bigint, masked_code text,
               serial text, batch_id bigint, supplier text, sold_at timestamptz, order_id bigint, reason text, note text,
               status text, admin_note text, created_at timestamptz, resolved_at timestamptz,
               customer_reports bigint, customer_accepted bigint)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query
  select r.id, c.id, c.name, p.name, k.id, '****' || right(k.code, 4), k.serial, k.batch_id, s.name, k.sold_at, k.order_id,
         r.reason, r.note, r.status, r.admin_note, r.created_at, r.resolved_at,
         (select count(*) from store.card_reports x where x.customer_id = c.id),
         (select count(*) from store.card_reports x where x.customer_id = c.id and x.status = 'accepted')
  from store.card_reports r
  join store.customers c on c.id = r.customer_id
  join store.codes k on k.id = r.code_id
  join store.products p on p.id = k.product_id
  join store.suppliers s on s.id = k.supplier_id
  where p_status is null or r.status = p_status
  order by (r.status = 'open') desc, r.id desc limit 200;
end;
$$;

create function private.store_admin_resolve_report_impl(p_report_id bigint, p_status text, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare a uuid := private.store_require_admin();
declare v_status text;
begin
  if p_status is null or p_status not in ('accepted', 'rejected') then raise exception 'INVALID_REASON'; end if;
  select r.status into v_status from store.card_reports r where r.id = p_report_id for update;
  if not found then raise exception 'REPORT_NOT_FOUND'; end if;
  if v_status <> 'open' then raise exception 'ALREADY_RESOLVED'; end if;
  update store.card_reports r set status = p_status, admin_note = nullif(left(btrim(coalesce(p_note, '')), 500), ''),
    resolved_at = now(), resolved_by = a
  where r.id = p_report_id;
end;
$$;

-- For the header bell
create function private.store_admin_open_reports_count_impl() returns bigint
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return (select count(*) from store.card_reports r where r.status = 'open');
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------
create function public.store_order_codes_v2(p_token text, p_order_id bigint)
returns table (code_id bigint, code text, serial text, status text, report_status text, report_reason text, can_report boolean)
language sql set search_path = '' as $$ select * from private.store_order_codes_v2_impl(p_token, p_order_id); $$;
create function public.store_report_code(p_token text, p_code_id bigint, p_reason text, p_note text) returns bigint
language sql set search_path = '' as $$ select private.store_report_code_impl(p_token, p_code_id, p_reason, p_note); $$;
create function public.store_my_reports(p_token text)
returns table (report_id bigint, product_name text, code text, serial text, reason text, note text, status text,
               admin_note text, created_at timestamptz, resolved_at timestamptz)
language sql set search_path = '' as $$ select * from private.store_my_reports_impl(p_token); $$;
create function public.store_admin_reports(p_status text)
returns table (report_id bigint, customer_id bigint, customer_name text, product_name text, code_id bigint, masked_code text,
               serial text, batch_id bigint, supplier text, sold_at timestamptz, order_id bigint, reason text, note text,
               status text, admin_note text, created_at timestamptz, resolved_at timestamptz,
               customer_reports bigint, customer_accepted bigint)
language sql set search_path = '' as $$ select * from private.store_admin_reports_impl(p_status); $$;
create function public.store_admin_resolve_report(p_report_id bigint, p_status text, p_note text) returns void
language sql set search_path = '' as $$ select private.store_admin_resolve_report_impl(p_report_id, p_status, p_note); $$;
create function public.store_admin_open_reports_count() returns bigint
language sql set search_path = '' as $$ select private.store_admin_open_reports_count_impl(); $$;

-- ---------------------------------------------------------------------
-- Grants (same rule as v1) for the new functions only
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_order_codes_v2_impl', 'store_order_codes_v2', 'store_report_code_impl', 'store_report_code',
                        'store_my_reports_impl', 'store_my_reports', 'store_admin_reports_impl', 'store_admin_reports',
                        'store_admin_resolve_report_impl', 'store_admin_resolve_report',
                        'store_admin_open_reports_count_impl', 'store_admin_open_reports_count')
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
