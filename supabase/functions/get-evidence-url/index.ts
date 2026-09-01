import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { signedViewUrl } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { text, uuid } from '../_shared/validation.ts'

type EvidenceAccess = { bucket: string; storage_path: string; ttl_seconds: number }

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const access = await rpc<EvidenceAccess>(context.client, 'api_authorize_evidence_view', {
    p_evidence_id: uuid(body.evidence_id, 'EVIDENCE_ID'),
    p_purpose: text(body.purpose, 'PURPOSE', 5, 500),
  })
  const signedUrl = await signedViewUrl(serviceClient(), access.bucket, access.storage_path, access.ttl_seconds)
  return success(request, { signed_url: signedUrl, expires_in_seconds: access.ttl_seconds })
}, { scope: 'get-evidence-url', maxRequests: 30, windowSeconds: 600 }))
