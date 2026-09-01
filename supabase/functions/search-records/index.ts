import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { enumValue, text } from '../_shared/validation.ts'

const modes = ['imei', 'report', 'operation', 'shop'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const limit = typeof body.limit === 'number' ? body.limit : 25
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('INVALID_LIMIT')
  const data = await rpc(context.client, 'api_search_records', {
    p_mode: enumValue(body.mode, modes, 'SEARCH_MODE'),
    p_query: text(body.query, 'QUERY', 2, 160),
    p_limit: limit,
  })
  return success(request, data)
}, { scope: 'search-records', maxRequests: 30, windowSeconds: 600 }))
