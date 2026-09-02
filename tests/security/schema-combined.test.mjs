import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { buildCombined } from '../../scripts/build-schema-combined.mjs'

const root = dirname(dirname(dirname(fileURLToPath(import.meta.url))))
const combined = readFileSync(join(root, 'supabase/scripts/schema_combined.sql'), 'utf8')

test('schema_combined.sql stays in sync with supabase/migrations (browser-only setup)', () => {
  assert.equal(combined, buildCombined(), 'run `node scripts/build-schema-combined.mjs` after editing migrations')
})

test('schema_combined.sql is a single atomic transaction', () => {
  assert.match(combined, /\nbegin;\n/)
  assert.match(combined, /\ncommit;\n/)
  assert.ok(combined.indexOf('\nbegin;\n') < combined.indexOf('\ncommit;\n'))
})

test('schema_combined.sql includes the foundation tables and the hardening migration', () => {
  assert.match(combined, /create table public\.users \(/)
  assert.match(combined, /create table public\.roles \(/)
  assert.match(combined, /create table public\.user_roles \(/)
  assert.match(combined, /revoke create on schema public from public, anon, authenticated/)
  assert.match(combined, /20260901001600_schema_function_hardening\.sql/)
})
