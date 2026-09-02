-- ============================================================
-- Hardening: leftover schema/function privileges (additive, safe)
-- ============================================================
-- Addressed here without touching previously shipped migrations:
--   1. API-exposed roles must not create objects in the public schema.
--      (The earlier blanket revokes removed TABLE grants, but the schema-level
--      CREATE privilege inherited from the PUBLIC pseudo-role was not removed.)
--   2. Objects created by future migrations must not silently inherit
--      PUBLIC EXECUTE or anon/authenticated write grants.
--   3. The Auth profile trigger runs as its owner; a later blanket
--      "grant execute on all functions in schema public to authenticated"
--      had re-exposed direct EXECUTE on it. Re-revoke it as a final cleanup.
--
-- These are privilege revocations only: no schema/object changes, no data
-- changes, and they are idempotent. Existing explicit GRANTs (e.g. SELECT
-- policies, api_* EXECUTE to authenticated) are unaffected.

-- 1) Remove object-creation ability from the API/global roles in `public`.
revoke create on schema public from public, anon, authenticated;

-- 2) Future objects created by the migration role (postgres) must not inherit
--    PUBLIC EXECUTE on functions nor write grants on tables by default.
alter default privileges for role postgres in schema public
  revoke execute on functions from public;
alter default privileges for role postgres in schema public
  revoke insert, update, delete on tables from anon, authenticated;

-- 3) The Auth profile trigger function is owner-only; no caller needs direct EXECUTE.
revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;
