import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { text, uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_suspend_shop', {
    p_shop_id: uuid(body.shop_id, 'SHOP_ID'),
    p_reason: text(body.reason, 'REASON', 5, 1000),
  })
  return success(request, data)
}, { scope: 'suspend-shop', maxRequests: 10, windowSeconds: 600 }))
