import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { signedUpload } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { enumValue, optionalText, text, uuid } from '../_shared/validation.ts'

const evidenceLevels = ['restricted', 'investigation', 'sealed'] as const
const mimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const size = body.size_bytes
  if (typeof size !== 'number' || !Number.isInteger(size) || size < 1 || size > 15_728_640) throw new Error('INVALID_FILE_SIZE')
  const contentType = enumValue(body.content_type, mimeTypes, 'CONTENT_TYPE')
  const intent = await rpc<{ evidence_id: string; bucket: string; storage_path: string }>(context.client, 'api_create_evidence_upload_intent', {
    p_report_id: uuid(body.report_id, 'REPORT_ID'),
    p_evidence_type: text(body.evidence_type, 'EVIDENCE_TYPE', 2, 100),
    p_original_name: text(body.original_name, 'ORIGINAL_NAME', 1, 255),
    p_content_type: contentType,
    p_size_bytes: size,
    p_description: optionalText(body.description, 'DESCRIPTION', 3000),
    p_access_level: enumValue(body.access_level ?? 'restricted', evidenceLevels, 'ACCESS_LEVEL'),
  })
  const upload = await signedUpload(serviceClient(), intent.bucket, intent.storage_path)
  return success(request, { evidence_id: intent.evidence_id, ...upload }, 201)
}, { scope: 'create-evidence-upload', maxRequests: 15, windowSeconds: 600 }))
