import type { SupabaseClient } from 'npm:@supabase/supabase-js@2.112.4'
import { sha256 } from './crypto.ts'

export type UploadIntent = {
  evidence_id?: string
  media_id?: string
  bucket: string
  storage_path: string
}

export async function signedUpload(client: SupabaseClient, bucket: string, storagePath: string) {
  const { data, error } = await client.storage.from(bucket).createSignedUploadUrl(storagePath)
  if (error || !data?.token) throw new Error(error?.message ?? 'SIGNED_UPLOAD_URL_FAILED')
  return { token: data.token, signed_url: data.signedUrl, bucket, storage_path: storagePath }
}

export async function signedViewUrl(client: SupabaseClient, bucket: string, storagePath: string, seconds: number) {
  const { data, error } = await client.storage.from(bucket).createSignedUrl(storagePath, seconds)
  if (error || !data?.signedUrl) throw new Error(error?.message ?? 'SIGNED_URL_FAILED')
  return data.signedUrl
}

/** Download only a previously authorized, exact key and validate the immutable upload metadata. */
export async function verifyAndHashPrivateObject(
  client: SupabaseClient,
  bucket: string,
  storagePath: string,
  expectedSize: number,
  expectedContentType: string,
): Promise<string> {
  const { data, error } = await client.storage.from(bucket).download(storagePath)
  if (error || !data) throw new Error(error?.message ?? 'PRIVATE_OBJECT_NOT_FOUND')
  if (data.size !== expectedSize || data.type !== expectedContentType) throw new Error('PRIVATE_OBJECT_METADATA_MISMATCH')
  return sha256(await data.arrayBuffer())
}
