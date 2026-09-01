import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { enumValue, optionalText, uuid } from '../_shared/validation.ts'

const reportStatuses = ['draft', 'submitted', 'under_review', 'verified', 'active', 'assigned', 'recovered', 'closed', 'rejected', 'cancelled'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_update_report_status', {
    p_report_id: uuid(body.report_id, 'REPORT_ID'),
    p_to_status: enumValue(body.status, reportStatuses, 'REPORT_STATUS'),
    p_note: optionalText(body.note, 'NOTE', 3000),
  })
  return success(request, data)
}, { scope: 'update-report-status', maxRequests: 20, windowSeconds: 600 }))
