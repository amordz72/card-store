-- Behavioural tests for v1.22 (image banners). Run after all migrations and the other tests.
\set ON_ERROR_STOP on
\set QUIET on
create temp table r_results (name text, ok boolean, detail text);
grant all on r_results to anon, authenticated;
create or replace function pg_temp.check(n text, cond boolean, d text default '') returns void language sql as $$
  insert into r_results values (n, coalesce(cond, false), d);
$$;
create or replace function pg_temp.err(sqltext text) returns text language plpgsql as $$
begin
  execute sqltext;
  return 'NO_ERROR';
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
\set img 'https://wqyebqzbbpohbnznqdjj.supabase.co/storage/v1/object/public/store-images/banner/0-1.webp'

-- ===== owner =====
set role authenticated;
select set_config('request.jwt.claim.sub', '60e166af-1366-47cc-81f9-791a4585c66e', false);
select public.store_admin_save_banner(null, :'img', 'عرض الأسبوع', 'none', null, null, null) as b1 \gset
select public.store_admin_save_banner(null, :'img', '', 'url', 'https://facebook.com/page', null, null) as b2 \gset
select public.store_admin_save_banner(null, :'img', 'ببجي', 'page', '/store?brand=PUBG', null, null) as b3 \gset
select public.store_admin_save_banner(null, :'img', 'لاحقًا', 'none', null, now() + interval '1 day', null) as b4 \gset
select public.store_admin_save_banner(null, :'img', 'انتهى', 'none', null, now() - interval '2 day', now() - interval '1 day') as b5 \gset
select pg_temp.check('5 saved, in order', (select array_agg(banner_id order by sort_order) from public.store_admin_banners()) = array[:b1, :b2, :b3, :b4, :b5]::bigint[]);
select pg_temp.check('states', (select string_agg(state, ',' order by sort_order) from public.store_admin_banners()) = 'live,live,live,scheduled,ended');
select pg_temp.check('owner sees live only on home', (select array_agg(banner_id order by banner_id) from public.store_banners(null)) = array[:b1, :b2, :b3]::bigint[]);

select pg_temp.check('bad image', pg_temp.err($$select public.store_admin_save_banner(null, 'https://evil.example/x.png', '', 'none', null, null, null)$$) like '%INVALID_IMAGE%');
select pg_temp.check('http link refused', pg_temp.err(format($$select public.store_admin_save_banner(null, %L, '', 'url', 'http://x.com', null, null)$$, :'img')) like '%INVALID_LINK%');
select pg_temp.check('javascript link refused', pg_temp.err(format($$select public.store_admin_save_banner(null, %L, '', 'url', 'javascript:alert(1)', null, null)$$, :'img')) like '%INVALID_LINK%');
select pg_temp.check('unknown page refused', pg_temp.err(format($$select public.store_admin_save_banner(null, %L, '', 'page', '/idoom', null, null)$$, :'img')) like '%INVALID_LINK%');
select pg_temp.check('url kind needs a link', pg_temp.err(format($$select public.store_admin_save_banner(null, %L, '', 'url', '', null, null)$$, :'img')) like '%INVALID_LINK%');
select pg_temp.check('end before start refused', pg_temp.err(format($$select public.store_admin_save_banner(null, %L, '', 'none', null, now(), now() - interval '1 hour')$$, :'img')) like '%INVALID_DATES%');
select pg_temp.check('none kind drops link', (select link is null from public.store_admin_banners() where banner_id = (
  select public.store_admin_save_banner(:b1, :'img', 'عرض الأسبوع', 'none', 'https://ignored.com', null, null))));

-- freeze / edit / move / delete
select public.store_admin_set_banner_active(:b2, false);
select pg_temp.check('frozen hidden', not exists (select 1 from public.store_banners(null) where banner_id = :b2));
select pg_temp.check('frozen state', (select state from public.store_admin_banners() where banner_id = :b2) = 'frozen');
select public.store_admin_set_banner_active(:b2, true);
select public.store_admin_save_banner(:b3, :'img', 'ببجي جديد', 'page', '/store', null, null);
select pg_temp.check('edited', (select title = 'ببجي جديد' and link = '/store' from public.store_admin_banners() where banner_id = :b3));
select public.store_admin_move_banner(:b3, -1);
select pg_temp.check('moved up', (select array_agg(banner_id order by sort_order, banner_id) from public.store_admin_banners()) = array[:b1, :b3, :b2, :b4, :b5]::bigint[]);
select public.store_admin_move_banner(:b1, -1);
select pg_temp.check('first stays first', (select banner_id from public.store_admin_banners() order by sort_order, banner_id limit 1) = :b1);
select public.store_admin_move_banner(:b5, 1);
select public.store_admin_remove_banner(:b5);
select pg_temp.check('deleted', not exists (select 1 from public.store_admin_banners() where banner_id = :b5));
select pg_temp.check('delete missing', pg_temp.err(format('select public.store_admin_remove_banner(%s)', :b5)) like '%BANNER_NOT_FOUND%');
select public.store_admin_create_customer('مشاهد', '0770999111', 'secret123') as rc \gset
reset role;
select pg_temp.check('removed row kept as record', (select count(*) from store.banners where id = :b5 and removed_at is not null and not active) = 1);

-- ===== customer =====
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select session_token as tok from public.store_login('0770999111', 'secret123') \gset
select pg_temp.check('customer sees live banners', (select array_agg(banner_id order by banner_id) from public.store_banners(:'tok')) = array[:b1, :b2, :b3]::bigint[]);
select pg_temp.check('bad token', pg_temp.err($$select * from public.store_banners('nope')$$) like '%INVALID_SESSION%');
select pg_temp.check('anon without token', pg_temp.err($$select * from public.store_banners(null)$$) like '%NOT_ADMIN%');
select pg_temp.check('anon cannot run admin', pg_temp.err($$select * from public.store_admin_banners()$$) like '%permission denied%');
select pg_temp.check('no direct table access', pg_temp.err($$select * from store.banners$$) like '%permission denied%');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', false);
select pg_temp.check('non-admin blocked', pg_temp.err($$select * from public.store_admin_banners()$$) like '%NOT_ADMIN%');
select pg_temp.check('non-admin cannot delete', pg_temp.err(format('select public.store_admin_remove_banner(%s)', :b1)) like '%NOT_ADMIN%');
reset role;

\set QUIET off
select ok, count(*) from r_results group by ok;
select name, detail from r_results where not ok;
