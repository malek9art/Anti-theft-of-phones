import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const rawLimit = typeof body.limit === 'number' ? body.limit : 40
  if (!Number.isInteger(rawLimit) || rawLimit < 1 || rawLimit > 100) throw new Error('INVALID_LIMIT')
  const before = body.before
  if (before !== undefined && before !== null && (typeof before !== 'string' || Number.isNaN(new Date(before).getTime()))) {
    throw new Error('INVALID_CURSOR')
  }
  const data = await rpc(context.client, 'api_get_device_timeline', {
    p_device_id: uuid(body.device_id, 'DEVICE_ID'),
    p_limit: rawLimit,
    p_before: before ?? null,
  })
  return success(request, data)
}, { scope: 'get-device-timeline', maxRequests: 60, windowSeconds: 60 }))
