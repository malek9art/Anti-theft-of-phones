import { isAllowedOrigin, preflight } from './cors.ts'
import { databaseError, json, publicError } from './http.ts'
import { enforceRateLimit } from './rate-limit.ts'
import { requestContext, rpc, serviceClient, type RequestContext } from './supabase.ts'

export type TrustedHandler = (request: Request, context: RequestContext) => Promise<Response>

type Options = {
  scope: string
  maxRequests?: number
  windowSeconds?: number
}

async function recordDeniedRequest(context: RequestContext, action: string, reason: string): Promise<void> {
  try {
    await rpc(serviceClient(), 'api_record_denied_request', {
      p_actor_id: context.user.id,
      p_action: action.replace(/[^a-z0-9_-]/gi, '_').toLowerCase(),
      p_reason_code: reason.replace(/[^A-Z0-9_]/gi, '_').toUpperCase().slice(0, 100) || 'DENIED',
      p_ip_address: context.ipAddress,
      p_device_information: context.deviceInformation,
    })
  } catch (telemetryError) {
    // Audit telemetry must never turn an authorization rejection into a successful operation.
    console.error('denied-request-telemetry-failed', telemetryError)
  }
}

export function withAuthenticatedRequest(handler: TrustedHandler, options: Options) {
  return async (request: Request): Promise<Response> => {
    const optionsResponse = preflight(request)
    if (optionsResponse) return optionsResponse
    if (request.method !== 'POST') return publicError(request, 'INVALID_INPUT', 'طريقة الطلب غير مدعومة.', 405)
    if (!isAllowedOrigin(request)) return publicError(request, 'FORBIDDEN', 'مصدر الطلب غير مسموح به.', 403)

    let context: RequestContext | null = null
    try {
      context = await requestContext(request)
      const limited = await enforceRateLimit(
        context,
        options.scope,
        options.maxRequests ?? 60,
        options.windowSeconds ?? 60,
      )
      if (!limited.allowed) {
        await recordDeniedRequest(context, options.scope, 'RATE_LIMITED')
        return publicError(request, 'RATE_LIMITED', 'تم تجاوز الحد الآمن للطلبات. حاول لاحقًا.', 429)
      }
      return await handler(request, context)
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      if (/^MISSING_/.test(message)) {
        return publicError(request, 'SERVICE_UNAVAILABLE', 'الخدمة الآمنة غير مكتملة الإعداد حاليًا.', 503)
      }
      if (/^INVALID_|^AUTH_REQUIRED|^INVALID_CONTENT_TYPE|^INVALID_BODY/.test(message)) {
        const status = message.includes('AUTH_REQUIRED') ? 401 : 422
        return publicError(request, status === 401 ? 'AUTH_REQUIRED' : 'INVALID_INPUT', status === 401 ? 'انتهت الجلسة أو لم يتم تسجيل الدخول.' : 'تحقق من البيانات المدخلة ثم أعد المحاولة.', status)
      }
      if (context && /FORBIDDEN|OUT_OF_SCOPE|NOT_OPERATIONAL|NOT_ACTIVE|SPOOFING|DIRECT_|IMMUTABLE|SERVICE_ROLE_REQUIRED|MFA_REQUIRED/i.test(message)) {
        await recordDeniedRequest(context, options.scope, message.match(/[A-Z_]{3,}/)?.[0] ?? 'FORBIDDEN')
      }
      return databaseError(request, error)
    }
  }
}

export function success(request: Request, data: unknown, status = 200): Response {
  return json(request, { data }, status)
}
