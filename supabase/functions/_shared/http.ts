import { corsHeaders } from './cors.ts'

export type PublicErrorCode =
  | 'AUTH_REQUIRED'
  | 'FORBIDDEN'
  | 'MFA_REQUIRED'
  | 'INVALID_INPUT'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'RATE_LIMITED'
  | 'SERVICE_UNAVAILABLE'
  | 'INTERNAL_ERROR'

export function json(request: Request, body: unknown, status = 200, extraHeaders: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      'Content-Type': 'application/json; charset=utf-8',
      ...extraHeaders,
    },
  })
}

export function publicError(request: Request, code: PublicErrorCode, messageAr: string, status: number): Response {
  return json(request, { error: { code, message_ar: messageAr } }, status)
}

/** Maps internal Postgres/GoTrue error messages to intentionally small, user-safe responses. */
export function databaseError(request: Request, error: unknown): Response {
  const raw = error instanceof Error ? error.message : String(error)
  console.error('trusted-operation-failed', { message: raw.slice(0, 500) })

  if (/AUTH_REQUIRED|JWT|not authenticated/i.test(raw)) {
    return publicError(request, 'AUTH_REQUIRED', 'انتهت الجلسة أو لم يتم تسجيل الدخول.', 401)
  }
  if (/MFA_REQUIRED/i.test(raw)) {
    return publicError(request, 'MFA_REQUIRED', 'يلزم التحقق بخطوتين لإتمام هذه العملية.', 403)
  }
  if (/INVALID_OR_OUT_OF_SCOPE_AGENCY/i.test(raw)) {
    return publicError(request, 'FORBIDDEN', 'الحساب غير مربوط بجهة اختصاص نشطة أو أن الجهة المختارة خارج نطاقك.', 403)
  }
  if (/FORBIDDEN|OUT_OF_SCOPE|NOT_OPERATIONAL|NOT_APPROVED|NOT_ACTIVE|SERVICE_ROLE_REQUIRED|SPOOFING|IMMUTABLE|DIRECT_/i.test(raw)) {
    return publicError(request, 'FORBIDDEN', 'لا تملك الصلاحية اللازمة لإتمام هذه العملية.', 403)
  }
  if (/SECURITY_ALERT|NOT_ASSIGNABLE|NOT_PENDING|NOT_OPEN|NOT_SUSPENDABLE|NOT_ELIGIBLE/i.test(raw)) {
    return publicError(request, 'CONFLICT', 'لا يمكن إتمام العملية بسبب الحالة الأمنية أو التشغيلية الحالية.', 409)
  }
  if (/NOT_FOUND|_NOT_FOUND|NOT_AVAILABLE/i.test(raw)) {
    return publicError(request, 'NOT_FOUND', 'السجل المطلوب غير متاح أو لا تملك صلاحية الوصول إليه.', 404)
  }
  if (/DUPLICATE|ALREADY_EXISTS|23505|CONFLICT/i.test(raw)) {
    return publicError(request, 'CONFLICT', 'توجد بيانات مسجلة مسبقًا تتعارض مع هذه العملية.', 409)
  }
  if (/INVALID|REQUIRED|MISMATCH|NOT_PENDING|NOT_ASSIGNABLE|NOT_OPEN|TOO_MANY/i.test(raw)) {
    return publicError(request, 'INVALID_INPUT', 'تحقق من البيانات المدخلة ثم أعد المحاولة.', 422)
  }
  return publicError(request, 'INTERNAL_ERROR', 'تعذر إتمام العملية الآن. لم يتم عرض أي تفاصيل تقنية.', 500)
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  const contentType = request.headers.get('content-type') ?? ''
  if (!contentType.includes('application/json')) {
    throw new Error('INVALID_CONTENT_TYPE')
  }
  const body = await request.json()
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('INVALID_BODY')
  return body as Record<string, unknown>
}
