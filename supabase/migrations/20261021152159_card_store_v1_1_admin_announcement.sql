-- Card Store v1.1 — admin can read the current announcement (additive, read-only)

create function private.store_admin_get_announcement_impl() returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return (select s.announcement from store.settings s where s.id = 1);
end;
$$;

create function public.store_admin_get_announcement() returns text
language sql set search_path = '' as $$ select private.store_admin_get_announcement_impl(); $$;

revoke all on function private.store_admin_get_announcement_impl() from public, anon, authenticated;
revoke all on function public.store_admin_get_announcement() from public, anon, authenticated;
grant execute on function private.store_admin_get_announcement_impl() to authenticated;
grant execute on function public.store_admin_get_announcement() to authenticated;
