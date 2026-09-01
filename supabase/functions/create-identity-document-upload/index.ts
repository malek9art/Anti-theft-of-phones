import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { signedUpload } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { enumValue, text, uuid } from '../_shared/validation.ts'

const mimeTypes = ['image/jpeg', 'image/png', 'application/pdf'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  if (typeof body.size_bytes !== 'number' || !Number.isInteger(body.size_bytes) || body.size_bytes < 1 || body.size_bytes > 10_485_760) throw new Error('INVALID_FILE_SIZE')
  const intent = await rpc<{ identity_document_id: string; bucket: string; storage_path: string }>(context.client, 'api_create_identity_document_upload_intent', {
    p_customer_id: uuid(body.customer_id, 'CUSTOMER_ID'),
    p_original_name: text(body.original_name, 'ORIGINAL_NAME', 1, 255),
    p_content_type: enumValue(body.content_type, mimeTypes, 'CONTENT_TYPE'),
    p_size_bytes: body.size_bytes,
  })
  const upload = await signedUpload(serviceClient(), intent.bucket, intent.storage_path)
  return success(request, { identity_document_id: intent.identity_document_id, ...upload }, 201)
}, { scope: 'create-identity-document-upload', maxRequests: 10, windowSeconds: 600 }))
