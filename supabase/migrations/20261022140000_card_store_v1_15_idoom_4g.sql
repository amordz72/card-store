-- v1.15: IDOOM 4G LTE lines. My IDOOM takes them in the same field as ADSL/FTTH, as 12 digits
-- starting with 213 (observed 2026-10-22: 2134XXXXXXXX → «Recharge 4GLTE» page). Fixed lines stay 9 digits.

alter table store.idoom_jobs drop constraint idoom_jobs_line_check;
alter table store.idoom_jobs add constraint idoom_jobs_line_check check (line ~ '^(0[0-9]{8}|213[0-9]{9})$') not valid;  -- keeps old test rows

create or replace function private.store_idoom_line(p_line text) returns text
language plpgsql immutable set search_path = '' as $$
declare v text := regexp_replace(coalesce(p_line, ''), '[^0-9]', '', 'g');
begin
  if v !~ '^(0[0-9]{8}|213[0-9]{9})$' then raise exception 'INVALID_LINE'; end if;
  return v;
end;
$$;
revoke all on function private.store_idoom_line(text) from public, anon, authenticated;
