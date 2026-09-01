import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  await rpc(context.client, 'api_mark_notification_read', { p_notification_id: uuid(body.notification_id, 'NOTIFICATION_ID') })
  return success(request, { marked: true })
}, { scope: 'mark-notification-read', maxRequests: 60, windowSeconds: 60 }))
