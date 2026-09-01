import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_approve_shop', { p_shop_id: uuid(body.shop_id, 'SHOP_ID') })
  return success(request, data)
}, { scope: 'approve-shop', maxRequests: 20, windowSeconds: 600 }))
