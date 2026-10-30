-- v1.46 (owner 2026-10-30): «غربي دخل، لكن إلى أين؟» — each shop's visits page by page, and what it shows interest in
-- without buying: the brand it opened, the card whose buy sheet it opened, what it searched («/store/brand:PUBG»,
-- «/store/buy:…», «/store/search:…»). Same light rule as v1.44: once per page per shop every 10 minutes, 90 days.

create or replace function private.store_page_note(p_customer bigint, p_page text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_page text := left(btrim(coalesce(p_page, '')), 60);
begin
  -- a path, now with a brand, a card or a search after it (no line breaks, no control characters)
  if v_page !~ '^/[^[:cntrl:]]*$' then return; end if;
  if exists (select 1 from store.page_views v where v.customer_id is not distinct from p_customer
               and v.page = v_page and v.at > now() - interval '10 minutes') then return; end if;
  insert into store.page_views (customer_id, page) values (p_customer, v_page);
end;
$$;

-- One shop: every page and interest in the last p_days, most visited first
create or replace function private.store_admin_usage_shop_impl(p_customer bigint, p_days integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return coalesce((select jsonb_agg(x order by x.visits desc, x.last_at desc) from (
    select v.page, count(*) visits, max(v.at) last_at from store.page_views v
     where v.customer_id = p_customer and v.at > now() - make_interval(days => least(greatest(coalesce(p_days, 7), 1), 90))
     group by v.page) x), '[]'::jsonb);
end;
$$;
create or replace function public.store_admin_usage_shop(p_customer bigint, p_days integer)
returns jsonb language sql as $$ select private.store_admin_usage_shop_impl(p_customer, p_days) $$;

revoke all on function private.store_admin_usage_shop_impl(bigint, integer) from public, anon, authenticated;
revoke all on function public.store_admin_usage_shop(bigint, integer) from public, anon, authenticated;
grant execute on function private.store_admin_usage_shop_impl(bigint, integer) to authenticated;
grant execute on function public.store_admin_usage_shop(bigint, integer) to authenticated;
