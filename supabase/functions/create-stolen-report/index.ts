import { encryptCustomer } from '../_shared/customer.ts'
import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { enumValue, isValidImei, normalizeImei, optionalText, optionalUuid, text, uuid } from '../_shared/validation.ts'

const priorities = ['low', 'normal', 'high', 'critical'] as const

function incidentTime(value: unknown): string {
  if (typeof value !== 'string') throw new Error('INVALID_INCIDENT_AT')
  const date = new Date(value)
  if (Number.isNaN(date.getTime()) || date.getTime() > Date.now() + 5 * 60_000) throw new Error('INVALID_INCIDENT_AT')
  return date.toISOString()
}

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const imei = normalizeImei(body.imei)
  const imei2 = body.imei2 ? normalizeImei(body.imei2) : null
  if (!isValidImei(imei) || (imei2 !== null && !isValidImei(imei2)) || imei === imei2) throw new Error('INVALID_IMEI')
  const reporter = await encryptCustomer(body.reporter)

  const data = await rpc(context.client, 'api_create_stolen_report_with_reporter', {
    p_imei: imei,
    p_report_type: text(body.report_type, 'REPORT_TYPE', 2, 100),
    p_incident_at: incidentTime(body.incident_at),
    p_description: text(body.description, 'DESCRIPTION', 5, 6000),
    p_priority: enumValue(body.priority ?? 'normal', priorities, 'PRIORITY'),
    p_agency_id: optionalUuid(body.agency_id, 'AGENCY_ID'),
    p_incident_location_id: optionalUuid(body.incident_location_id, 'LOCATION_ID'),
    p_imei2: imei2,
    p_brand: optionalText(body.brand, 'BRAND', 100),
    p_model: optionalText(body.model, 'MODEL', 160),
    p_color: optionalText(body.color, 'COLOR', 100),
    ...reporter,
  })
  return success(request, data, 201)
}, { scope: 'create-stolen-report', maxRequests: 8, windowSeconds: 3600 }))
