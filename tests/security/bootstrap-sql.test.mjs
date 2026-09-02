import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const root = process.cwd()
const bootstrap = readFileSync(join(root, 'supabase/scripts/bootstrap_first_system_admin.sql'), 'utf8')

test('bootstrap SQL requires migrations before granting the first admin', () => {
  assert.match(bootstrap, /to_regclass\('public\.users'\) is null/)
  assert.match(bootstrap, /to_regclass\('public\.roles'\) is null/)
  assert.match(bootstrap, /to_regclass\('public\.user_roles'\) is null/)
  assert.match(bootstrap, /to_regclass\('auth\.users'\) is null/)
  assert.match(bootstrap, /MIGRATIONS_NOT_APPLIED/)
})

test('bootstrap SQL stops when the Auth account is missing or unconfirmed', () => {
  assert.match(bootstrap, /not exists \(select 1 from auth\.users where id = v_uuid\)/)
  assert.match(bootstrap, /confirmed_at is not null or email_confirmed_at is not null/)
  assert.match(bootstrap, /لم يُعثر على حساب Auth لهذا UUID/)
  assert.match(bootstrap, /حساب Auth غير مؤكد البريد بعد/)
})

test('bootstrap SQL creates the profile, activates, and grants system_admin exactly once', () => {
  assert.match(bootstrap, /insert into public\.users \(id, display_name, account_status\)/)
  assert.match(bootstrap, /account_status = 'active'/)
  assert.match(bootstrap, /where r\.key = 'system_admin'/)
  assert.match(bootstrap, /on conflict \(user_id, role_id\) do nothing/)
  assert.match(bootstrap, /private\.append_audit\(/)
})

test('bootstrap SQL contains no fixed personal data (email, UUID, or name literal)', () => {
  assert.doesNotMatch(bootstrap, /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/)
  assert.doesNotMatch(bootstrap, /'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/)
  assert.doesNotMatch(bootstrap, /v_target\s*:?=\s*'(?![A-Z])(?![0-9a-f]{8}-)/)
})
