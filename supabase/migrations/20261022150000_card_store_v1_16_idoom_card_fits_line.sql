-- v1.16: the card must fit the line, checked here and not only in the page. A 4G LTE line
-- (213 + 9 digits) takes only an IDOOM 4G/LTE card; a fixed line (9 digits) only an IDOOM
-- ADSL/FTTH card. Any other product (Mobilis, games…) is refused for an IDOOM top-up.
-- Same rule as the page: "4g" or "lte" in the brand or product name marks a 4G card.

create or replace function private.store_idoom_check_product(p_product_id bigint, p_line text) returns void
language plpgsql stable security definer set search_path = '' as $$
declare v_name text;
begin
  select b.name || ' ' || p.name into v_name
  from store.products p join store.brands b on b.id = p.brand_id
  where p.id = p_product_id and b.category = 'net' and b.name ~* 'idoom';
  if v_name is null then raise exception 'NOT_IDOOM_CARD'; end if;
  if (v_name ~* '4g|lte') <> (p_line ~ '^213') then raise exception 'CARD_LINE_MISMATCH'; end if;
end;
$$;

create or replace function private.store_admin_idoom_create_impl(p_product_id bigint, p_line text, p_request_id uuid)
returns table (job_id bigint, status text)
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  v_line text;
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs where request_id = p_request_id;
  if not found then
    v_line := private.store_idoom_line(p_line);
    if not exists (select 1 from store.products p join store.brands b on b.id = p.brand_id
                   where p.id = p_product_id and p.active and b.active) then
      raise exception 'PRODUCT_NOT_FOUND';
    end if;
    perform private.store_idoom_check_product(p_product_id, v_line);
    if not exists (select 1 from store.codes k where k.product_id = p_product_id and k.status = 'available') then
      raise exception 'OUT_OF_STOCK';
    end if;
    insert into store.idoom_jobs (line, product_id, request_id, created_by)
    values (v_line, p_product_id, p_request_id, auth.uid())
    returning * into j;
  end if;
  return query select j.id, j.status;
end;
$$;

-- Retry may correct the line; the corrected line must still fit the job's card.
create or replace function private.store_admin_idoom_retry_impl(p_job_id bigint, p_line text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  v_line text;
  v text;
begin
  perform private.store_require_admin();
  select * into j from store.idoom_jobs
   where id = p_job_id and kind = 'charge' and status = 'failed' and outcome = 'PRE_SUBMIT_FAILED' for update;
  if not found then raise exception 'NOT_RETRYABLE'; end if;
  v_line := private.store_idoom_line(coalesce(nullif(p_line, ''), j.line));
  perform private.store_idoom_check_product(j.product_id, v_line);
  update store.idoom_jobs
     set line = v_line,
         reply = left('[محاولة سابقة ' || line || ': ' || coalesce(outcome, '') || '] ' || coalesce(reply, ''), 2000),
         status = 'queued', outcome = null, offer = null, executor_id = null, claimed_at = null, finished_at = null
   where id = j.id
  returning status into v;
  return v;
end;
$$;

revoke all on function private.store_idoom_check_product(bigint, text) from public, anon, authenticated;
