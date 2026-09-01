import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { isValidImei, normalizeImei, optionalText, optionalUuid, text, uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const imei = normalizeImei(body.imei)
  if (!isValidImei(imei)) throw new Error('INVALID_IMEI')
  const data = await rpc(context.client, 'api_create_format_record', {
    p_shop_id: uuid(body.shop_id, 'SHOP_ID'),
    p_imei: imei,
    p_technician_id: optionalUuid(body.technician_id, 'TECHNICIAN_ID'),
    p_format_type: text(body.format_type, 'FORMAT_TYPE', 2, 160),
    p_notes: optionalText(body.notes, 'NOTES', 3000),
    p_repair_record_id: optionalUuid(body.repair_record_id, 'REPAIR_RECORD_ID'),
    p_result: optionalText(body.result, 'RESULT', 500) ?? 'completed',
  })
  return success(request, data, 201)
}, { scope: 'create-format-record', maxRequests: 15, windowSeconds: 600 }))
