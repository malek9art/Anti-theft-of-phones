import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { enumValue } from '../_shared/validation.ts'

const actions = ['login', 'logout', 'mfa_event'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const action = enumValue(body.action, actions, 'SECURITY_ACTION')
  await rpc(serviceClient(), 'api_ingest_auth_event', {
    p_actor_id: context.user.id,
    p_action: action,
    p_result: 'success',
    p_metadata: { source: 'web_app' },
    p_ip_address: context.ipAddress,
    p_device_information: context.deviceInformation,
  })
  return success(request, { recorded: true })
}, { scope: 'security-event', maxRequests: 20, windowSeconds: 600 }))
