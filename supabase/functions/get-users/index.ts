import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const limit = typeof body.limit === 'number' ? body.limit : 50
  const offset = typeof body.offset === 'number' ? body.offset : 0
  if (!Number.isInteger(limit) || limit < 1 || limit > 100 || !Number.isInteger(offset) || offset < 0) throw new Error('INVALID_PAGINATION')
  const data = await rpc(context.client, 'api_get_users', { p_limit: limit, p_offset: offset })
  return success(request, data)
}, { scope: 'get-users', maxRequests: 30, windowSeconds: 60 }))
