-- v1.31 — an IDOOM job no phone takes does not wait forever (owner request 2026-10-23).
-- A job still waiting after 5 minutes is cancelled: a card it holds goes back to stock and its price
-- back to the buyer (store_idoom_return_card), so a phone switched on later never runs an old request.
-- A job a phone took but never reported within 15 minutes (phone off or app closed):
--   lookup, or charge before the card was taken → failed (no card used);
--   charge with its card already handed to the phone → review (Valider may have been pressed).
-- Runs every minute (pg_cron) and before every claim, so the phone itself never takes a stale job.

-- Filled for open jobs only: some finished rows predate the stricter line check (NOT VALID) and
-- cannot be rewritten. A null queued_at falls back to created_at.
alter table store.idoom_jobs add column queued_at timestamptz;
alter table store.idoom_jobs alter column queued_at set default now();
update store.idoom_jobs set queued_at = created_at where status in ('queued', 'claimed');

-- Every return to «queued» (automatic second attempt, admin retry) starts a new wait.
create function private.store_idoom_jobs_queued_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status = 'queued' and old.status is distinct from 'queued' then new.queued_at := now(); end if;
  return new;
end;
$$;
create trigger idoom_jobs_queued_at before update of status on store.idoom_jobs
  for each row execute function private.store_idoom_jobs_queued_at();

create function private.store_idoom_expire() returns int
language plpgsql security definer set search_path = '' as $$
declare
  j store.idoom_jobs;
  n int := 0;
begin
  for j in
    select * from store.idoom_jobs x
     where (x.status = 'queued' and coalesce(x.queued_at, x.created_at) < now() - interval '5 minutes')
        or (x.status = 'claimed' and x.claimed_at < now() - interval '15 minutes')
     order by x.id
     for update skip locked
  loop
    if j.status = 'queued' then
      update store.idoom_jobs
         set status = 'cancelled', finished_at = now(),
             reply = left('[انتهت المهلة: لم يأخذه أي هاتف خلال 5 دقائق] ' || coalesce(reply, ''), 2000)
       where id = j.id;
      perform private.store_idoom_return_card(j.id);
    elsif j.kind = 'lookup' or j.code_id is null then
      update store.idoom_jobs
         set status = 'failed', finished_at = now(),
             reply = left('[انتهت المهلة: الهاتف لم يُرسل النتيجة خلال 15 دقيقة، لم تُستعمل بطاقة] ' || coalesce(reply, ''), 2000)
       where id = j.id;
    else
      update store.idoom_jobs
         set status = 'review', finished_at = now(),
             reply = left('[انتهت المهلة: الهاتف أخذ البطاقة ولم يُرسل النتيجة خلال 15 دقيقة — تحقق من الخط] ' || coalesce(reply, ''), 2000)
       where id = j.id;
    end if;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- The phone's claim expires stale jobs first (same bodies as v1.11 / v1.12 otherwise).
create or replace function private.store_exec_claim_impl(p_token text)
returns table (job_id bigint, line text, code text)
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  j store.idoom_jobs;
begin
  perform private.store_idoom_expire();
  if exists (select 1 from store.idoom_jobs x where x.executor_id = v_exec and x.status = 'claimed') then
    return;
  end if;
  select * into j from store.idoom_jobs x where x.status = 'queued' and x.kind = 'charge' order by x.id limit 1 for update skip locked;
  if not found then return; end if;
  update store.idoom_jobs set status = 'claimed', executor_id = v_exec, claimed_at = now() where id = j.id;
  return query select j.id, j.line, k.code from store.codes k where k.id = j.code_id;
end;
$$;

create or replace function private.store_exec_claim_v2_impl(p_token text)
returns table (job_id bigint, kind text, line text, code text)
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  j store.idoom_jobs;
begin
  perform private.store_idoom_expire();
  if exists (select 1 from store.idoom_jobs x where x.executor_id = v_exec and x.status = 'claimed') then
    return;
  end if;
  select * into j from store.idoom_jobs x where x.status = 'queued' order by x.id limit 1 for update skip locked;
  if not found then return; end if;
  update store.idoom_jobs set status = 'claimed', executor_id = v_exec, claimed_at = now() where id = j.id;
  return query select j.id, j.kind, j.line, (select k.code from store.codes k where k.id = j.code_id);
end;
$$;

revoke all on function private.store_idoom_jobs_queued_at() from public, anon, authenticated;
revoke all on function private.store_idoom_expire() from public, anon, authenticated;

-- Every minute where pg_cron exists (production); local test databases rely on the claim alone.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('card_store_idoom_expire', '* * * * *', 'select private.store_idoom_expire()');
  end if;
end $$;
