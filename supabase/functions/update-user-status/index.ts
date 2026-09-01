import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { enumValue, optionalText, uuid } from '../_shared/validation.ts'

const statuses = ['pending', 'active', 'suspended', 'inactive'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_update_user_status', {
    p_user_id: uuid(body.user_id, 'USER_ID'),
    p_status: enumValue(body.status, statuses, 'ACCOUNT_STATUS'),
    p_reason: optionalText(body.reason, 'REASON', 1000),
    p_mfa_required: typeof body.mfa_required === 'boolean' ? body.mfa_required : null,
  })
  return success(request, data)
}, { scope: 'update-user-status', maxRequests: 15, windowSeconds: 600 }))
