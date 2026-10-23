-- v1.22 — إعلانات بالصور في الرئيسية (pattern 20; owner decision 2026-10-23)
-- Each banner: an image, optional text, optional link (external https or a page inside the app),
-- active / frozen, order, optional start and end dates (empty = always). Shown to everyone.
-- The text announcement (store.settings.announcement) stays as it is.
-- Additive only: new table, new functions; existing functions untouched.
-- «حذف» hides a banner for good (removed_at) and keeps the row: no DELETE statement, because the
-- Supabase MCP tool stops for confirmation on DELETE/DROP in cloud sessions.
-- Production: applied in parts v1_22a (table + reads/save/freeze/move), v1_22b (wrappers),
-- v1_22c (removed_at column + create or replace of the same functions + remove). Same final state as this file.

create table store.banners (
  id bigint generated always as identity primary key,
  -- same rule as v1.19 images: a file in the public store-images bucket of this project
  image text not null
    check (image ~ '^https://wqyebqzbbpohbnznqdjj\.supabase\.co/storage/v1/object/public/store-images/[A-Za-z0-9/_.-]+$'),
  title text not null default '' check (length(title) <= 120),
  link_kind text not null default 'none' check (link_kind in ('none', 'url', 'page')),
  link text check (link is null or length(link) <= 500),
  active boolean not null default true,
  sort_order int not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  removed_at timestamptz,
  check (starts_at is null or ends_at is null or ends_at > starts_at),
  check ((link_kind = 'none') = (link is null)),
  check (link_kind <> 'url' or link ~ '^https://[^\s<>"]{4,}$'),
  -- pages inside the app only (no external path can hide here)
  check (link_kind <> 'page' or link ~ '^/(store(\?brand=[A-Za-z0-9%._~-]{1,120})?|operations|transfers|account|reports)$')
);
create index on store.banners (sort_order, id);
alter table store.banners enable row level security;
revoke all on store.banners from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Everyone: the banners showing right now (customer token, or the signed-in owner)
-- ---------------------------------------------------------------------
create function private.store_banners_impl(p_token text)
returns table (banner_id bigint, image text, title text, link_kind text, link text)
language plpgsql security definer set search_path = '' as $$
begin
  if p_token is null then perform private.store_require_admin();
  else perform private.store_session_customer(p_token);
  end if;
  return query
  select b.id, b.image, b.title, b.link_kind, b.link from store.banners b
  where b.active and b.removed_at is null and (b.starts_at is null or b.starts_at <= now()) and (b.ends_at is null or b.ends_at > now())
  order by b.sort_order, b.id;
end;
$$;

-- ---------------------------------------------------------------------
-- Owner
-- ---------------------------------------------------------------------
-- All banners with a state: live | frozen | scheduled (not started yet) | ended
create function private.store_admin_banners_impl()
returns table (banner_id bigint, image text, title text, link_kind text, link text, active boolean, sort_order int,
               starts_at timestamptz, ends_at timestamptz, state text, updated_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query
  select b.id, b.image, b.title, b.link_kind, b.link, b.active, b.sort_order, b.starts_at, b.ends_at,
         case when not b.active then 'frozen'
              when b.ends_at is not null and b.ends_at <= now() then 'ended'
              when b.starts_at is not null and b.starts_at > now() then 'scheduled'
              else 'live' end,
         b.updated_at
  from store.banners b where b.removed_at is null order by b.sort_order, b.id;
end;
$$;

-- p_id null = new banner (added last, active). Returns the banner id.
create function private.store_admin_save_banner_impl(
  p_id bigint, p_image text, p_title text, p_link_kind text, p_link text, p_starts_at timestamptz, p_ends_at timestamptz)
returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_kind text := coalesce(nullif(p_link_kind, ''), 'none');
  v_link text := nullif(btrim(coalesce(p_link, '')), '');
  v_id bigint;
begin
  perform private.store_require_admin();
  if p_image is null or p_image !~ '^https://wqyebqzbbpohbnznqdjj\.supabase\.co/storage/v1/object/public/store-images/[A-Za-z0-9/_.-]+$' then
    raise exception 'INVALID_IMAGE';
  end if;
  if v_kind not in ('none', 'url', 'page') then raise exception 'INVALID_LINK'; end if;
  if v_kind = 'none' then v_link := null;
  elsif v_link is null
     or (v_kind = 'url' and (length(v_link) > 500 or v_link !~ '^https://[^\s<>"]{4,}$'))
     or (v_kind = 'page' and v_link !~ '^/(store(\?brand=[A-Za-z0-9%._~-]{1,120})?|operations|transfers|account|reports)$') then
    raise exception 'INVALID_LINK';
  end if;
  if p_starts_at is not null and p_ends_at is not null and p_ends_at <= p_starts_at then raise exception 'INVALID_DATES'; end if;

  if p_id is null then
    if (select count(*) from store.banners b where b.removed_at is null) >= 20 then raise exception 'TOO_MANY_BANNERS'; end if;
    insert into store.banners (image, title, link_kind, link, starts_at, ends_at, sort_order)
    values (p_image, left(btrim(coalesce(p_title, '')), 120), v_kind, v_link, p_starts_at, p_ends_at,
            coalesce((select max(b.sort_order) from store.banners b), 0) + 1)
    returning id into v_id;
  else
    update store.banners b set image = p_image, title = left(btrim(coalesce(p_title, '')), 120), link_kind = v_kind, link = v_link,
           starts_at = p_starts_at, ends_at = p_ends_at, updated_at = now()
    where b.id = p_id and b.removed_at is null returning b.id into v_id;
    if v_id is null then raise exception 'BANNER_NOT_FOUND'; end if;
  end if;
  return v_id;
end;
$$;

-- Freeze (hide without deleting) or show again
create function private.store_admin_set_banner_active_impl(p_id bigint, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.banners b set active = coalesce(p_active, false), updated_at = now() where b.id = p_id and b.removed_at is null;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;
end;
$$;

-- p_dir: -1 = earlier, +1 = later (swap with the neighbour)
create function private.store_admin_move_banner_impl(p_id bigint, p_dir int) returns void
language plpgsql security definer set search_path = '' as $$
declare me record; other record;
begin
  perform private.store_require_admin();
  select b.id, b.sort_order into me from store.banners b where b.id = p_id and b.removed_at is null for update;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;
  if p_dir < 0 then
    select b.id, b.sort_order into other from store.banners b
    where b.removed_at is null and (b.sort_order, b.id) < (me.sort_order, me.id) order by b.sort_order desc, b.id desc limit 1 for update;
  else
    select b.id, b.sort_order into other from store.banners b
    where b.removed_at is null and (b.sort_order, b.id) > (me.sort_order, me.id) order by b.sort_order, b.id limit 1 for update;
  end if;
  if not found then return; end if;   -- already first / last
  if other.sort_order = me.sort_order then
    -- equal orders: spread them first so the swap means something
    update store.banners b set sort_order = s.n
    from (select x.id, row_number() over (order by x.sort_order, x.id)::int as n from store.banners x where x.removed_at is null) s
    where s.id = b.id;
    select b.sort_order into me.sort_order from store.banners b where b.id = me.id;
    select b.sort_order into other.sort_order from store.banners b where b.id = other.id;
  end if;
  update store.banners b set sort_order = other.sort_order, updated_at = now() where b.id = me.id;
  update store.banners b set sort_order = me.sort_order, updated_at = now() where b.id = other.id;
end;
$$;

-- «حذف»: gone from every list for good; the row stays as a record. The image file stays in storage.
create function private.store_admin_remove_banner_impl(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  update store.banners b set removed_at = now(), active = false, updated_at = now() where b.id = p_id and b.removed_at is null;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------
create function public.store_banners(p_token text)
returns table (banner_id bigint, image text, title text, link_kind text, link text)
language sql set search_path = '' as $$ select * from private.store_banners_impl(p_token); $$;
create function public.store_admin_banners()
returns table (banner_id bigint, image text, title text, link_kind text, link text, active boolean, sort_order int,
               starts_at timestamptz, ends_at timestamptz, state text, updated_at timestamptz)
language sql set search_path = '' as $$ select * from private.store_admin_banners_impl(); $$;
create function public.store_admin_save_banner(
  p_id bigint, p_image text, p_title text, p_link_kind text, p_link text, p_starts_at timestamptz, p_ends_at timestamptz)
returns bigint
language sql set search_path = '' as $$
  select private.store_admin_save_banner_impl(p_id, p_image, p_title, p_link_kind, p_link, p_starts_at, p_ends_at);
$$;
create function public.store_admin_set_banner_active(p_id bigint, p_active boolean) returns void
language sql set search_path = '' as $$ select private.store_admin_set_banner_active_impl(p_id, p_active); $$;
create function public.store_admin_move_banner(p_id bigint, p_dir int) returns void
language sql set search_path = '' as $$ select private.store_admin_move_banner_impl(p_id, p_dir); $$;
create function public.store_admin_remove_banner(p_id bigint) returns void
language sql set search_path = '' as $$ select private.store_admin_remove_banner_impl(p_id); $$;

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
      and p.proname in ('store_banners_impl', 'store_banners', 'store_admin_banners_impl', 'store_admin_banners',
                        'store_admin_save_banner_impl', 'store_admin_save_banner',
                        'store_admin_set_banner_active_impl', 'store_admin_set_banner_active',
                        'store_admin_move_banner_impl', 'store_admin_move_banner',
                        'store_admin_remove_banner_impl', 'store_admin_remove_banner')
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
end;
$$;
