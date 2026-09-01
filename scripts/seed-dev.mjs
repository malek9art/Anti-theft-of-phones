/*
 * DEVELOPMENT ONLY. This script intentionally refuses non-local URLs.
 * It creates fake accounts, role mappings, and one development agency through Auth Admin/service role
 * only after proving the target is local; it never places sample data in a production migration.
 */
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_URL
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
const anonKey = process.env.SUPABASE_ANON_KEY
const password = process.env.DEV_TEST_PASSWORD ?? 'Himaya!Dev2026'
if (process.env.ALLOW_DEVELOPMENT_SEED !== 'true' || !url || !serviceRoleKey || !anonKey || !/^https?:\/\/(localhost|127\.0\.0\.1)(:|\/|$)/.test(url)) {
  throw new Error('Refusing to seed. Use a local Supabase URL and ALLOW_DEVELOPMENT_SEED=true.')
}

const users = [
  ['system_admin', 'مدير تجريبي'],
  ['authorized_officer', 'موظف مختص تجريبي'],
  ['investigation_officer', 'باحث جنائي تجريبي'],
  ['delegate', 'مندوب تجريبي'],
  ['shop_manager', 'مدير محل تجريبي'],
  ['technician', 'فني تجريبي'],
  ['auditor', 'مدقق تجريبي'],
]
const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false } })

async function ensureAuthUser(role, displayName) {
  const email = `${role}@himaya.test`
  const { data: all, error: listError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
  if (listError) throw listError
  let user = all.users.find((candidate) => candidate.email === email)
  if (!user) {
    const { data, error } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { display_name: displayName },
    })
    if (error || !data.user) throw error ?? new Error(`Could not create ${role}`)
    user = data.user
  }
  return { role, displayName, email, id: user.id }
}

const seeded = await Promise.all(users.map(([role, displayName]) => ensureAuthUser(role, displayName)))
const ids = seeded.map((entry) => entry.id)
const { error: activateError } = await admin.from('users').update({ account_status: 'active', mfa_required: false }).in('id', ids)
if (activateError) throw activateError

const { data: roleRows, error: roleError } = await admin.from('roles').select('id,key').in('key', users.map(([role]) => role))
if (roleError) throw roleError
const roleMap = new Map(roleRows.map((row) => [row.key, row.id]))
const systemAdmin = seeded.find((entry) => entry.role === 'system_admin')
if (!systemAdmin) throw new Error('Missing system admin')
const { error: bootstrapAdminError } = await admin.from('user_roles').upsert({ user_id: systemAdmin.id, role_id: roleMap.get('system_admin') }, { onConflict: 'user_id,role_id' })
if (bootstrapAdminError) throw bootstrapAdminError

// This remains deliberately local-only. Production role changes must go through the AAL2-protected API.
const roleAssignments = seeded.map((entry) => ({ user_id: entry.id, role_id: roleMap.get(entry.role) }))
const { error: assignmentsError } = await admin.from('user_roles').upsert(roleAssignments, { onConflict: 'user_id,role_id' })
if (assignmentsError) throw assignmentsError

const { data: agency, error: agencyError } = await admin
  .from('agencies')
  .upsert({ code: 'DEV-AGENCY', name: 'جهة تطوير محلية', is_active: true }, { onConflict: 'code' })
  .select('id')
  .single()
if (agencyError || !agency) throw agencyError ?? new Error('Unable to create local development agency')

const officerAndDelegate = seeded.filter((entry) => ['authorized_officer', 'investigation_officer', 'delegate'].includes(entry.role))
const { error: agencyMembersError } = await admin.from('users').update({ agency_id: agency.id }).in('id', officerAndDelegate.map((entry) => entry.id))
if (agencyMembersError) throw agencyMembersError
const delegate = seeded.find((entry) => entry.role === 'delegate')
if (!delegate) throw new Error('Missing development delegate')
const { error: delegateError } = await admin.from('delegates').upsert({
  user_id: delegate.id, agency_id: agency.id, professional_reference: 'DEV-DELEGATE', is_active: true,
}, { onConflict: 'user_id' })
if (delegateError) throw delegateError

console.table(seeded.map(({ role, displayName, email }) => ({ role, displayName, email, password })))
console.log('Development-only fake accounts are ready. Enroll TOTP after signing in with a sensitive role; AAL2 is enforced for sensitive operations even in development.')
