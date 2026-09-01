import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  await rpc(context.client, 'api_resolve_security_event', { p_event_id: uuid(body.event_id, 'EVENT_ID') })
  return success(request, { resolved: true })
}, { scope: 'resolve-security-event', maxRequests: 20, windowSeconds: 600 }))
