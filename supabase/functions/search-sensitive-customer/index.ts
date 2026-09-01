import { sensitiveLookupHash } from '../_shared/crypto.ts'
import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { enumValue, text } from '../_shared/validation.ts'

const lookupTypes = ['phone', 'full_name', 'national_id'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const lookupValue = text(body.query, 'QUERY', 2, 160)
  const lookupHash = await sensitiveLookupHash(lookupValue)
  if (!lookupHash) throw new Error('INVALID_QUERY')
  const rawLimit = typeof body.limit === 'number' ? body.limit : 20
  if (!Number.isInteger(rawLimit) || rawLimit < 1 || rawLimit > 50) throw new Error('INVALID_LIMIT')
  const data = await rpc(context.client, 'api_search_customer_by_lookup_hash', {
    p_lookup_type: enumValue(body.lookup_type, lookupTypes, 'LOOKUP_TYPE'),
    p_lookup_hash: lookupHash,
    p_purpose: text(body.purpose, 'PURPOSE', 5, 500),
    p_limit: rawLimit,
  })
  return success(request, data)
}, { scope: 'search-sensitive-customer', maxRequests: 12, windowSeconds: 600 }))
