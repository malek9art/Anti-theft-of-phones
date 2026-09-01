import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { verifyAndHashPrivateObject } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

type PendingMedia = { bucket: string; storage_path: string; size_bytes: number; content_type: string }

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const mediaId = uuid(body.media_id, 'MEDIA_ID')
  const pending = await rpc<PendingMedia>(context.client, 'api_get_pending_device_media_upload', { p_media_id: mediaId })
  const hash = await verifyAndHashPrivateObject(serviceClient(), pending.bucket, pending.storage_path, pending.size_bytes, pending.content_type)
  const data = await rpc(context.client, 'api_complete_device_media_upload', { p_media_id: mediaId, p_sha256: hash })
  return success(request, data)
}, { scope: 'complete-device-media-upload', maxRequests: 20, windowSeconds: 600 }))
