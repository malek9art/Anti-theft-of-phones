import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const service = serviceClient()
  const { error } = await service.auth.admin.signOut(context.user.id, 'others')
  if (error) throw new Error(error.message)
  await rpc(service, 'api_ingest_auth_event', {
    p_actor_id: context.user.id,
    p_action: 'logout',
    p_result: 'success',
    p_metadata: { source: 'security_center', scope: 'other_sessions_revoked' },
    p_ip_address: context.ipAddress,
    p_device_information: context.deviceInformation,
  })
  return success(request, { revoked: true })
}, { scope: 'revoke-other-sessions', maxRequests: 5, windowSeconds: 600 }))
