import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { signedViewUrl } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { text, uuid } from '../_shared/validation.ts'

type IdentityAccess = { bucket: string; storage_path: string; ttl_seconds: number }

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const access = await rpc<IdentityAccess>(context.client, 'api_authorize_identity_document_view', {
    p_identity_document_id: uuid(body.identity_document_id, 'IDENTITY_DOCUMENT_ID'),
    p_purpose: text(body.purpose, 'PURPOSE', 5, 500),
  })
  const signedUrl = await signedViewUrl(serviceClient(), access.bucket, access.storage_path, access.ttl_seconds)
  return success(request, { signed_url: signedUrl, expires_in_seconds: access.ttl_seconds })
}, { scope: 'get-identity-document-url', maxRequests: 20, windowSeconds: 600 }))
