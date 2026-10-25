-- card-store v1.34: shop Flexy follows up by itself.
--
-- Before: a shop's request moved from «جارٍ» to its result only while that shop's Flexy page was open.
-- Now: every minute, when (and only when) a request is still open, the database asks store-flexy
-- to follow up every open request with Flexy Core (POST /store-flexy/internal/sweep).
--
-- The call carries a secret kept in Vault ('store_flexy_sweep_secret', generated here, never shown);
-- store-flexy hands it back to store_flexy_sweep_jobs, which lists the open jobs only if it matches.

create function private.store_flexy_sweep_jobs_impl(p_secret text)
returns table (job_id bigint, core_key text, status text, phone text, amount int, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare v_secret text;
begin
  select d.decrypted_secret into v_secret from vault.decrypted_secrets d where d.name = 'store_flexy_sweep_secret';
  if v_secret is null or p_secret is null or p_secret <> v_secret then
    raise exception 'NOT_ALLOWED' using errcode = 'insufficient_privilege';
  end if;
  return query select * from private.store_flexy_open_jobs_impl(null);
end;
$$;

create function public.store_flexy_sweep_jobs(p_secret text)
returns table (job_id bigint, core_key text, status text, phone text, amount int, created_at timestamptz)
language sql as $$ select * from private.store_flexy_sweep_jobs_impl(p_secret) $$;

-- The minute tick: nothing open, no call.
create function private.store_flexy_sweep_tick(p_url text)
returns void
language plpgsql security definer set search_path = '' as $$
declare v_secret text;
begin
  if not exists (select 1 from store.flexy_jobs j where j.status in ('queued', 'sent')) then return; end if;
  select d.decrypted_secret into v_secret from vault.decrypted_secrets d where d.name = 'store_flexy_sweep_secret';
  if v_secret is null then return; end if;
  perform net.http_post(url := p_url, body := jsonb_build_object('secret', v_secret),
                        headers := '{"content-type": "application/json"}'::jsonb, timeout_milliseconds := 20000);
end;
$$;

revoke all on function private.store_flexy_sweep_jobs_impl(text) from public, anon, authenticated;
revoke all on function public.store_flexy_sweep_jobs(text) from public, anon, authenticated;
grant execute on function public.store_flexy_sweep_jobs(text) to service_role;
revoke all on function private.store_flexy_sweep_tick(text) from public, anon, authenticated;

-- Production only (Vault, pg_net and pg_cron exist there); local test databases skip it.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'supabase_vault') then
    if not exists (select 1 from vault.secrets where name = 'store_flexy_sweep_secret') then
      perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'store_flexy_sweep_secret');
    end if;
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('card_store_flexy_sweep', '* * * * *',
      $c$select private.store_flexy_sweep_tick('https://wqyebqzbbpohbnznqdjj.supabase.co/functions/v1/store-flexy/internal/sweep')$c$);
  end if;
end;
$$;
