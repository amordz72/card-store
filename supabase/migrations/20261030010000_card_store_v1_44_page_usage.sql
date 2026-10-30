-- v1.44 (owner 2026-10-30, «نفذ الاثنين»): which pages are used most, by the owner and by the shops, so the rare
-- ones move aside and a shop that stopped coming shows. Light: one row per page opened, never the same page by the
-- same person twice in 10 minutes; only the page's path (no ids, no numbers); rows older than 90 days removed.

create table if not exists store.page_views (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  customer_id bigint references store.customers(id) on delete cascade,
  page text not null check (length(page) between 1 and 60)
);
-- customer_id null = the owner
create index if not exists page_views_who on store.page_views (customer_id, page, at desc);
create index if not exists page_views_at on store.page_views (at);
alter table store.page_views enable row level security;

create or replace function private.store_page_note(p_customer bigint, p_page text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_page text := left(btrim(coalesce(p_page, '')), 60);
begin
  if v_page !~ '^/[a-z0-9/_:-]*$' then return; end if;
  if exists (select 1 from store.page_views v where v.customer_id is not distinct from p_customer
               and v.page = v_page and v.at > now() - interval '10 minutes') then return; end if;
  insert into store.page_views (customer_id, page) values (p_customer, v_page);
end;
$$;

-- A shop: by its session
create or replace function public.store_page_seen(p_token text, p_page text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_page_note(private.store_session_customer(p_token), p_page);
end;
$$;

-- The owner
create or replace function private.store_admin_page_seen_impl(p_page text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  perform private.store_page_note(null, p_page);
end;
$$;
create or replace function public.store_admin_page_seen(p_page text)
returns void language sql as $$ select private.store_admin_page_seen_impl(p_page) $$;

-- «الاستعمال»: per page (owner / shops, the last p_days), and per shop (last visit, its most opened page)
create or replace function private.store_admin_usage_impl(p_days integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_days integer := least(greatest(coalesce(p_days, 7), 1), 90);
begin
  perform private.store_require_admin();
  delete from store.page_views where at < now() - interval '90 days';
  return jsonb_build_object(
    'days', v_days,
    'pages', coalesce((select jsonb_agg(x order by x.owner + x.shops desc) from (
        select v.page, count(*) filter (where v.customer_id is null) owner,
               count(*) filter (where v.customer_id is not null) shops,
               count(distinct v.customer_id) shop_count
          from store.page_views v where v.at > now() - make_interval(days => v_days) group by v.page) x), '[]'::jsonb),
    'shops', coalesce((select jsonb_agg(y order by y.last_at desc nulls last) from (
        select c.id, c.name, max(v.at) last_at,
               count(v.id) filter (where v.at > now() - make_interval(days => v_days)) visits,
               (select v2.page from store.page_views v2 where v2.customer_id = c.id
                  and v2.at > now() - make_interval(days => v_days)
                 group by v2.page order by count(*) desc limit 1) top_page
          from store.customers c left join store.page_views v on v.customer_id = c.id
         where c.active group by c.id, c.name) y), '[]'::jsonb));
end;
$$;
create or replace function public.store_admin_usage(p_days integer)
returns jsonb language sql as $$ select private.store_admin_usage_impl(p_days) $$;

revoke all on table store.page_views from public, anon, authenticated;
revoke all on function private.store_page_note(bigint, text) from public, anon, authenticated;
revoke all on function public.store_page_seen(text, text) from public;
grant execute on function public.store_page_seen(text, text) to anon, authenticated;
revoke all on function private.store_admin_page_seen_impl(text) from public, anon, authenticated;
revoke all on function public.store_admin_page_seen(text) from public, anon, authenticated;
grant execute on function private.store_admin_page_seen_impl(text) to authenticated;
grant execute on function public.store_admin_page_seen(text) to authenticated;
revoke all on function private.store_admin_usage_impl(integer) from public, anon, authenticated;
revoke all on function public.store_admin_usage(integer) from public, anon, authenticated;
grant execute on function private.store_admin_usage_impl(integer) to authenticated;
grant execute on function public.store_admin_usage(integer) to authenticated;
