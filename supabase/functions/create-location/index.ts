import { withAuthenticatedRequest, success } from '../_shared/handler.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { numberInRange, optionalText, text } from '../_shared/validation.ts'

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const latitude = numberInRange(body.latitude, 'LATITUDE', -90, 90)
  const longitude = numberInRange(body.longitude, 'LONGITUDE', -180, 180)
  if ((latitude === null) !== (longitude === null)) throw new Error('INVALID_LOCATION')
  const data = await rpc(context.client, 'api_create_location', {
    p_label: text(body.label, 'LABEL', 1, 180),
    p_address_text: optionalText(body.address_text, 'ADDRESS', 1000),
    p_latitude: latitude,
    p_longitude: longitude,
  })
  return success(request, { location_id: data }, 201)
}, { scope: 'create-location', maxRequests: 30, windowSeconds: 600 }))
