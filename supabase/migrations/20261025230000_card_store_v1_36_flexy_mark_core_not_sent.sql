-- v1.36 — A shop's Flexy request the core says was not sent is closed and refunded, whatever its
-- local state (code review 2026-10-25, owner «نفّذ إصلاح العملية العالقة»).
--
-- Before: store_flexy_mark refused not_sent on a job already «sent» (FLEXY_ALREADY_SENT), and
-- store-flexy ignored the error. A request the core accepted and then judged not sent (the
-- confirmation screen did not match, the code never left the modem, the request expired in the
-- queue) stayed «sent» for ever: the shop's money held, the number busy for every shop
-- (FLEXY_PHONE_BUSY), one of its 3 open requests used, followed up every minute.
-- Now not_sent is the core's verdict («nothing left the SIM»), as final as failed: it closes the
-- job and refunds once. store-flexy only asks for not_sent from a queued job when the core
-- refused the request itself (a 4xx: the core finds an existing key before anything else), or
-- from the core's own status of the operation.
-- No money is sent by this migration; the refund is store_flexy_refund (once per job).

create or replace function private.store_flexy_mark_impl(p_job_id bigint, p_status text, p_reply text)
returns text
language plpgsql security definer set search_path = '' as $$
declare j store.flexy_jobs;
begin
  if p_status not in ('sent', 'success', 'failed', 'review', 'not_sent') then raise exception 'FLEXY_BAD_STATUS'; end if;
  select * into j from store.flexy_jobs x where x.id = p_job_id for update;
  if not found then raise exception 'FLEXY_JOB_NOT_FOUND'; end if;
  if j.status in ('success', 'failed', 'not_sent') then return j.status; end if;
  if j.status = 'review' and p_status = 'sent' then return j.status; end if;
  update store.flexy_jobs x
     set status = p_status,
         network_reply = coalesce(left(nullif(btrim(p_reply), ''), 500), x.network_reply),
         decided_by = case when p_status in ('success', 'failed', 'not_sent', 'review') then 'core' else x.decided_by end,
         updated_at = now(),
         finished_at = case when p_status in ('success', 'failed', 'not_sent') then now() end
   where x.id = j.id;
  if p_status in ('failed', 'not_sent') then
    perform private.store_flexy_refund(j, case p_status when 'failed' then 'فليكسي: فشل، أُعيد المبلغ'
                                                         else 'فليكسي: لم يُرسل، أُعيد المبلغ' end);
  end if;
  return p_status;
end;
$$;
