-- =====================================================================
-- Card Store v1.6 — self top-up only in multiples of 500 DZD (owner decision 2026-10-21)
-- 500, 1000, 1500 … — no awkward amounts in the customer's debt.
-- =====================================================================
create or replace function private.store_self_topup_impl(p_token text, p_amount bigint, p_request_id uuid)
returns table (balance bigint, debt bigint)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v bigint := private.store_session_customer(p_token);
  r store.wallet_entries;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into r from store.wallet_entries where request_id = p_request_id;
  if not found then
    if not (select c.self_topup from store.customers c where c.id = v) then raise exception 'SELF_TOPUP_DISABLED'; end if;
    if p_amount is null or p_amount <= 0 or p_amount % 500 <> 0 then raise exception 'AMOUNT_STEP_500'; end if;
    r := private.store_post_entry(v, 'self', p_amount, 'شحن ذاتي', null, null, p_request_id, null);
  elsif r.customer_id <> v then
    raise exception 'REQUEST_ID_CONFLICT';
  end if;
  return query select c.balance, c.debt from store.customers c where c.id = v;
end;
$$;
