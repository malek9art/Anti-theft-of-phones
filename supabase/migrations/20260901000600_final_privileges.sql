-- Final privilege reset runs after every API migration. Do not expose functions to anon/public.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to authenticated;

-- Auth-event ingestion is server-to-server only. It is called by an Edge Function whose hook secret
-- is configured outside source control.
revoke execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) from public, anon, authenticated;
grant execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) to service_role;

revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
