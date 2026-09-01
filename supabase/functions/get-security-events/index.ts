import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const limit = typeof body.limit === 'number' ? body.limit : 50
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) throw new Error('INVALID_LIMIT')
  const data = await rpc(context.client, 'api_get_security_events', {
    p_limit: limit,
    p_unresolved_only: body.unresolved_only !== false,
  })
  return success(request, data)
}, { scope: 'get-security-events', maxRequests: 30, windowSeconds: 60 }))
