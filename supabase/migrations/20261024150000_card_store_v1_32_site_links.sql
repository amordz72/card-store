-- v1.32 — site links as owner settings instead of constants in the code (owner rule 2026-10-24:
-- «anything that can be a setting becomes one»; developer/guidelines/reusable-patterns.md, pattern 20).
--  * official_site_url: the link shared to other phones (site, Rech-Doom app). Null = the built-in
--    https://amordz72.github.io/card-store/ in the page.
--  * extra_origins: up to 3 more sites (e.g. a Cloudflare copy) whose pages may call the Edge Function
--    store-flexy. https://amordz72.github.io and http://localhost:9000 stay built into the function, so a
--    wrong setting can never lock out the official site. Remove a site here BEFORE deleting it: a deleted
--    name may be taken by someone else.
-- Both are public (they are site addresses), so the reader is open to anon: the Edge Function reads the list
-- on the browser's preflight, which carries no session.
-- Additive only: new columns, new functions.

alter table store.settings add column official_site_url text
  check (official_site_url is null or (official_site_url ~ '^https://[^\s]+/$' and length(official_site_url) <= 300));
alter table store.settings add column extra_origins text[] not null default '{}'
  check (cardinality(extra_origins) <= 3);

-- Exact origins only: https, a host name, an optional port; no path, no wildcard.
create function private.store_origin_ok(p text) returns boolean
language sql immutable set search_path = '' as $$
  select p ~ '^https://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:[0-9]{1,5})?$' and length(p) <= 200;
$$;

create function private.store_site_links_impl() returns table (official_url text, extra_origins text[])
language sql stable security definer set search_path = '' as $$
  select s.official_site_url, s.extra_origins from store.settings s where s.id = 1;
$$;

-- Accepts https://host/… and keeps the site root with a trailing slash; empty = back to the built-in link.
create function private.store_admin_set_official_url_impl(p_url text) returns void
language plpgsql security definer set search_path = '' as $$
declare v text := nullif(btrim(coalesce(p_url, '')), '');
begin
  perform private.store_require_admin();
  if v is not null then
    if right(v, 1) <> '/' then v := v || '/'; end if;
    if v !~ '^https://[^\s]+/$' or length(v) > 300 then raise exception 'INVALID_LINK'; end if;
  end if;
  update store.settings set official_site_url = v, updated_at = now() where id = 1;
end;
$$;

-- Replaces the whole list. Each entry is lower-cased and loses a trailing slash; duplicates are dropped.
create function private.store_admin_set_extra_origins_impl(p_origins text[]) returns void
language plpgsql security definer set search_path = '' as $$
declare v text[];
begin
  perform private.store_require_admin();
  select coalesce(array_agg(distinct o order by o), '{}') into v
  from (select rtrim(lower(btrim(x)), '/') as o from unnest(coalesce(p_origins, '{}')) x) t
  where o <> '';
  if exists (select 1 from unnest(v) o where not private.store_origin_ok(o)) then raise exception 'INVALID_ORIGIN'; end if;
  if cardinality(v) > 3 then raise exception 'TOO_MANY_ORIGINS'; end if;
  update store.settings set extra_origins = v, updated_at = now() where id = 1;
end;
$$;

create function public.store_site_links() returns table (official_url text, extra_origins text[])
language sql set search_path = '' as $$ select * from private.store_site_links_impl(); $$;
create function public.store_admin_set_official_url(p_url text) returns void
language sql set search_path = '' as $$ select private.store_admin_set_official_url_impl(p_url); $$;
create function public.store_admin_set_extra_origins(p_origins text[]) returns void
language sql set search_path = '' as $$ select private.store_admin_set_extra_origins_impl(p_origins); $$;

-- Grants: store_admin_* to authenticated; the reader to anon and authenticated; the helper to nobody.
revoke all on function private.store_origin_ok(text) from public, anon, authenticated;
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, n.nspname as sch, p.proname as name
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('private', 'public')
      and p.proname in ('store_site_links_impl', 'store_site_links',
                        'store_admin_set_official_url_impl', 'store_admin_set_official_url',
                        'store_admin_set_extra_origins_impl', 'store_admin_set_extra_origins')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.name like 'store\_admin\_%' then
      execute format('grant execute on function %s to authenticated', f.sig);
    else
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end;
$$;
