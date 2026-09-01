import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { optionalText, text } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_submit_shop', {
    p_shop_name: text(body.shop_name, 'SHOP_NAME', 2, 180),
    p_commercial_name: optionalText(body.commercial_name, 'COMMERCIAL_NAME', 180),
    p_business_phone: optionalText(body.business_phone, 'BUSINESS_PHONE', 40),
    p_address_text: optionalText(body.address_text, 'ADDRESS', 1000),
  })
  return success(request, data, 201)
}, { scope: 'submit-shop', maxRequests: 3, windowSeconds: 86_400 }))
