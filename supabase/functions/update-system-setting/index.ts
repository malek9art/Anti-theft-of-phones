import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { enumValue } from '../_shared/validation.ts'

const keys = ['security.imei_checks_per_10m', 'security.signed_url_ttl_seconds', 'retention.audit_log_years'] as const

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  if (typeof body.value !== 'number' || !Number.isInteger(body.value) || body.value < 1 || body.value > 100_000) throw new Error('INVALID_SETTING_VALUE')
  await rpc(context.client, 'api_update_system_setting', {
    p_key: enumValue(body.key, keys, 'SETTING_KEY'),
    p_value: body.value,
  })
  return success(request, { updated: true })
}, { scope: 'update-system-setting', maxRequests: 10, windowSeconds: 600 }))
