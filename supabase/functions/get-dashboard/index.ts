import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'

function optionalDate(value: unknown, label: string): string | null {
  if (value === null || value === undefined || value === '') return null
  if (typeof value !== 'string' || Number.isNaN(new Date(value).getTime())) throw new Error(`INVALID_${label}`)
  return new Date(value).toISOString()
}

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const data = await rpc(context.client, 'api_get_dashboard', {
    p_from: optionalDate(body.from, 'FROM_DATE'),
    p_to: optionalDate(body.to, 'TO_DATE'),
  })
  return success(request, data)
}, { scope: 'get-dashboard', maxRequests: 30, windowSeconds: 60 }))
