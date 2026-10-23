-- v1.24 — ولاية المحل ونطاق البحث عن الخط (pattern 21; owner decision 2026-10-23)
--  * Every shop account has a province (wilaya), set by the owner (customer page) or by the shop itself
--    («حسابي»); the owner's own shop account has one too. The 58 provinces are data, not code: new ones
--    are added as rows. Daira / commune can be added later (additive).
--  * IDOOM known line for a customer: searched by the full number inside the shops of his province only
--    (their top-ups and checks; the owner's jobs count for his shop's province). The full offer text is
--    shown; never which shop, when or how much (checked_at only for the customer's own jobs).
--    A shop without a province sees its own lines only, as before. Unknown number: nothing.
-- Additive only: new table, new column, new functions, create or replace of store_idoom_line_info_impl
-- (same signature).

create table store.wilayas (
  code int primary key check (code between 1 and 99),
  name_ar text not null check (length(btrim(name_ar)) between 1 and 60),
  name_fr text not null check (length(btrim(name_fr)) between 1 and 60)
);
alter table store.wilayas enable row level security;
revoke all on store.wilayas from public, anon, authenticated;

insert into store.wilayas (code, name_ar, name_fr) values
  (1, 'أدرار', 'Adrar'),
  (2, 'الشلف', 'Chlef'),
  (3, 'الأغواط', 'Laghouat'),
  (4, 'أم البواقي', 'Oum El Bouaghi'),
  (5, 'باتنة', 'Batna'),
  (6, 'بجاية', 'Béjaïa'),
  (7, 'بسكرة', 'Biskra'),
  (8, 'بشار', 'Béchar'),
  (9, 'البليدة', 'Blida'),
  (10, 'البويرة', 'Bouira'),
  (11, 'تمنراست', 'Tamanrasset'),
  (12, 'تبسة', 'Tébessa'),
  (13, 'تلمسان', 'Tlemcen'),
  (14, 'تيارت', 'Tiaret'),
  (15, 'تيزي وزو', 'Tizi Ouzou'),
  (16, 'الجزائر', 'Alger'),
  (17, 'الجلفة', 'Djelfa'),
  (18, 'جيجل', 'Jijel'),
  (19, 'سطيف', 'Sétif'),
  (20, 'سعيدة', 'Saïda'),
  (21, 'سكيكدة', 'Skikda'),
  (22, 'سيدي بلعباس', 'Sidi Bel Abbès'),
  (23, 'عنابة', 'Annaba'),
  (24, 'قالمة', 'Guelma'),
  (25, 'قسنطينة', 'Constantine'),
  (26, 'المدية', 'Médéa'),
  (27, 'مستغانم', 'Mostaganem'),
  (28, 'المسيلة', 'M''Sila'),
  (29, 'معسكر', 'Mascara'),
  (30, 'ورقلة', 'Ouargla'),
  (31, 'وهران', 'Oran'),
  (32, 'البيض', 'El Bayadh'),
  (33, 'إليزي', 'Illizi'),
  (34, 'برج بوعريريج', 'Bordj Bou Arréridj'),
  (35, 'بومرداس', 'Boumerdès'),
  (36, 'الطارف', 'El Tarf'),
  (37, 'تندوف', 'Tindouf'),
  (38, 'تيسمسيلت', 'Tissemsilt'),
  (39, 'الوادي', 'El Oued'),
  (40, 'خنشلة', 'Khenchela'),
  (41, 'سوق أهراس', 'Souk Ahras'),
  (42, 'تيبازة', 'Tipaza'),
  (43, 'ميلة', 'Mila'),
  (44, 'عين الدفلى', 'Aïn Defla'),
  (45, 'النعامة', 'Naâma'),
  (46, 'عين تموشنت', 'Aïn Témouchent'),
  (47, 'غرداية', 'Ghardaïa'),
  (48, 'غليزان', 'Relizane'),
  (49, 'تيميمون', 'Timimoun'),
  (50, 'برج باجي مختار', 'Bordj Badji Mokhtar'),
  (51, 'أولاد جلال', 'Ouled Djellal'),
  (52, 'بني عباس', 'Béni Abbès'),
  (53, 'عين صالح', 'In Salah'),
  (54, 'عين قزام', 'In Guezzam'),
  (55, 'تقرت', 'Touggourt'),
  (56, 'جانت', 'Djanet'),
  (57, 'المغير', 'El M''Ghair'),
  (58, 'المنيعة', 'El Meniaa');

alter table store.customers add column wilaya_code int references store.wilayas(code);
create index on store.customers (wilaya_code) where wilaya_code is not null;

-- ---------------------------------------------------------------------
-- Everyone: the list (not sensitive)
-- ---------------------------------------------------------------------
create function private.store_wilayas_impl()
returns table (code int, name_ar text, name_fr text)
language sql stable security definer set search_path = '' as $$
  select w.code, w.name_ar, w.name_fr from store.wilayas w order by w.code;
$$;

-- ---------------------------------------------------------------------
-- Customer (shop): read / set his own province
-- ---------------------------------------------------------------------
create function private.store_my_wilaya_impl(p_token text) returns int
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  return (select c.wilaya_code from store.customers c where c.id = v);
end;
$$;

create function private.store_set_my_wilaya_impl(p_token text, p_code int) returns void
language plpgsql security definer set search_path = '' as $$
declare v bigint := private.store_session_customer(p_token);
begin
  if p_code is not null and not exists (select 1 from store.wilayas w where w.code = p_code) then
    raise exception 'WILAYA_NOT_FOUND';
  end if;
  update store.customers c set wilaya_code = p_code where c.id = v;
end;
$$;

-- ---------------------------------------------------------------------
-- Owner: any account, his own shop included
-- ---------------------------------------------------------------------
create function private.store_admin_set_customer_wilaya_impl(p_customer_id bigint, p_code int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  if p_code is not null and not exists (select 1 from store.wilayas w where w.code = p_code) then
    raise exception 'WILAYA_NOT_FOUND';
  end if;
  update store.customers c set wilaya_code = p_code where c.id = p_customer_id;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
end;
$$;

create function private.store_admin_customer_wilayas_impl()
returns table (customer_id bigint, is_shop boolean, wilaya_code int)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select c.id, c.is_shop, c.wilaya_code from store.customers c order by c.id;
end;
$$;

-- ---------------------------------------------------------------------
-- Known line, inside the customer's province (same signature as v1.23)
-- ---------------------------------------------------------------------
create or replace function private.store_idoom_line_info_impl(p_token text, p_line text)
returns table (offer text, checked_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  v bigint := private.store_session_customer(p_token);
  v_line text := private.store_idoom_line(p_line);
  v_wilaya int := (select c.wilaya_code from store.customers c where c.id = v);
  v_shop_wilaya int := (select c.wilaya_code from store.customers c where c.is_shop);
begin
  return query
  select j.offer, case when j.customer_id = v then coalesce(j.finished_at, j.claimed_at) end
  from store.idoom_jobs j
  left join store.customers jc on jc.id = j.customer_id
  where j.line = v_line and j.offer is not null and j.status <> 'cancelled'
    and (j.customer_id = v
         or (v_wilaya is not null and (jc.wilaya_code = v_wilaya
                                       or (j.customer_id is null and v_shop_wilaya = v_wilaya))))
  order by coalesce(j.finished_at, j.claimed_at) desc nulls last, j.id desc
  limit 1;
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers
-- ---------------------------------------------------------------------
create function public.store_wilayas() returns table (code int, name_ar text, name_fr text)
language sql set search_path = '' as $$ select * from private.store_wilayas_impl(); $$;
create function public.store_my_wilaya(p_token text) returns int
language sql set search_path = '' as $$ select private.store_my_wilaya_impl(p_token); $$;
create function public.store_set_my_wilaya(p_token text, p_code int) returns void
language sql set search_path = '' as $$ select private.store_set_my_wilaya_impl(p_token, p_code); $$;
create function public.store_admin_set_customer_wilaya(p_customer_id bigint, p_code int) returns void
language sql set search_path = '' as $$ select private.store_admin_set_customer_wilaya_impl(p_customer_id, p_code); $$;
create function public.store_admin_customer_wilayas() returns table (customer_id bigint, is_shop boolean, wilaya_code int)
language sql set search_path = '' as $$ select * from private.store_admin_customer_wilayas_impl(); $$;

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
      and p.proname in ('store_wilayas_impl', 'store_wilayas', 'store_my_wilaya_impl', 'store_my_wilaya',
                        'store_set_my_wilaya_impl', 'store_set_my_wilaya',
                        'store_admin_set_customer_wilaya_impl', 'store_admin_set_customer_wilaya',
                        'store_admin_customer_wilayas_impl', 'store_admin_customer_wilayas')
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
