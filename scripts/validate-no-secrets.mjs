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
const suspicious = /(SUPABASE_SERVICE_ROLE_KEY\s*=\s*(?!(?:server-only|replace-with|\.\.\.)\b)[A-Za-z0-9_-]{20,}|eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,})/
const violations = files.filter((file) => !file.endsWith('.example') && suspicious.test(readFileSync(file, 'utf8')))
if (violations.length) {
  console.error(`Potential secret(s) found in: ${violations.join(', ')}`)
  process.exit(1)
}
console.log('No committed service-role key or JWT-shaped secret found.')
