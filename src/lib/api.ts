import { requireSupabase } from './supabase'
import type { ApiErrorShape } from '../types/domain'

export class ApiError extends Error {
  code: string
  constructor(message: string, code = 'INTERNAL_ERROR') {
    super(message)
    this.name = 'ApiError'
    this.code = code
  }
}

export async function invoke<T>(name: string, body: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await requireSupabase().functions.invoke(name, { body })
  if (error) {
    const response = (error.context && await error.context.json().catch(() => null)) as ApiErrorShape | null
    if (response?.error?.code === 'AUTH_REQUIRED') void requireSupabase().auth.signOut()
    throw new ApiError(response?.error?.message_ar ?? 'تعذر الاتصال بالخدمة الآمنة.', response?.error?.code ?? 'NETWORK_ERROR')
  }
  const response = data as ApiErrorShape & { data?: T }
  if (response?.error) {
    if (response.error.code === 'AUTH_REQUIRED') void requireSupabase().auth.signOut()
    throw new ApiError(response.error.message_ar ?? response.error.message ?? 'تعذر إتمام العملية.', response.error.code)
  }
  return response.data as T
}

export function readableError(error: unknown): string {
  if (error instanceof ApiError) return error.message
  if (error instanceof Error && error.message === 'SUPABASE_NOT_CONFIGURED') return 'لم يتم إعداد اتصال Supabase بعد.'
  return 'تعذر إتمام العملية الآن. يرجى المحاولة لاحقًا.'
}
