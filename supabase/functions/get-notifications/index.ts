import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const limit = typeof body.limit === 'number' ? body.limit : 30
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('INVALID_LIMIT')
  const data = await rpc(context.client, 'api_get_notifications', { p_limit: limit })
  return success(request, data)
}, { scope: 'get-notifications', maxRequests: 60, windowSeconds: 60 }))
