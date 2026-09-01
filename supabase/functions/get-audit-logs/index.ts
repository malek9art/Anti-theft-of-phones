import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const limit = typeof body.limit === 'number' ? body.limit : 50
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) throw new Error('INVALID_LIMIT')
  const before = body.before
  if (before !== undefined && before !== null && (typeof before !== 'string' || Number.isNaN(new Date(before).getTime()))) throw new Error('INVALID_CURSOR')
  const data = await rpc(context.client, 'api_get_audit_logs', { p_limit: limit, p_before: before ?? null })
  return success(request, data)
}, { scope: 'get-audit-logs', maxRequests: 30, windowSeconds: 60 }))
