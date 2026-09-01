import { isAllowedOrigin, preflight } from '../_shared/cors.ts'
import { databaseError, json, publicError, readJson } from '../_shared/http.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false
  let difference = 0
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index)
  return difference === 0
}

const allowedActions = new Set(['login', 'logout', 'failed_login', 'mfa_event', 'password_reset', 'suspicious_login'])
const allowedResults = new Set(['success', 'failure', 'denied'])

Deno.serve(async (request) => {
  const options = preflight(request)
  if (options) return options
  if (request.method !== 'POST') return publicError(request, 'INVALID_INPUT', 'طريقة الطلب غير مدعومة.', 405)
  if (!isAllowedOrigin(request)) return publicError(request, 'FORBIDDEN', 'مصدر الطلب غير مسموح به.', 403)

  try {
    const expectedSecret = Deno.env.get('AUTH_EVENT_INGEST_SECRET')
    const suppliedSecret = request.headers.get('x-auth-event-secret') ?? ''
    if (!expectedSecret || !constantTimeEqual(suppliedSecret, expectedSecret)) {
      return publicError(request, 'FORBIDDEN', 'الطلب غير مصرح به.', 403)
    }
    const body = await readJson(request)
    if (typeof body.actor_id !== 'string' || !/^[0-9a-f-]{36}$/i.test(body.actor_id)
      || typeof body.action !== 'string' || !allowedActions.has(body.action)
      || typeof body.result !== 'string' || !allowedResults.has(body.result)) {
      return publicError(request, 'INVALID_INPUT', 'بيانات حدث المصادقة غير صالحة.', 422)
    }
    const forwarded = request.headers.get('x-forwarded-for')
    await rpc(serviceClient(), 'api_ingest_auth_event', {
      p_actor_id: body.actor_id,
      p_action: body.action,
      p_result: body.result,
      p_metadata: typeof body.metadata === 'object' && body.metadata && !Array.isArray(body.metadata) ? body.metadata : {},
      p_ip_address: forwarded ? forwarded.split(',')[0].trim() : null,
      p_device_information: (request.headers.get('user-agent') ?? '').slice(0, 500),
    })
    return json(request, { data: { accepted: true } }, 202)
  } catch (error) {
    return databaseError(request, error)
  }
})
