import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { optionalUuid, text, uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_add_report_follow_up', {
    p_report_id: uuid(body.report_id, 'REPORT_ID'),
    p_note: text(body.note, 'NOTE', 5, 3000),
    p_location_id: optionalUuid(body.location_id, 'LOCATION_ID'),
  })
  return success(request, data, 201)
}, { scope: 'add-report-follow-up', maxRequests: 25, windowSeconds: 600 }))
