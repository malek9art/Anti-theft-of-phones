import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { isValidImei, normalizeImei } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const imei = normalizeImei(body.imei)
  if (!isValidImei(imei)) throw new Error('INVALID_IMEI')
  const data = await rpc(context.client, 'api_check_imei', { p_imei: imei })
  return success(request, data)
}, { scope: 'check-imei', maxRequests: 30, windowSeconds: 600 }))
