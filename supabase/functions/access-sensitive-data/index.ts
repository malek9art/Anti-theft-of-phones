import { decryptSensitive } from '../_shared/crypto.ts'
import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { signedViewUrl } from '../_shared/storage.ts'
import { rpc, serviceClient } from '../_shared/supabase.ts'
import { text, uuid } from '../_shared/validation.ts'

type CipherRow = {
  customer_id: string
  full_name_ciphertext: string | null
  phone_ciphertext: string | null
  national_id_ciphertext: string | null
  address_ciphertext: string | null
}

type IdentityDocument = { storage_path: string }

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const customerId = uuid(body.customer_id, 'CUSTOMER_ID')
  const includeIdentity = body.include_identity === true
  const purpose = text(body.purpose, 'PURPOSE', 5, 500)

  // This RPC both checks scope/permission/MFA and appends the separate sensitive-access log.
  await rpc(context.client, 'api_authorize_sensitive_customer_access', {
    p_customer_id: customerId,
    p_purpose: purpose,
    p_include_identity: includeIdentity,
  })

  // service_role is used only after the user-scoped authorization above; plaintext lives only in this isolate.
  const { data, error } = await serviceClient()
    .from('customer_sensitive_data')
    .select('customer_id,full_name_ciphertext,phone_ciphertext,national_id_ciphertext,address_ciphertext')
    .eq('customer_id', customerId)
    .single<CipherRow>()
  if (error || !data) throw new Error(error?.message ?? 'CUSTOMER_NOT_FOUND')

  const { data: identityDocument } = includeIdentity
    ? await serviceClient().from('customer_identity_documents').select('storage_path').eq('customer_id', customerId).eq('status', 'uploaded').order('created_at', { ascending: false }).limit(1).maybeSingle<IdentityDocument>()
    : { data: null }
  const identityUrl = identityDocument?.storage_path
    ? await signedViewUrl(serviceClient(), 'identity-private', identityDocument.storage_path, 60)
    : null
  return success(request, {
    customer_id: customerId,
    full_name: await decryptSensitive(data.full_name_ciphertext),
    phone: await decryptSensitive(data.phone_ciphertext),
    address: await decryptSensitive(data.address_ciphertext),
    // National ID and document URL are returned only with the additional view_identity permission.
    national_id: includeIdentity ? await decryptSensitive(data.national_id_ciphertext) : null,
    identity_document_url: identityUrl,
    expires_in_seconds: identityUrl ? 60 : null,
  })
}, { scope: 'access-sensitive-data', maxRequests: 15, windowSeconds: 600 }))
