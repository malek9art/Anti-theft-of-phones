import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { isValidImei, normalizeImei, optionalText, optionalUuid, text, uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const imei1 = normalizeImei(body.imei1)
  const imei2 = body.imei2 ? normalizeImei(body.imei2) : null
  if (!isValidImei(imei1) || (imei2 !== null && !isValidImei(imei2)) || imei1 === imei2) throw new Error('INVALID_IMEI')

  const data = await rpc(context.client, 'api_create_device', {
    p_shop_id: uuid(body.shop_id, 'SHOP_ID'),
    p_brand: text(body.brand, 'BRAND', 1, 100),
    p_model: text(body.model, 'MODEL', 1, 160),
    p_color: optionalText(body.color, 'COLOR', 100),
    p_serial_number: optionalText(body.serial_number, 'SERIAL_NUMBER', 160),
    p_imei1: imei1,
    p_imei2: imei2,
  })
  return success(request, data, 201)
}, { scope: 'create-device', maxRequests: 20, windowSeconds: 600 }))
