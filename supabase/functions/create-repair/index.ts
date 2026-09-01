import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { isValidImei, normalizeImei, optionalText, optionalUuid, text, uuid } from '../_shared/validation.ts'

function imageReferences(value: unknown): unknown[] {
  if (value === undefined || value === null) return []
  if (!Array.isArray(value) || value.length > 12 || value.some((item) => typeof item !== 'string' || item.length > 120)) {
    throw new Error('INVALID_IMAGE_REFERENCES')
  }
  return value
}

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const imei = normalizeImei(body.imei)
  if (!isValidImei(imei)) throw new Error('INVALID_IMEI')
  const data = await rpc(context.client, 'api_create_repair', {
    p_shop_id: uuid(body.shop_id, 'SHOP_ID'),
    p_imei: imei,
    p_technician_id: optionalUuid(body.technician_id, 'TECHNICIAN_ID'),
    p_operation_type: text(body.operation_type, 'OPERATION_TYPE', 2, 160),
    p_notes: optionalText(body.notes, 'NOTES', 3000),
    p_result: optionalText(body.result, 'RESULT', 500) ?? 'received',
    p_before_images: imageReferences(body.before_images),
    p_after_images: imageReferences(body.after_images),
    p_location_id: optionalUuid(body.location_id, 'LOCATION_ID'),
  })
  return success(request, data, 201)
}, { scope: 'create-repair', maxRequests: 20, windowSeconds: 600 }))
