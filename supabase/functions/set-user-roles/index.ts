import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

const rolePattern = /^[a-z][a-z0-9_]{1,62}$/

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  if (!Array.isArray(body.role_keys) || body.role_keys.length > 8 || body.role_keys.some((role) => typeof role !== 'string' || !rolePattern.test(role))) {
    throw new Error('INVALID_ROLE_KEYS')
  }
  const data = await rpc(context.client, 'api_set_user_roles', {
    p_user_id: uuid(body.user_id, 'USER_ID'),
    p_role_keys: body.role_keys,
  })
  return success(request, data)
}, { scope: 'set-user-roles', maxRequests: 10, windowSeconds: 600 }))
