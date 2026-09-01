import { encryptCustomer } from '../_shared/customer.ts'
import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { isValidImei, normalizeImei, numberInRange, optionalText, uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const imei = normalizeImei(body.imei)
  if (!isValidImei(imei)) throw new Error('INVALID_IMEI')
  const customer = await encryptCustomer(body.customer)

  const data = await rpc(context.client, 'api_register_sale_with_customer', {
    p_shop_id: uuid(body.shop_id, 'SHOP_ID'),
    p_imei: imei,
    p_unit_price: numberInRange(body.unit_price, 'UNIT_PRICE', 0, 999999999999.99),
    p_notes: optionalText(body.notes, 'NOTES', 2000),
    ...customer,
  })
  return success(request, data, 201)
}, { scope: 'register-sale', maxRequests: 15, windowSeconds: 600 }))
