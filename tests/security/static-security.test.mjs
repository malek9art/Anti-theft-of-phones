import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

const root = process.cwd()
const migrations = readdirSync(join(root, 'supabase/migrations')).sort().map((file) => readFileSync(join(root, 'supabase/migrations', file), 'utf8')).join('\n')
function files(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name)
    return entry.isDirectory() ? files(path) : [path]
  })
}

test('critical tables are RLS-enabled and have no browser write policy', () => {
  const critical = ['devices', 'device_imeis', 'sales', 'repair_records', 'format_records', 'stolen_reports', 'evidence', 'audit_logs', 'customer_sensitive_data']
  for (const table of critical) assert.match(migrations, new RegExp(`alter table public\\.${table} enable row level security`, 'i'), table)
  assert.doesNotMatch(migrations, /create policy\s+.*\s+on public\.(?:sales|repair_records|format_records|stolen_reports|audit_logs)\s+for\s+(?:insert|update|delete|all)/i)
})

test('sensitive customer fields are ciphertext-only and use a distinct access log', () => {
  assert.match(migrations, /full_name_ciphertext text/i)
  assert.match(migrations, /phone_ciphertext text/i)
  assert.match(migrations, /create table public\.sensitive_data_access_logs/i)
  assert.match(migrations, /Versioned AES-GCM envelope shape/i)
  assert.doesNotMatch(migrations, /(?:^|\n)\s+full_name\s+text\s*(?:,|\n)/i)
  assert.doesNotMatch(migrations, /(?:^|\n)\s+phone\s+text\s*(?:,|\n)/i)
})

test('sensitive server operations require AAL2 and case assignment is agency-scoped', () => {
  assert.match(migrations, /if p_mfa_for_sensitive and not public\.has_mfa_assurance\(\) then/i)
  assert.match(migrations, /raise exception 'MFA_REQUIRED'/i)
  assert.match(migrations, /and sr\.agency_id = u\.agency_id/i)
  assert.match(migrations, /api_get_case_assignees\(p_report_id uuid\)/i)
  assert.match(migrations, /d\.agency_id = v_agency_id/i)
})

test('audit ledger is append-only and tamper-evident', () => {
  assert.match(migrations, /entry_hash text not null unique/i)
  assert.match(migrations, /pg_advisory_xact_lock\(hashtext\('himaya_audit_chain_v1'\)\)/i)
  assert.match(migrations, /create trigger immutable_audit_logs/i)
  assert.match(migrations, /before update or delete on public\.audit_logs/i)
})

test('all browser storage buckets are private and direct browser access is denied', () => {
  assert.match(migrations, /\('evidence-private', 'evidence-private', false/i)
  assert.match(migrations, /\('device-media-private', 'device-media-private', false/i)
  assert.match(migrations, /\('identity-private', 'identity-private', false/i)
  assert.match(migrations, /deny browser access to evidence-private/i)
  assert.match(migrations, /deny browser access to identity-private/i)
  const storageFunctions = files(join(root, 'supabase/functions')).map((file) => readFileSync(file, 'utf8')).join('\n')
  assert.match(storageFunctions, /createSignedUrl|createSignedUploadUrl/)
})

test('the service role key is never imported by the browser application', () => {
  const browserSource = files(join(root, 'src')).map((file) => readFileSync(file, 'utf8')).join('\n')
  assert.doesNotMatch(browserSource, /SERVICE_ROLE/i)
  assert.doesNotMatch(browserSource, /SENSITIVE_DATA_ENCRYPTION_KEY/i)
})

test('all Edge Functions use a user context before trusted operations except the HMAC-protected Auth hook', () => {
  const functionDirectories = readdirSync(join(root, 'supabase/functions'), { withFileTypes: true }).filter((entry) => entry.isDirectory() && entry.name !== '_shared')
  for (const directory of functionDirectories) {
    const source = readFileSync(join(root, 'supabase/functions', directory.name, 'index.ts'), 'utf8')
    if (directory.name === 'ingest-auth-event') {
      assert.match(source, /AUTH_EVENT_INGEST_SECRET/)
      assert.match(source, /constantTimeEqual/)
    } else {
      assert.match(source, /withAuthenticatedRequest/, directory.name)
    }
  }
})
