import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { ApiError, invoke } from '../lib/api'
import { isSupabaseConfigured, requireSupabase, supabase } from '../lib/supabase'
import type { Bootstrap } from '../types/domain'

type MfaEnrollment = { factorId: string; qrCode: string; secret: string }

// Must stay aligned with database calls using private.require_permission(..., true).
const AAL2_PERMISSIONS = new Set([
  'create_stolen_report', 'change_report_status', 'assign_case', 'update_follow_up',
  'upload_evidence', 'view_evidence', 'view_sensitive_data', 'view_identity',
  'correct_record', 'approve_shop', 'suspend_shop', 'manage_permissions',
  'manage_users', 'generate_reports', 'view_audit_logs', 'view_security_events',
  'manage_system_settings',
])

type AuthContextValue = {
  configured: boolean
  loading: boolean
  session: Session | null
  bootstrap: Bootstrap | null
  needsMfa: boolean
  blockedStatus: Bootstrap['user']['account_status'] | null
  signIn: (identifier: string, password: string) => Promise<void>
  signOut: () => Promise<void>
  refresh: () => Promise<void>
  verifyMfa: (code: string) => Promise<void>
  enrollMfa: () => Promise<MfaEnrollment>
  verifyEnrollment: (factorId: string, code: string) => Promise<void>
  can: (permission: string) => boolean
}

const AuthContext = createContext<AuthContextValue | null>(null)

function authMessage(error: unknown): string {
  if (error instanceof ApiError) return error.message
  return 'تعذر تسجيل الدخول. تحقق من بيانات الحساب ثم أعد المحاولة.'
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [loading, setLoading] = useState(true)
  const [session, setSession] = useState<Session | null>(null)
  const [bootstrap, setBootstrap] = useState<Bootstrap | null>(null)
  const [needsMfa, setNeedsMfa] = useState(false)
  const [blockedStatus, setBlockedStatus] = useState<Bootstrap['user']['account_status'] | null>(null)

  const hydrate = useCallback(async (nextSession: Session | null) => {
    setSession(nextSession)
    if (!nextSession || !isSupabaseConfigured) {
      setBootstrap(null)
      setNeedsMfa(false)
      setLoading(false)
      return
    }

    try {
      const profile = await invoke<Bootstrap>('bootstrap')
      if (profile.user.account_status === 'pending') {
        // Pending accounts are allowed only into the isolated onboarding view; they get no operational routes or permissions.
        setBootstrap(profile)
        setBlockedStatus('pending')
        setNeedsMfa(false)
        return
      }
      if (profile.user.account_status !== 'active') {
        setBlockedStatus(profile.user.account_status)
        setBootstrap(null)
        setNeedsMfa(false)
        await requireSupabase().auth.signOut()
        setSession(null)
        return
      }
      const assurance = await requireSupabase().auth.mfa.getAuthenticatorAssuranceLevel()
      setBootstrap(profile)
      setBlockedStatus(null)
      setNeedsMfa(profile.permissions.some((permission) => AAL2_PERMISSIONS.has(permission)) && assurance.data?.currentLevel !== 'aal2')
    } catch (error) {
      console.error('auth-bootstrap-failed', error)
      setBootstrap(null)
      setNeedsMfa(false)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (!supabase) {
      setLoading(false)
      return
    }
    void supabase.auth.getSession().then(({ data }) => hydrate(data.session))
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (_event === 'SIGNED_OUT') {
        setSession(null)
        setBootstrap(null)
        setNeedsMfa(false)
        setLoading(false)
      }
    })
    return () => listener.subscription.unsubscribe()
  }, [hydrate])

  const signIn = useCallback(async (identifier: string, password: string) => {
    if (!isSupabaseConfigured) throw new ApiError('لم يتم إعداد اتصال Supabase بعد.', 'SUPABASE_NOT_CONFIGURED')
    const normalized = identifier.trim()
    if (!normalized || !password) throw new ApiError('أدخل البريد أو رقم الهاتف وكلمة المرور.', 'INVALID_INPUT')
    setLoading(true)
    try {
      const credentials = normalized.includes('@') ? { email: normalized, password } : { phone: normalized, password }
      const { data, error } = await requireSupabase().auth.signInWithPassword(credentials)
      if (error || !data.session) throw error ?? new Error('AUTH_REQUIRED')
      await hydrate(data.session)
      // Login telemetry is best-effort and never blocks an authenticated session.
      void invoke('security-event', { action: 'login' }).catch(() => undefined)
    } catch (error) {
      setLoading(false)
      throw new ApiError(authMessage(error), 'LOGIN_FAILED')
    }
  }, [hydrate])

  const signOut = useCallback(async () => {
    try {
      if (session) void invoke('security-event', { action: 'logout' }).catch(() => undefined)
      await requireSupabase().auth.signOut()
    } finally {
      setSession(null)
      setBootstrap(null)
      setNeedsMfa(false)
      setBlockedStatus(null)
    }
  }, [session])

  const refresh = useCallback(async () => {
    if (!session) return
    setLoading(true)
    await hydrate(session)
  }, [hydrate, session])

  const verifyMfa = useCallback(async (code: string) => {
    const client = requireSupabase()
    const { data: factors, error: factorsError } = await client.auth.mfa.listFactors()
    if (factorsError) throw new ApiError('تعذر الوصول إلى إعدادات التحقق بخطوتين.', 'MFA_ERROR')
    const factor = factors.totp.find((item) => item.status === 'verified')
    if (!factor) throw new ApiError('لا توجد وسيلة تحقق مُفعّلة لهذا الحساب.', 'MFA_NOT_ENROLLED')
    const { data: challenge, error: challengeError } = await client.auth.mfa.challenge({ factorId: factor.id })
    if (challengeError || !challenge) throw new ApiError('تعذر بدء التحقق بخطوتين.', 'MFA_ERROR')
    const { error: verifyError } = await client.auth.mfa.verify({ factorId: factor.id, challengeId: challenge.id, code: code.trim() })
    if (verifyError) throw new ApiError('رمز التحقق غير صحيح أو انتهت صلاحيته.', 'MFA_INVALID')
    const { data } = await client.auth.getSession()
    await hydrate(data.session)
    void invoke('security-event', { action: 'mfa_event' }).catch(() => undefined)
  }, [hydrate])

  const enrollMfa = useCallback(async (): Promise<MfaEnrollment> => {
    const { data, error } = await requireSupabase().auth.mfa.enroll({ factorType: 'totp', friendlyName: 'حماية — جهاز موثوق' })
    if (error || !data) throw new ApiError('تعذر إنشاء رمز التحقق بخطوتين.', 'MFA_ENROLL_FAILED')
    return { factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret }
  }, [])

  const verifyEnrollment = useCallback(async (factorId: string, code: string) => {
    const client = requireSupabase()
    const { data: challenge, error: challengeError } = await client.auth.mfa.challenge({ factorId })
    if (challengeError || !challenge) throw new ApiError('تعذر بدء التحقق بخطوتين.', 'MFA_ERROR')
    const { error: verifyError } = await client.auth.mfa.verify({ factorId, challengeId: challenge.id, code: code.trim() })
    if (verifyError) throw new ApiError('رمز التحقق غير صحيح أو انتهت صلاحيته.', 'MFA_INVALID')
    const { data } = await client.auth.getSession()
    await hydrate(data.session)
    void invoke('security-event', { action: 'mfa_event' }).catch(() => undefined)
  }, [hydrate])

  const value = useMemo<AuthContextValue>(() => ({
    configured: isSupabaseConfigured,
    loading,
    session,
    bootstrap,
    needsMfa,
    blockedStatus,
    signIn,
    signOut,
    refresh,
    verifyMfa,
    enrollMfa,
    verifyEnrollment,
    can: (permission) => Boolean(bootstrap?.permissions.includes(permission)),
  }), [blockedStatus, bootstrap, enrollMfa, loading, needsMfa, refresh, session, signIn, signOut, verifyEnrollment, verifyMfa])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}
