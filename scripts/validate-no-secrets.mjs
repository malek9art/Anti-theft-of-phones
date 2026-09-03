import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

const ignored = new Set(['.git', 'node_modules', 'dist'])
const files = []
function walk(directory) {
  for (const item of readdirSync(directory)) {
    if (ignored.has(item)) continue
    const file = join(directory, item)
    if (statSync(file).isDirectory()) walk(file)
    else files.push(file)
  }
}
walk('.')

// Server secrets only. The publishable anon key is a JWT too, but its payload role is
// "anon"; it is intentionally public and shipped to the browser, so it must not fail here.
const serviceRoleAssignment = /SUPABASE_SERVICE_ROLE_KEY\s*=\s*(?!(?:server-only|replace-with|\.\.\.)\b)[A-Za-z0-9_-]{20,}/
const jwtShape = /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/g

function isServiceRoleJwt(token) {
  try {
    const payload = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    const decoded = JSON.parse(Buffer.from(payload, 'base64').toString('utf8'))
    return decoded.role === 'service_role'
  } catch {
    return false
  }
}

function containsServerSecret(content) {
  if (serviceRoleAssignment.test(content)) return true
  for (const match of content.matchAll(jwtShape)) {
    if (isServiceRoleJwt(match[0])) return true
  }
  return false
}

const violations = files.filter((file) => !file.endsWith('.example') && containsServerSecret(readFileSync(file, 'utf8')))
if (violations.length) {
  console.error(`Potential server secret(s) found in: ${violations.join(', ')}`)
  process.exit(1)
}
console.log('No committed server secret (service-role key or service-role JWT) found.')
