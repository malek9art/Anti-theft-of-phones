import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_get_case_assignees', {
    p_report_id: uuid(body.report_id, 'REPORT_ID'),
  })
  return success(request, data)
}, { scope: 'get-case-assignees', maxRequests: 30, windowSeconds: 60 }))
