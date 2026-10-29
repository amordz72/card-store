-- card-store v1.40: «أعطِ لمن بلا نسبة» for every service (owner 2026-10-29, after v1.39).
-- The owner preferred one button per service over «حفظ الافتراضية»: the rate is kept as the default
-- (for shops enabled later) AND given to every enabled shop that has none for that service.
-- v1.39's fill function knew Djezzy and Ooredoo only; this _v2 knows the four: mobilis (ordinary
-- 630), offer (Mobilis offers), ooredoo, djezzy. A shop that has its own rate keeps it. Nothing dropped.

create or replace function private.store_admin_flexy_fill_rate_v2_impl(p_service text, p_rate numeric)
returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.store_require_admin();
  if p_rate is null or p_rate < 0 or p_rate >= 100 then raise exception 'FLEXY_BAD_REQUEST'; end if;
  if p_service = 'mobilis' then
    update store.settings s set flexy_default_rate_630 = p_rate, updated_at = now() where s.id = 1;
    update store.customers c set flexy_rate_630 = p_rate where c.flexy_enabled and not c.is_shop and c.flexy_rate_630 is null;
  elsif p_service = 'offer' then
    update store.settings s set flexy_default_rate_offer = p_rate, updated_at = now() where s.id = 1;
    update store.customers c set flexy_rate_offer = p_rate where c.flexy_enabled and not c.is_shop and c.flexy_rate_offer is null;
  elsif p_service = 'ooredoo' then
    update store.settings s set flexy_default_rate_630_ooredoo = p_rate, updated_at = now() where s.id = 1;
    update store.customers c set flexy_rate_630_ooredoo = p_rate where c.flexy_enabled and not c.is_shop and c.flexy_rate_630_ooredoo is null;
  elsif p_service = 'djezzy' then
    update store.settings s set flexy_default_rate_630_djezzy = p_rate, updated_at = now() where s.id = 1;
    update store.customers c set flexy_rate_630_djezzy = p_rate where c.flexy_enabled and not c.is_shop and c.flexy_rate_630_djezzy is null;
  else
    raise exception 'FLEXY_BAD_REQUEST';
  end if;
  get diagnostics n = row_count;
  return n;
end;
$$;
create or replace function public.store_admin_flexy_fill_rate_v2(p_service text, p_rate numeric)
returns int language sql as $$ select private.store_admin_flexy_fill_rate_v2_impl(p_service, p_rate) $$;

revoke all on function private.store_admin_flexy_fill_rate_v2_impl(text, numeric) from public, anon, authenticated;
revoke all on function public.store_admin_flexy_fill_rate_v2(text, numeric) from public, anon, authenticated;
grant execute on function private.store_admin_flexy_fill_rate_v2_impl(text, numeric) to authenticated;
grant execute on function public.store_admin_flexy_fill_rate_v2(text, numeric) to authenticated;
