import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { optionalText, text } from '../_shared/validation.ts'

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const email = text(body.email, 'EMAIL', 3, 254).toLowerCase()
  if (!emailPattern.test(email)) throw new Error('INVALID_EMAIL')
  const displayName = optionalText(body.display_name, 'DISPLAY_NAME', 160) ?? 'مستخدم جديد'

  // Authorize before the service-role Auth Admin API is touched.
  await rpc(context.client, 'api_authorize_user_invite')
  const { data, error } = await serviceClient().auth.admin.inviteUserByEmail(email, {
    data: { display_name: displayName },
    redirectTo: Deno.env.get('APP_REDIRECT_URL'),
  })
  if (error || !data.user) throw new Error(error?.message ?? 'INVITE_FAILED')
  await rpc(context.client, 'api_record_user_invite', { p_user_id: data.user.id })
  return success(request, { user_id: data.user.id, invited: true }, 201)
}, { scope: 'invite-user', maxRequests: 10, windowSeconds: 3600 }))
