/*
 * Static-shell PWA worker.
 * It deliberately caches only same-origin application files; API responses, Auth tokens,
 * PII, uploads, signed URLs, and Supabase responses are never written to Cache Storage.
 */
const CACHE_PREFIX = 'himaya-static-'
const CACHE_NAME = `${CACHE_PREFIX}v1`
const scope = self.registration.scope
const shell = [
  new URL('./', scope).toString(),
  new URL('index.html', scope).toString(),
  new URL('manifest.webmanifest', scope).toString(),
  new URL('icons/icon-192.png', scope).toString(),
  new URL('icons/icon-512.png', scope).toString(),
  new URL('icons/maskable-512.png', scope).toString(),
]
const appShell = new URL('index.html', scope).toString()

async function installStaticShell() {
  const cache = await caches.open(CACHE_NAME)
  await cache.addAll(shell)

  // Vite fingerprints JS/CSS names at build time. Read the deployed HTML so the first installed
  // version also has its exact static assets offline, without maintaining a second asset manifest.
  const index = await cache.match(appShell)
  const html = index ? await index.text() : ''
  const assets = [...html.matchAll(/(?:src|href)="([^"]+)"/g)]
    .map((match) => new URL(match[1], scope))
    .filter((url) => url.origin === self.location.origin && url.pathname.includes('/assets/'))
  await Promise.all(assets.map(async (url) => {
    try {
      const response = await fetch(url.toString())
      if (response.ok && response.type !== 'opaque') await cache.put(url.toString(), response)
    } catch {
      // A transient asset fetch must not stop the PWA shell from installing.
    }
  }))

  // Do not let old fingerprinted bundles accumulate across GitHub Pages releases.
  const allowed = new Set([...shell, ...assets.map((url) => url.toString())])
  await Promise.all((await cache.keys()).filter((request) => !allowed.has(request.url)).map((request) => cache.delete(request)))
  await self.skipWaiting()
}

self.addEventListener('install', (event) => {
  event.waitUntil(installStaticShell())
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  )
})

function cacheStaticResponse(request, response) {
  if (!response || !response.ok || response.type === 'opaque') return response
  const copy = response.clone()
  void caches.open(CACHE_NAME).then((cache) => cache.put(request, copy))
  return response
}

self.addEventListener('fetch', (event) => {
  const { request } = event
  if (request.method !== 'GET') return

  const url = new URL(request.url)
  // Never cache third-party requests. Supabase/Auth/Storage are cross-origin in production.
  if (url.origin !== self.location.origin) return

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => cacheStaticResponse(appShell, response))
        .catch(async () => {
          const cached = await caches.match(appShell)
          return cached || caches.match(new URL('./', scope).toString())
        }),
    )
    return
  }

  // Hashed assets are immutable per build; cache only successful same-origin static resources.
  if (url.pathname.includes('/assets/') || url.pathname.endsWith('.webmanifest') || url.pathname.includes('/icons/')) {
    event.respondWith(
      caches.match(request).then((cached) => cached || fetch(request).then((response) => cacheStaticResponse(request, response))),
    )
  }
})
