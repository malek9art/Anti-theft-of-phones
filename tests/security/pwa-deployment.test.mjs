import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const root = process.cwd()
const read = (file) => readFileSync(join(root, file), 'utf8')

test('GitHub Pages workflow template uses only browser-safe build configuration', () => {
  // This template is committed as documentation because GitHub workflow files may need manual upload.
  const manual = read('docs-source/GITHUB_WORKFLOWS_MANUAL.md')
  const workflow = manual.slice(manual.indexOf('## 2)'), manual.indexOf('## 3)'))
  assert.match(workflow, /actions\/deploy-pages@/)
  assert.match(workflow, /VITE_SUPABASE_URL: \$\{\{ secrets\.VITE_SUPABASE_URL \}\}/)
  assert.match(workflow, /VITE_SUPABASE_ANON_KEY: \$\{\{ secrets\.VITE_SUPABASE_ANON_KEY \}\}/)
  assert.match(workflow, /VITE_ROUTER_MODE: hash/)
  assert.match(workflow, /VITE_BASE_PATH:/)
  assert.doesNotMatch(workflow, /SUPABASE_SERVICE_ROLE_KEY|SENSITIVE_DATA_ENCRYPTION_KEY|SENSITIVE_DATA_LOOKUP_KEY/)
})

test('manifest, base-aware route mode, and worker make the static app installable', () => {
  const manifest = read('public/manifest.webmanifest')
  const main = read('src/main.tsx')
  const worker = read('public/sw.js')
  assert.match(manifest, /"display": "standalone"/)
  assert.match(manifest, /"start_url": "\.\/"/)
  assert.match(manifest, /"purpose": "maskable"/)
  assert.match(manifest, /"src": "icons\/icon-192\.png"/)
  assert.match(main, /VITE_ROUTER_MODE === 'hash'/)
  assert.match(main, /navigator\.serviceWorker\.register/)
  assert.match(main, /import\.meta\.env\.BASE_URL/)
  assert.match(worker, /request\.method !== 'GET'/)
  assert.match(worker, /url\.origin !== self\.location\.origin/)
  assert.match(worker, /url\.pathname\.includes\('\/assets\/'\)/)
})
