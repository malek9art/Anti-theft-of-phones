import { encryptSensitive, sensitiveLookupHash } from './crypto.ts'
import { optionalText, text } from './validation.ts'

export type EncryptedCustomer = {
  p_full_name_ciphertext: string | null
  p_phone_ciphertext: string | null
  p_national_id_ciphertext: string | null
  p_address_ciphertext: string | null
  p_full_name_lookup_hash: string | null
  p_phone_lookup_hash: string | null
  p_national_id_lookup_hash: string | null
}

/** Input exists only in request memory, then becomes ciphertext before leaving the trusted function. */
export async function encryptCustomer(value: unknown): Promise<EncryptedCustomer> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('INVALID_CUSTOMER')
  const customer = value as Record<string, unknown>
  const fullName = text(customer.full_name, 'CUSTOMER_NAME', 2, 160)
  const phone = text(customer.phone, 'CUSTOMER_PHONE', 6, 30)
  const nationalId = optionalText(customer.national_id, 'NATIONAL_ID', 80)
  const address = optionalText(customer.address, 'CUSTOMER_ADDRESS', 1000)

  return {
    p_full_name_ciphertext: await encryptSensitive(fullName),
    p_phone_ciphertext: await encryptSensitive(phone),
    p_national_id_ciphertext: await encryptSensitive(nationalId),
    p_address_ciphertext: await encryptSensitive(address),
    p_full_name_lookup_hash: await sensitiveLookupHash(fullName),
    p_phone_lookup_hash: await sensitiveLookupHash(phone),
    p_national_id_lookup_hash: await sensitiveLookupHash(nationalId),
  }
}
