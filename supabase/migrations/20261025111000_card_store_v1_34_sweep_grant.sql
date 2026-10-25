-- v1.34 fix: the public wrapper runs as the caller, so service_role also needs the private function
-- (same as store_flexy_open_jobs in v1.33). Without it every sweep answered NOT_ALLOWED.
grant execute on function private.store_flexy_sweep_jobs_impl(text) to service_role;
