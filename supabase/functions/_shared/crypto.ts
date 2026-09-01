function fromBase64Url(value: string): ArrayBuffer {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (value.length % 4)) % 4)
  const binary = atob(padded)
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0))
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
}

function toBase64Url(value: ArrayBuffer | Uint8Array): string {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value)
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

function secret(name: string): ArrayBuffer {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`MISSING_${name}`)
  const bytes = fromBase64Url(value)
  if (bytes.byteLength !== 32) throw new Error(`INVALID_${name}`)
  return bytes
}

async function aesKey(): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', secret('SENSITIVE_DATA_ENCRYPTION_KEY'), { name: 'AES-GCM' }, false, ['encrypt', 'decrypt'])
}

async function hmacKey(): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', secret('SENSITIVE_DATA_LOOKUP_KEY'), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
}

export function normalizeSensitiveLookup(value: string): string {
  return value.trim().normalize('NFKC').toLocaleLowerCase('ar').replace(/[\s\-()]+/g, '')
}

/** AES-256-GCM versioned envelope. Keys remain only in the Edge Function secret store. */
export async function encryptSensitive(value: string | null | undefined): Promise<string | null> {
  if (!value) return null
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const plaintext = new TextEncoder().encode(value)
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await aesKey(), plaintext)
  return `v1.${toBase64Url(iv)}.${toBase64Url(ciphertext)}`
}

export async function decryptSensitive(envelope: string | null): Promise<string | null> {
  if (!envelope) return null
  const [version, encodedIv, encodedCiphertext, ...rest] = envelope.split('.')
  if (version !== 'v1' || !encodedIv || !encodedCiphertext || rest.length) throw new Error('INVALID_CIPHERTEXT_ENVELOPE')
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: fromBase64Url(encodedIv) },
    await aesKey(),
    fromBase64Url(encodedCiphertext),
  )
  return new TextDecoder().decode(plaintext)
}

/** A keyed blind index enables exact permitted lookups without persisting plaintext PII. */
export async function sensitiveLookupHash(value: string | null | undefined): Promise<string | null> {
  if (!value) return null
  const normalized = normalizeSensitiveLookup(value)
  if (!normalized) return null
  const signature = await crypto.subtle.sign('HMAC', await hmacKey(), new TextEncoder().encode(normalized))
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

export async function sha256(input: ArrayBuffer): Promise<string> {
  const hash = await crypto.subtle.digest('SHA-256', input)
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, '0')).join('')
}
