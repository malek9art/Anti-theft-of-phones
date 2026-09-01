import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { optionalText, optionalUuid, uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const officerId = optionalUuid(body.assigned_officer_id, 'ASSIGNED_OFFICER_ID')
  const delegateId = optionalUuid(body.assigned_delegate_id, 'ASSIGNED_DELEGATE_ID')
  if (!officerId && !delegateId) throw new Error('INVALID_ASSIGNEE')
  const data = await rpc(context.client, 'api_assign_report', {
    p_report_id: uuid(body.report_id, 'REPORT_ID'),
    p_assigned_officer_id: officerId,
    p_assigned_delegate_id: delegateId,
    p_note: optionalText(body.note, 'NOTE', 3000),
  })
  return success(request, data)
}, { scope: 'assign-report', maxRequests: 20, windowSeconds: 600 }))
