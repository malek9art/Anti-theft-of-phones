import type { RequestContext } from './supabase.ts'
import { rpc, serviceClient } from './supabase.ts'

async function digestHex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input)
  const hash = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

type RateLimitResult = { allowed: boolean; remaining: number; retry_after_seconds: number }

/**
 * Uses an atomic database counter rather than process memory, so limits work across Edge isolates.
 * The bucket holds a one-way hash of account + proxy IP, not the raw address.
 */
export async function enforceRateLimit(
  context: RequestContext,
  scope: string,
  maxRequests: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  const bucketHash = await digestHex(`${scope}:${context.user.id}:${context.ipAddress ?? 'unknown'}`)
  return rpc<RateLimitResult>(serviceClient(), 'api_consume_rate_limit', {
    p_bucket_hash: bucketHash,
    p_window_seconds: windowSeconds,
    p_max_requests: maxRequests,
  })
}
