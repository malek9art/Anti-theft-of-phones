-- New functions added after the first privilege migration inherit PostgreSQL's PUBLIC EXECUTE default.
-- Reset that default exposure once more, then allow authenticated requests only through checked functions.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) from public, anon, authenticated;
grant execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) to service_role;
revoke execute on function public.api_consume_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.api_consume_rate_limit(text, integer, integer) to service_role;
revoke all on all functions in schema private from public, anon, authenticated;
