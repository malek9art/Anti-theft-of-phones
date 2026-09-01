import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { signedUpload } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { enumValue, optionalUuid, text, uuid } from '../_shared/validation.ts'

const kinds = ['device', 'before_repair', 'after_repair', 'sale', 'other'] as const
const imageMimeTypes = ['image/jpeg', 'image/png', 'image/webp'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const size = body.size_bytes
  if (typeof size !== 'number' || !Number.isInteger(size) || size < 1 || size > 10_485_760) throw new Error('INVALID_FILE_SIZE')
  const intent = await rpc<{ media_id: string; bucket: string; storage_path: string }>(context.client, 'api_create_device_media_upload_intent', {
    p_device_id: uuid(body.device_id, 'DEVICE_ID'),
    p_repair_record_id: optionalUuid(body.repair_record_id, 'REPAIR_RECORD_ID'),
    p_kind: enumValue(body.kind, kinds, 'MEDIA_KIND'),
    p_original_name: text(body.original_name, 'ORIGINAL_NAME', 1, 255),
    p_content_type: enumValue(body.content_type, imageMimeTypes, 'CONTENT_TYPE'),
    p_size_bytes: size,
  })
  const upload = await signedUpload(serviceClient(), intent.bucket, intent.storage_path)
  return success(request, { media_id: intent.media_id, ...upload }, 201)
}, { scope: 'create-device-media-upload', maxRequests: 20, windowSeconds: 600 }))
