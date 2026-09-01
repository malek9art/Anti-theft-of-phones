import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { optionalText, uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_link_shop_user', {
    p_shop_id: uuid(body.shop_id, 'SHOP_ID'),
    p_user_id: uuid(body.user_id, 'USER_ID'),
    p_title: optionalText(body.title, 'TITLE', 160),
    p_as_technician: body.as_technician === true,
  })
  return success(request, data)
}, { scope: 'link-shop-user', maxRequests: 20, windowSeconds: 600 }))
