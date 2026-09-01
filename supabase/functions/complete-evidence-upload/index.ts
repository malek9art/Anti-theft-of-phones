import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { verifyAndHashPrivateObject } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { uuid } from '../_shared/validation.ts'

type PendingEvidence = { bucket: string; storage_path: string; size_bytes: number; content_type: string }

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const evidenceId = uuid(body.evidence_id, 'EVIDENCE_ID')
  const pending = await rpc<PendingEvidence>(context.client, 'api_get_pending_evidence_upload', { p_evidence_id: evidenceId })
  const hash = await verifyAndHashPrivateObject(serviceClient(), pending.bucket, pending.storage_path, pending.size_bytes, pending.content_type)
  const data = await rpc(context.client, 'api_complete_evidence_upload', { p_evidence_id: evidenceId, p_sha256: hash })
  return success(request, data)
}, { scope: 'complete-evidence-upload', maxRequests: 15, windowSeconds: 600 }))
