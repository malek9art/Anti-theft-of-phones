import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { rpc } from '../_shared/supabase.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const data = await rpc(context.client, 'api_bootstrap')
  return success(request, data)
}, { scope: 'bootstrap', maxRequests: 30, windowSeconds: 60 }))
