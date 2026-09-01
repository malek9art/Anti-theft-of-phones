const configuredOrigins = () =>
  (Deno.env.get('ALLOWED_ORIGINS') ?? '')
    .split(',')
    .map((origin) => origin.trim().replace(/\/$/, ''))
    .filter(Boolean)

export function corsHeaders(request: Request): HeadersInit {
  const requestOrigin = (request.headers.get('origin') ?? '').replace(/\/$/, '')
  const allowedOrigins = configuredOrigins()
  const allowed = requestOrigin && allowedOrigins.includes(requestOrigin)

  return {
    // Deliberately never uses '*': authenticated functions must only answer known web origins.
    'Access-Control-Allow-Origin': allowed ? requestOrigin : 'null',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-request-id',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '600',
    'Vary': 'Origin',
    'X-Content-Type-Options': 'nosniff',
    'Cache-Control': 'no-store',
  }
}

export function isAllowedOrigin(request: Request): boolean {
  const origin = request.headers.get('origin')
  // Server-to-server requests (such as Auth hooks) do not send Origin and are separately authenticated.
  if (!origin) return true
  return configuredOrigins().includes(origin.replace(/\/$/, ''))
}

export function preflight(request: Request): Response | null {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(request) })
  }
  return null
}
