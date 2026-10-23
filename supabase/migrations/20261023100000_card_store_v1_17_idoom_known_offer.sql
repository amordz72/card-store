-- v1.17: the last known offer of an IDOOM line, so the page shows the cards at once instead of
-- asking for a check every time (owner 2026-10-23). The phone still checks the line itself in
-- every top-up before it takes a card, so this is display only. Learnt from every job where the
-- phone read the line's page: checks and top-ups alike (offer is kept on both).

create or replace function private.store_admin_idoom_line_info_impl(p_line text)
returns table (offer text, checked_at timestamptz, source text)
language plpgsql stable security definer set search_path = '' as $$
declare v_line text;
begin
  perform private.store_require_admin();
  v_line := private.store_idoom_line(p_line);
  return query
  select j.offer, coalesce(j.finished_at, j.claimed_at), j.kind
  from store.idoom_jobs j
  where j.line = v_line and j.offer is not null and j.status <> 'cancelled'
  order by coalesce(j.finished_at, j.claimed_at) desc nulls last, j.id desc
  limit 1;
end;
$$;

create or replace function public.store_admin_idoom_line_info(p_line text)
returns table (offer text, checked_at timestamptz, source text)
language sql set search_path = '' as $$ select * from private.store_admin_idoom_line_info_impl(p_line); $$;

revoke all on function private.store_admin_idoom_line_info_impl(text) from public, anon, authenticated;
grant execute on function private.store_admin_idoom_line_info_impl(text) to authenticated;
revoke all on function public.store_admin_idoom_line_info(text) from public, anon, authenticated;
grant execute on function public.store_admin_idoom_line_info(text) to authenticated;
