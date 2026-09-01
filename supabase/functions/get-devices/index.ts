import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { enumValue } from '../_shared/validation.ts'

const statuses = ['registered', 'available', 'sold', 'in_repair', 'formatted', 'flagged', 'stolen', 'recovered', 'blocked', 'archived'] as const
function optionalDate(value: unknown): string | null {
  if (value === null || value === undefined || value === '') return null
  if (typeof value !== 'string' || Number.isNaN(new Date(value).getTime())) throw new Error('INVALID_DATE')
  return new Date(value).toISOString()
}

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const limit = typeof body.limit === 'number' ? body.limit : 40
  const offset = typeof body.offset === 'number' ? body.offset : 0
  if (!Number.isInteger(limit) || limit < 1 || limit > 100 || !Number.isInteger(offset) || offset < 0) throw new Error('INVALID_PAGINATION')
  const data = await rpc(context.client, 'api_get_devices', {
    p_status: body.status ? enumValue(body.status, statuses, 'STATUS') : null,
    p_from: optionalDate(body.from),
    p_to: optionalDate(body.to),
    p_limit: limit,
    p_offset: offset,
  })
  return success(request, data)
}, { scope: 'get-devices', maxRequests: 60, windowSeconds: 60 }))
