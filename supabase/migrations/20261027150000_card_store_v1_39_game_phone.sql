-- v1.39 — Free Fire top-up on the Rech-Doom phone (owner «سجّل ونفّذ الآلي», 2026-10-27)
-- Decision record: developer/projects/card-store/FREE-FIRE-TOPUP-2026-10-23.md (section «المسار 2»)
--  * Shop2game (Garena's official top-up site): log in with the player id only (no Garena account),
--    «استرداد» → «بطاقات جارينا» → the card code → «تأكيد». No captcha (owner). After «تأكيد» a screen with
--    numbers appears; the phone saves that screen's text as the raw reply.
--  * A phone the owner switches on for games (store.executors.game_enabled) takes waiting orders from the
--    same queue as the people, one at a time. While it is seen (every 5 s) the service counts as open.
--  * The phone is transport only. It reports 'not_sent' (stopped before «تأكيد»: the card was not used),
--    'sent' (with the raw reply) or 'unknown' (cannot tell whether «تأكيد» was pressed).
--    The decision is here:
--      - not_sent → the order goes back to the queue for a person, and the phone never takes it again;
--      - sent → the reply is matched against store.game_reply_rules (data, filled from real replies):
--          done → finished with the transaction number; used_card → next card, back to the queue;
--          no rule matches → «يحتاج مراجعة»: it stays with the phone and the owner finishes it
--          (تمّت / مستعملة / لم تتم) with the reply in front of him. No refund ever without the owner.
--      - unknown → «يحتاج مراجعة».
--    The rules table starts empty, so every reply needs the owner's review until a real reply is known.
--  * A phone with an order in progress or waiting for review gets no other order (IDOOM or game).
-- Additive only: new columns, new table, new functions, create or replace of existing ones (same signatures).

alter table store.executors add column game_enabled boolean not null default false;

alter table store.game_orders add column claimed_executor bigint references store.executors(id);
alter table store.game_orders add column auto_state text check (auto_state is null or auto_state in ('working', 'review'));
alter table store.game_orders add column auto_skip boolean not null default false;   -- the phone stopped on it once
alter table store.game_orders add column reply text check (reply is null or length(reply) <= 3000);
alter table store.game_orders add column player_name text check (player_name is null or length(player_name) <= 60);
alter table store.game_orders add column auto_note text check (auto_note is null or length(auto_note) <= 300);
create index game_orders_phone on store.game_orders (claimed_executor) where status = 'claimed';

-- Known replies of the top-up site. pattern: case-insensitive regex on the reply text. For 'done',
-- txn_pattern (optional) is a regex whose first capture group is the transaction number. First active rule by id wins.
create table store.game_reply_rules (
  id bigint generated always as identity primary key,
  pattern text not null check (length(pattern) between 1 and 300),
  outcome text not null check (outcome in ('done', 'used_card')),
  txn_pattern text check (txn_pattern is null or length(txn_pattern) between 1 and 300),
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  created_at timestamptz not null default now()
);
alter table store.game_reply_rules enable row level security;
revoke all on store.game_reply_rules from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create function private.store_game_classify(p_reply text, out outcome text, out txn text)
language plpgsql stable security definer set search_path = '' as $$
declare r store.game_reply_rules;
begin
  for r in select * from store.game_reply_rules x where x.active order by x.id loop
    if coalesce(p_reply, '') ~* r.pattern then
      outcome := r.outcome;
      if r.outcome = 'done' and r.txn_pattern is not null then
        txn := nullif(left(btrim(coalesce(substring(p_reply from '(?i)' || r.txn_pattern), '')), 60), '');
      end if;
      return;
    end if;
  end loop;
  outcome := 'review';
end;
$$;

-- The card was already used: void it, put the next card on the order and send it back to the queue;
-- no other card = failed with a refund (the voided card does not come back). Same rules as «مستعملة» in v1.25.
create function private.store_game_used_card(p_game_id bigint, p_note text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  g store.game_orders;
  v_next bigint;
begin
  select * into g from store.game_orders where id = p_game_id for update;
  update store.codes set status = 'void', void_reason = 'شحن لعبة: البطاقة مستعملة (طلب ' || g.id || ')', voided_at = now()
   where id = g.code_id;
  select k.id into v_next from store.codes k
   where k.product_id = g.product_id and k.status = 'available' and not k.frozen order by k.id limit 1 for update skip locked;
  if v_next is null then
    update store.game_orders set status = 'failed', cards_used = cards_used + 1, finished_at = now(), auto_state = null,
           reason = left('البطاقة مستعملة ولا توجد بطاقة أخرى' || coalesce(' · ' || nullif(btrim(p_note), ''), ''), 300)
     where id = g.id;
    perform private.store_game_refund(g.id, false, 'شحن لعبة: لم يتم، أُعيد المبلغ');
    return 'failed';
  end if;
  update store.codes set status = 'sold', order_id = g.order_id, sold_at = now() where id = v_next;
  update store.game_orders set code_id = v_next, cards_used = cards_used + 1, status = 'queued',
         claimed_admin = null, claimed_operator = null, claimed_executor = null, claimed_at = null, auto_state = null
   where id = g.id;
  return 'queued';
end;
$$;

-- A phone order in progress (not yet reported) is left alone by people for 10 minutes; after that the
-- owner may take it over (the phone stopped answering).
create function private.store_game_phone_working(g store.game_orders) returns boolean
language sql stable set search_path = '' as $$
  select g.claimed_executor is not null and g.auto_state = 'working' and g.claimed_at > now() - interval '10 minutes';
$$;

-- ---------------------------------------------------------------------
-- Phone (executor token)
-- ---------------------------------------------------------------------
create function private.store_exec_game_claim_impl(p_token text)
returns table (game_id bigint, player_id text, code text, url text)
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  g store.game_orders;
begin
  if not exists (select 1 from store.executors e where e.id = v_exec and e.game_enabled) then return; end if;
  if exists (select 1 from store.idoom_jobs j where j.executor_id = v_exec and j.status = 'claimed')
     or exists (select 1 from store.game_orders x where x.claimed_executor = v_exec and x.status = 'claimed') then
    return;
  end if;
  select * into g from store.game_orders x
   where x.status = 'queued' and not x.auto_skip and x.code_id is not null
   order by x.id limit 1 for update skip locked;
  if not found then return; end if;
  update store.game_orders set status = 'claimed', claimed_executor = v_exec, claimed_at = now(), auto_state = 'working'
   where id = g.id;
  return query select g.id, g.player_id, (select k.code from store.codes k where k.id = g.code_id),
                      (select s.game_topup_url from store.settings s where s.id = 1);
end;
$$;

-- p_outcome: 'not_sent' | 'sent' | 'unknown'. Returns the order's new state: queued / done / failed / review.
create function private.store_exec_game_report_impl(p_token text, p_game_id bigint, p_outcome text, p_reply text, p_player_name text)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  g store.game_orders;
  v_code text;
  v_reply text;
  c record;
begin
  if p_outcome is null or p_outcome not in ('not_sent', 'sent', 'unknown') then raise exception 'INVALID_RESULT'; end if;
  select * into g from store.game_orders x
   where x.id = p_game_id and x.claimed_executor = v_exec and x.status = 'claimed' and x.auto_state = 'working'
  for update;
  if not found then raise exception 'GAME_NOT_OPEN'; end if;
  -- the card code never stays in a reply
  select k.code into v_code from store.codes k where k.id = g.code_id;
  v_reply := left(coalesce(p_reply, ''), 3000);
  if v_code is not null and length(v_code) >= 4 then v_reply := replace(v_reply, v_code, '****'); end if;
  v_reply := nullif(btrim(v_reply), '');
  update store.game_orders set reply = v_reply,
         player_name = coalesce(nullif(left(btrim(coalesce(p_player_name, '')), 60), ''), player_name)
   where id = g.id;

  if p_outcome = 'not_sent' then
    update store.game_orders set status = 'queued', claimed_executor = null, claimed_at = null, auto_state = null,
           auto_skip = true, auto_note = left('الهاتف توقف قبل «تأكيد»' || coalesce(': ' || left(v_reply, 200), ''), 300)
     where id = g.id;
    return 'queued';
  end if;
  if p_outcome = 'sent' then
    select * into c from private.store_game_classify(v_reply);
    if c.outcome = 'done' then
      update store.game_orders set status = 'done', txn_ref = c.txn, finished_at = now(), auto_state = null where id = g.id;
      return 'done';
    elsif c.outcome = 'used_card' then
      return private.store_game_used_card(g.id, 'الهاتف');
    end if;
  end if;
  update store.game_orders set auto_state = 'review',
         auto_note = case when p_outcome = 'unknown' then 'لا يُعرف هل ضُغط «تأكيد»' else 'رد غير معروف' end
   where id = g.id;
  return 'review';
end;
$$;

-- ---------------------------------------------------------------------
-- Owner
-- ---------------------------------------------------------------------
create function private.store_admin_executors_v2_impl()
returns table (id bigint, name text, active boolean, last_seen_at timestamptz, game_enabled boolean)
language plpgsql security definer set search_path = '' as $$
begin
  perform private.store_require_admin();
  return query select e.id, e.name, e.active, e.last_seen_at, e.game_enabled from store.executors e
  where e.deleted_at is null
  order by e.last_seen_at desc nulls last, e.id desc;
end;
$$;

create function private.store_admin_executor_set_game_impl(p_executor_id bigint, p_enabled boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v boolean;
begin
  perform private.store_require_admin();
  update store.executors set game_enabled = coalesce(p_enabled, false)
   where id = p_executor_id and deleted_at is null
  returning game_enabled into v;
  if v is null then raise exception 'PHONE_NOT_FOUND'; end if;
  return v;
end;
$$;

-- The queue of v1.25 plus the phone's part: who took it (a phone shows «هاتف: name»), review state,
-- the reply, the player name the site showed, and the phone's note.
create function private.store_game_queue_v2_impl(p_token text, p_open boolean, p_limit int, p_offset int)
returns table (game_id bigint, customer_name text, player_id text, product_name text, status text, charged_amount bigint,
               code text, serial text, mine boolean, taken_by text, txn_ref text, reason text, cards_used int,
               created_at timestamptz, claimed_at timestamptz, finished_at timestamptz,
               by_phone boolean, auto_state text, reply text, player_name text, auto_note text, total_count bigint)
language plpgsql security definer set search_path = '' as $$
declare o record;
begin
  select * into o from private.store_game_operator(p_token);
  return query
  select g.id, c.name, g.player_id, p.name, g.status, ord.charged_amount,
         case when g.status = 'claimed' and mine.v then k.code end,
         case when g.status = 'claimed' and mine.v then k.serial end,
         mine.v,
         case when g.claimed_executor is not null then 'هاتف: ' || ex.name
              when g.claimed_operator is not null then oc.name when g.claimed_admin is not null then 'المدير' end,
         g.txn_ref, g.reason, g.cards_used, g.created_at, g.claimed_at, g.finished_at,
         g.claimed_executor is not null, g.auto_state, g.reply, g.player_name, g.auto_note,
         count(*) over ()
  from store.game_orders g
  join store.customers c on c.id = g.customer_id
  join store.products p on p.id = g.product_id
  join store.orders ord on ord.id = g.order_id
  left join store.codes k on k.id = g.code_id
  left join store.customers oc on oc.id = g.claimed_operator
  left join store.executors ex on ex.id = g.claimed_executor
  cross join lateral (select (g.claimed_executor is null
                              and g.claimed_admin is not distinct from o.admin_id and g.claimed_operator is not distinct from o.operator_id
                              and (g.claimed_admin is not null or g.claimed_operator is not null)) as v) mine
  where (g.status in ('queued', 'claimed')) = coalesce(p_open, true)
  order by case when coalesce(p_open, true) then g.id end asc, g.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 200) offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- ---------------------------------------------------------------------
-- Existing functions, same signatures (create or replace)
-- ---------------------------------------------------------------------
-- Open while a person pressed «متاح» (30 minutes) or a game phone is receiving (seen in the last 2 minutes).
create or replace function private.store_game_open() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from store.game_presence g where g.available and g.last_seen_at > now() - interval '30 minutes')
      or exists (select 1 from store.executors e
                 where e.game_enabled and e.active and e.deleted_at is null and e.last_seen_at > now() - interval '2 minutes');
$$;

-- Names on the board include the receiving game phones.
create or replace function private.store_game_board_impl(p_token text)
returns table (is_open boolean, me_available boolean, available_names text[], url text)
language plpgsql security definer set search_path = '' as $$
declare o record;
begin
  select * into o from private.store_game_operator(p_token);
  return query select
    private.store_game_open(),
    coalesce((select g.available and g.last_seen_at > now() - interval '30 minutes' from store.game_presence g
              where g.admin_id is not distinct from o.admin_id and g.customer_id is not distinct from o.operator_id), false),
    array(select coalesce(c.name, 'المدير') from store.game_presence g left join store.customers c on c.id = g.customer_id
          where g.available and g.last_seen_at > now() - interval '30 minutes' order by g.id)
    || array(select 'هاتف: ' || e.name from store.executors e
             where e.game_enabled and e.active and e.deleted_at is null and e.last_seen_at > now() - interval '2 minutes'
             order by e.id),
    (select s.game_topup_url from store.settings s where s.id = 1);
end;
$$;

-- v1.25 + a phone's order in progress cannot be given back; the owner can give back a phone order that is
-- waiting for review or that the phone stopped answering (10 minutes).
create or replace function private.store_game_claim_impl(p_token text, p_game_id bigint, p_claim boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  o record;
  g store.game_orders;
  v text;
begin
  select * into o from private.store_game_operator(p_token);
  if coalesce(p_claim, true) then
    update store.game_orders set status = 'claimed', claimed_admin = o.admin_id, claimed_operator = o.operator_id, claimed_at = now()
     where id = p_game_id and status = 'queued' returning status into v;
  else
    select * into g from store.game_orders x where x.id = p_game_id for update;
    if found and private.store_game_phone_working(g) then raise exception 'PHONE_WORKING'; end if;
    update store.game_orders set status = 'queued', claimed_admin = null, claimed_operator = null, claimed_executor = null,
           claimed_at = null, auto_state = null
     where id = p_game_id and status = 'claimed'
       and ((claimed_executor is null and claimed_admin is not distinct from o.admin_id and claimed_operator is not distinct from o.operator_id)
            or o.admin_id is not null)
    returning status into v;
  end if;
  if v is null then raise exception 'GAME_NOT_OPEN'; end if;
  return v;
end;
$$;

-- v1.25 + a phone's order: only the owner finishes it, and not while the phone is still working on it.
create or replace function private.store_game_finish_impl(p_token text, p_game_id bigint, p_result text, p_txn_ref text, p_reason text, p_card_back boolean)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  o record;
  g store.game_orders;
  v_next bigint;
begin
  select * into o from private.store_game_operator(p_token);
  select * into g from store.game_orders x where x.id = p_game_id and x.status = 'claimed'
     and ((x.claimed_executor is null and x.claimed_admin is not distinct from o.admin_id and x.claimed_operator is not distinct from o.operator_id)
          or o.admin_id is not null)
  for update;
  if not found then raise exception 'GAME_NOT_OPEN'; end if;
  if private.store_game_phone_working(g) then raise exception 'PHONE_WORKING'; end if;
  if p_result = 'done' then
    update store.game_orders set status = 'done', txn_ref = nullif(left(btrim(coalesce(p_txn_ref, '')), 60), ''), finished_at = now(),
           auto_state = null
     where id = g.id;
    return 'done';
  elsif p_result = 'used_card' then
    if g.claimed_executor is not null then
      -- the phone tried this card: the next card goes back to the queue (the phone may take it)
      return private.store_game_used_card(g.id, p_reason);
    end if;
    -- the shop's loss: that card is voided, the customer keeps his order with the next card
    update store.codes set status = 'void', void_reason = 'شحن لعبة: البطاقة مستعملة (طلب ' || g.id || ')', voided_at = now()
     where id = g.code_id;
    select k.id into v_next from store.codes k
     where k.product_id = g.product_id and k.status = 'available' and not k.frozen order by k.id limit 1 for update skip locked;
    if v_next is null then
      update store.game_orders set status = 'failed', cards_used = cards_used + 1, finished_at = now(),
             reason = left('البطاقة مستعملة ولا توجد بطاقة أخرى' || coalesce(' · ' || nullif(btrim(p_reason), ''), ''), 300)
       where id = g.id;
      perform private.store_game_refund(g.id, false, 'شحن لعبة: لم يتم، أُعيد المبلغ');
      return 'failed';
    end if;
    update store.codes set status = 'sold', order_id = g.order_id, sold_at = now() where id = v_next;
    update store.game_orders set code_id = v_next, cards_used = cards_used + 1 where id = g.id;
    return 'claimed';
  elsif p_result = 'failed' then
    update store.game_orders set status = 'failed', reason = nullif(left(btrim(coalesce(p_reason, '')), 300), ''), finished_at = now(),
           auto_state = null
     where id = g.id;
    perform private.store_game_refund(g.id, coalesce(p_card_back, false), 'شحن لعبة: لم يتم، أُعيد المبلغ');
    return 'failed';
  end if;
  raise exception 'INVALID_RESULT';
end;
$$;

-- IDOOM (v1.31 body): a phone busy with a game order gets no IDOOM job.
create or replace function private.store_exec_claim_v2_impl(p_token text)
returns table (job_id bigint, kind text, line text, code text)
language plpgsql security definer set search_path = '' as $$
declare
  v_exec bigint := private.store_exec_id(p_token);
  j store.idoom_jobs;
begin
  perform private.store_idoom_expire();
  if exists (select 1 from store.idoom_jobs x where x.executor_id = v_exec and x.status = 'claimed')
     or exists (select 1 from store.game_orders x where x.claimed_executor = v_exec and x.status = 'claimed') then
    return;
  end if;
  select * into j from store.idoom_jobs x where x.status = 'queued' order by x.id limit 1 for update skip locked;
  if not found then return; end if;
  update store.idoom_jobs set status = 'claimed', executor_id = v_exec, claimed_at = now() where id = j.id;
  return query select j.id, j.kind, j.line, (select k.code from store.codes k where k.id = j.code_id);
end;
$$;

-- v1.37 bodies + a phone holding a game order is busy too.
create or replace function private.store_admin_executor_set_active_impl(p_executor_id bigint, p_active boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v boolean;
begin
  perform private.store_require_admin();
  if not coalesce(p_active, true)
     and (exists (select 1 from store.idoom_jobs j where j.executor_id = p_executor_id and j.status = 'claimed')
          or exists (select 1 from store.game_orders x where x.claimed_executor = p_executor_id and x.status = 'claimed')) then
    raise exception 'PHONE_BUSY';
  end if;
  update store.executors set active = coalesce(p_active, true)
  where id = p_executor_id and deleted_at is null
  returning active into v;
  if v is null then raise exception 'PHONE_NOT_FOUND'; end if;
  return v;
end;
$$;

create or replace function private.store_admin_executor_delete_impl(p_executor_id bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_active boolean;
begin
  perform private.store_require_admin();
  select e.active into v_active from store.executors e
  where e.id = p_executor_id and e.deleted_at is null
  for update;
  if not found then raise exception 'PHONE_NOT_FOUND'; end if;
  if v_active then raise exception 'PHONE_ACTIVE'; end if;
  if exists (select 1 from store.idoom_jobs j where j.executor_id = p_executor_id and j.status = 'claimed')
     or exists (select 1 from store.game_orders x where x.claimed_executor = p_executor_id and x.status = 'claimed') then
    raise exception 'PHONE_BUSY';
  end if;
  update store.executors
  set deleted_at = now(), game_enabled = false,
      token_hash = 'deleted:' || id || ':' || encode(extensions.gen_random_bytes(16), 'hex')
  where id = p_executor_id;
  return true;
end;
$$;

-- ---------------------------------------------------------------------
-- Public wrappers and grants
-- ---------------------------------------------------------------------
create function public.store_exec_game_claim(p_token text) returns table (game_id bigint, player_id text, code text, url text)
language sql set search_path = '' as $$ select * from private.store_exec_game_claim_impl(p_token); $$;
create function public.store_exec_game_report(p_token text, p_game_id bigint, p_outcome text, p_reply text, p_player_name text) returns text
language sql set search_path = '' as $$ select private.store_exec_game_report_impl(p_token, p_game_id, p_outcome, p_reply, p_player_name); $$;
create function public.store_admin_executors_v2()
returns table (id bigint, name text, active boolean, last_seen_at timestamptz, game_enabled boolean)
language sql set search_path = '' as $$ select * from private.store_admin_executors_v2_impl(); $$;
create function public.store_admin_executor_set_game(p_executor_id bigint, p_enabled boolean) returns boolean
language sql set search_path = '' as $$ select private.store_admin_executor_set_game_impl(p_executor_id, p_enabled); $$;
create function public.store_game_queue_v2(p_token text, p_open boolean, p_limit int, p_offset int)
returns table (game_id bigint, customer_name text, player_id text, product_name text, status text, charged_amount bigint,
               code text, serial text, mine boolean, taken_by text, txn_ref text, reason text, cards_used int,
               created_at timestamptz, claimed_at timestamptz, finished_at timestamptz,
               by_phone boolean, auto_state text, reply text, player_name text, auto_note text, total_count bigint)
language sql set search_path = '' as $$ select * from private.store_game_queue_v2_impl(p_token, p_open, p_limit, p_offset); $$;

revoke all on function private.store_game_classify(text) from public, anon, authenticated;
revoke all on function private.store_game_used_card(bigint, text) from public, anon, authenticated;
revoke all on function private.store_game_phone_working(store.game_orders) from public, anon, authenticated;
revoke all on function private.store_game_open() from public, anon, authenticated;

-- phone calls: anon (the token decides); owner calls: authenticated; queue: operators (anon worker or owner)
revoke all on function private.store_exec_game_claim_impl(text) from public, anon, authenticated;
grant execute on function private.store_exec_game_claim_impl(text) to anon, authenticated;
revoke all on function public.store_exec_game_claim(text) from public, anon, authenticated;
grant execute on function public.store_exec_game_claim(text) to anon, authenticated;
revoke all on function private.store_exec_game_report_impl(text, bigint, text, text, text) from public, anon, authenticated;
grant execute on function private.store_exec_game_report_impl(text, bigint, text, text, text) to anon, authenticated;
revoke all on function public.store_exec_game_report(text, bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.store_exec_game_report(text, bigint, text, text, text) to anon, authenticated;

revoke all on function private.store_admin_executors_v2_impl() from public, anon, authenticated;
grant execute on function private.store_admin_executors_v2_impl() to authenticated;
revoke all on function public.store_admin_executors_v2() from public, anon, authenticated;
grant execute on function public.store_admin_executors_v2() to authenticated;
revoke all on function private.store_admin_executor_set_game_impl(bigint, boolean) from public, anon, authenticated;
grant execute on function private.store_admin_executor_set_game_impl(bigint, boolean) to authenticated;
revoke all on function public.store_admin_executor_set_game(bigint, boolean) from public, anon, authenticated;
grant execute on function public.store_admin_executor_set_game(bigint, boolean) to authenticated;

revoke all on function private.store_game_queue_v2_impl(text, boolean, int, int) from public, anon, authenticated;
grant execute on function private.store_game_queue_v2_impl(text, boolean, int, int) to anon, authenticated;
revoke all on function public.store_game_queue_v2(text, boolean, int, int) from public, anon, authenticated;
grant execute on function public.store_game_queue_v2(text, boolean, int, int) to anon, authenticated;
