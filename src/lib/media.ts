import { invoke } from './api'
import { requireSupabase } from './supabase'

const imageTypes = new Set(['image/jpeg', 'image/png', 'image/webp'])

async function uploadDeviceMedia(file: File, deviceId: string, repairId: string | null, kind: 'device' | 'before_repair' | 'after_repair'): Promise<void> {
  if (!imageTypes.has(file.type) || file.size < 1 || file.size > 10_485_760) {
    throw new Error('INVALID_IMAGE_FILE')
  }
  const intent = await invoke<{ media_id: string; bucket: string; storage_path: string; token: string }>('create-device-media-upload', {
    device_id: deviceId,
    repair_record_id: repairId,
    kind,
    original_name: file.name,
    content_type: file.type,
    size_bytes: file.size,
  })
  const { error: uploadError } = await requireSupabase().storage
    .from(intent.bucket)
    .uploadToSignedUrl(intent.storage_path, intent.token, file, { contentType: file.type })
  if (uploadError) throw uploadError
  await invoke('complete-device-media-upload', { media_id: intent.media_id })
}

export function uploadRepairImage(file: File, deviceId: string, repairId: string, kind: 'before_repair' | 'after_repair'): Promise<void> {
  return uploadDeviceMedia(file, deviceId, repairId, kind)
}

export function uploadDeviceImage(file: File, deviceId: string): Promise<void> {
  return uploadDeviceMedia(file, deviceId, null, 'device')
}

export async function uploadIdentityDocument(file: File, customerId: string): Promise<void> {
  const allowed = new Set(['image/jpeg', 'image/png', 'application/pdf'])
  if (!allowed.has(file.type) || file.size < 1 || file.size > 10_485_760) throw new Error('INVALID_IDENTITY_DOCUMENT')
  const intent = await invoke<{ identity_document_id: string; bucket: string; storage_path: string; token: string }>('create-identity-document-upload', {
    customer_id: customerId,
    original_name: file.name,
    content_type: file.type,
    size_bytes: file.size,
  })
  const { error: uploadError } = await requireSupabase().storage
    .from(intent.bucket)
    .uploadToSignedUrl(intent.storage_path, intent.token, file, { contentType: file.type })
  if (uploadError) throw uploadError
  await invoke('complete-identity-document-upload', { identity_document_id: intent.identity_document_id })
}

export async function uploadEvidence(file: File, reportId: string, evidenceType: string, description: string, accessLevel: string): Promise<void> {
  const allowed = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
  if (!allowed.has(file.type) || file.size < 1 || file.size > 15_728_640) throw new Error('INVALID_EVIDENCE_FILE')
  const intent = await invoke<{ evidence_id: string; bucket: string; storage_path: string; token: string }>('create-evidence-upload', {
    report_id: reportId,
    evidence_type: evidenceType,
    original_name: file.name,
    content_type: file.type,
    size_bytes: file.size,
    description,
    access_level: accessLevel,
  })
  const { error: uploadError } = await requireSupabase().storage
    .from(intent.bucket)
    .uploadToSignedUrl(intent.storage_path, intent.token, file, { contentType: file.type })
  if (uploadError) throw uploadError
  await invoke('complete-evidence-upload', { evidence_id: intent.evidence_id })
}
