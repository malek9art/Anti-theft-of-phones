import { existsSync, readFileSync } from 'node:fs'

const manifestPath = 'public/manifest.webmanifest'
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
const required = ['name', 'short_name', 'display', 'start_url', 'scope', 'theme_color', 'icons']
for (const key of required) {
  if (!manifest[key]) throw new Error(`PWA manifest is missing ${key}`)
}
if (manifest.display !== 'standalone') throw new Error('PWA manifest must use standalone display')
if (!Array.isArray(manifest.icons) || !manifest.icons.some((icon) => icon.sizes === '192x192') || !manifest.icons.some((icon) => icon.sizes === '512x512')) {
  throw new Error('PWA manifest requires 192x192 and 512x512 icons')
}
for (const icon of manifest.icons) {
  if (!existsSync(`public/${icon.src}`)) throw new Error(`PWA icon does not exist: ${icon.src}`)
}
console.log('PWA manifest and icons are valid.')
