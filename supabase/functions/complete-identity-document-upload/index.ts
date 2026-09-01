import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { verifyAndHashPrivateObject } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

type PendingIdentityDocument = { bucket: string; storage_path: string; size_bytes: number; content_type: string }

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const id = uuid(body.identity_document_id, 'IDENTITY_DOCUMENT_ID')
  const pending = await rpc<PendingIdentityDocument>(context.client, 'api_get_pending_identity_document_upload', { p_identity_document_id: id })
  const hash = await verifyAndHashPrivateObject(serviceClient(), pending.bucket, pending.storage_path, pending.size_bytes, pending.content_type)
  const data = await rpc(context.client, 'api_complete_identity_document_upload', { p_identity_document_id: id, p_sha256: hash })
  return success(request, data)
}, { scope: 'complete-identity-document-upload', maxRequests: 10, windowSeconds: 600 }))
