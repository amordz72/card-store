-- v1.45 (owner 2026-10-30, «نفذ المؤشرات»): each shop's spending, this period against the one before, so a shop
-- that spends less (gone to another app?) shows before it disappears. Like the other app's «مؤشرات المستخدمين»,
-- computed live (no nightly report to fall behind).
--   spending = purchases + flexy charged, less their refunds (store.wallet_entries);
--   groups: down / up (changed by at least change_pct %), new (nothing before), stopped (nothing now);
--   a shop under min_amount in both periods is left out. Both numbers set from the page (store.settings).
-- Read only, except the two settings.

alter table store.settings add column if not exists indicator_change_pct integer not null default 30
  check (indicator_change_pct between 1 and 100);
alter table store.settings add column if not exists indicator_min_amount bigint not null default 1000
  check (indicator_min_amount between 0 and 10000000);

create or replace function private.store_admin_indicators_impl(p_days integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 7), 1), 90);
  v_pct integer;
  v_min bigint;
begin
  perform private.store_require_admin();
  select s.indicator_change_pct, s.indicator_min_amount into v_pct, v_min from store.settings s where s.id = 1;
  return jsonb_build_object(
    'days', v_days, 'change_pct', v_pct, 'min_amount', v_min,
    'cur_from', now() - make_interval(days => v_days), 'prev_from', now() - make_interval(days => 2 * v_days),
    'shops', coalesce((select jsonb_agg(x order by abs(x.cur - x.prev) desc) from (
      select t.*, case
               when t.prev > 0 and t.cur = 0 then 'stopped'
               when t.prev = 0 and t.cur > 0 then 'new'
               when t.cur <= t.prev * (100 - v_pct) / 100.0 then 'down'
               when t.cur >= t.prev * (100 + v_pct) / 100.0 then 'up'
               else 'steady' end as grp,
             case when t.prev > 0 then round((t.cur - t.prev) * 100.0 / t.prev) end as change
        from (
          select c.id, c.name,
                 coalesce(sum(case when e.created_at >= now() - make_interval(days => v_days) then e.spent end), 0)::bigint cur,
                 coalesce(sum(case when e.created_at < now() - make_interval(days => v_days) then e.spent end), 0)::bigint prev,
                 (select max(s.last_used_at) from store.customer_sessions s where s.customer_id = c.id) last_at
            from store.customers c
            left join (select w.customer_id, w.created_at,
                              case when w.kind in ('purchase', 'flexy') then w.amount else -w.amount end spent
                         from store.wallet_entries w
                        where w.kind in ('purchase', 'flexy', 'purchase_refund', 'flexy_refund')
                          and w.created_at >= now() - make_interval(days => 2 * v_days)) e on e.customer_id = c.id
           where c.active
           group by c.id, c.name) t
       where greatest(t.cur, t.prev) >= v_min) x), '[]'::jsonb));
end;
$$;
create or replace function public.store_admin_indicators(p_days integer)
returns jsonb language sql as $$ select private.store_admin_indicators_impl(p_days) $$;

create or replace function private.store_admin_set_indicators_impl(p_change_pct integer, p_min_amount bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.settings set indicator_change_pct = coalesce(p_change_pct, indicator_change_pct),
         indicator_min_amount = coalesce(p_min_amount, indicator_min_amount), updated_at = now()
   where id = 1;
end;
$$;
create or replace function public.store_admin_set_indicators(p_change_pct integer, p_min_amount bigint)
returns void language sql as $$ select private.store_admin_set_indicators_impl(p_change_pct, p_min_amount) $$;

revoke all on function private.store_admin_indicators_impl(integer) from public, anon, authenticated;
revoke all on function public.store_admin_indicators(integer) from public, anon, authenticated;
grant execute on function private.store_admin_indicators_impl(integer) to authenticated;
grant execute on function public.store_admin_indicators(integer) to authenticated;
revoke all on function private.store_admin_set_indicators_impl(integer, bigint) from public, anon, authenticated;
revoke all on function public.store_admin_set_indicators(integer, bigint) from public, anon, authenticated;
grant execute on function private.store_admin_set_indicators_impl(integer, bigint) to authenticated;
grant execute on function public.store_admin_set_indicators(integer, bigint) to authenticated;
