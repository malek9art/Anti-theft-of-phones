import { useState, type FormEvent } from 'react'
import { ArrowLeft, KeyRound, LockKeyhole, Mail, ShieldCheck, UserPlus } from 'lucide-react'
import { useAuth } from '../contexts/AuthContext'
import { readableError } from '../lib/api'
import { requireSupabase } from '../lib/supabase'
import { Logo } from '../components/Logo'
import { InlineLoader } from '../components/LoadingState'

function passwordLooksStrong(value: string): boolean {
  return value.length >= 12 && /[a-z]/.test(value) && /[A-Z]/.test(value) && /\d/.test(value) && /[^A-Za-z0-9]/.test(value)
}

export function LoginPage() {
  const { signIn, blockedStatus } = useAuth()
  const [mode, setMode] = useState<'login' | 'signup'>('login')
  const [identifier, setIdentifier] = useState('')
  const [password, setPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setError(null)
    setMessage(null)
    setBusy(true)
    try {
      if (mode === 'login') {
        await signIn(identifier, password)
      } else {
        if (!identifier.includes('@')) throw new Error('استخدم بريدًا إلكترونيًا صالحًا لإنشاء الحساب.')
        if (!passwordLooksStrong(password)) throw new Error('اختر كلمة مرور من 12 رمزًا على الأقل تضم أحرفًا كبيرة وصغيرة وأرقامًا ورمزًا خاصًا.')
        const { error: signUpError } = await requireSupabase().auth.signUp({
          email: identifier.trim(), password, options: { data: { display_name: displayName.trim() || 'مستخدم جديد' } },
        })
        if (signUpError) throw signUpError
        setMessage('تم إنشاء الطلب. تحقق من البريد الإلكتروني لتأكيد الحساب، ثم سجّل الدخول لتقديم بيانات المحل.')
        setMode('login')
        setPassword('')
      }
    } catch (caught) {
      setError(caught instanceof Error && !caught.message.includes('AuthApiError') ? caught.message : readableError(caught))
    } finally {
      setBusy(false)
    }
  }

  async function resetPassword() {
    setError(null)
    setMessage(null)
    if (!identifier.includes('@')) {
      setError('أدخل البريد الإلكتروني أولًا لإرسال رابط استعادة كلمة المرور.')
      return
    }
    setBusy(true)
    try {
      const { error: resetError } = await requireSupabase().auth.resetPasswordForEmail(identifier.trim(), { redirectTo: window.location.origin })
      if (resetError) throw resetError
      setMessage('إذا كان الحساب موجودًا، سيصلك رابط آمن لاستعادة كلمة المرور.')
    } catch (caught) {
      setError(readableError(caught))
    } finally {
      setBusy(false)
    }
  }

  const blockedMessage = blockedStatus === 'suspended'
    ? 'تم تعليق هذا الحساب. تواصل مع إدارة النظام المعتمدة.'
    : blockedStatus === 'inactive' ? 'هذا الحساب غير نشط حاليًا.' : null

  return <main className="auth-layout">
    <section className="auth-visual">
      <div className="auth-grid" />
      <div className="auth-visual-content"><Logo /><span className="hero-pill"><ShieldCheck size={16} />منصة مؤسسية محمية</span><h1>هوية الجهاز.<br />سجل موثوق.<br /><em>إجراء آمن.</em></h1><p>نقطة ربط مركزية بين عمليات البيع والصيانة والبلاغات، مع صلاحيات دقيقة وسجل تدقيق قابل للمراجعة.</p><div className="trust-list"><span><ShieldCheck size={18} />تحقق خادمي وصلاحيات RLS</span><span><LockKeyhole size={18} />أدلة وبيانات هوية خاصة</span><span><KeyRound size={18} />دعم التحقق بخطوتين</span></div></div>
      <p className="auth-footer">حماية © {new Date().getFullYear()} · لا تتبع المنصة موقع جهاز من رقم IMEI وحده.</p>
    </section>
    <section className="auth-form-area">
      <div className="auth-card">
        <div className="auth-card-heading"><span className="eyebrow">{mode === 'login' ? 'دخول آمن' : 'بدء طلب اعتماد'}</span><h2>{mode === 'login' ? 'مرحبًا بعودتك' : 'إنشاء حساب جهة أو محل'}</h2><p>{mode === 'login' ? 'أدخل بيانات حسابك المعتمد للمتابعة.' : 'يظل الحساب معلّقًا حتى الاعتماد الرسمي؛ لا تُمنح صلاحيات تشغيل تلقائيًا.'}</p></div>
        {blockedMessage && <div className="inline-alert danger"><ShieldCheck size={18} />{blockedMessage}</div>}
        {message && <div className="inline-alert success"><ShieldCheck size={18} />{message}</div>}
        {error && <div className="inline-alert danger"><ShieldCheck size={18} />{error}</div>}
        <form onSubmit={submit} className="form-stack">
          {mode === 'signup' && <label>الاسم المعروض<input value={displayName} onChange={(event) => setDisplayName(event.target.value)} maxLength={160} autoComplete="name" placeholder="الاسم أو اسم الجهة" /></label>}
          <label>البريد الإلكتروني أو رقم الهاتف<input dir="ltr" value={identifier} onChange={(event) => setIdentifier(event.target.value)} autoComplete={mode === 'login' ? 'username' : 'email'} placeholder="name@example.com أو +966…" required /></label>
          <label>كلمة المرور<input dir="ltr" type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete={mode === 'login' ? 'current-password' : 'new-password'} placeholder="••••••••••••" required /></label>
          {mode === 'signup' && <p className="field-help">12 رمزًا على الأقل، مع أحرف كبيرة وصغيرة وأرقام ورمز خاص.</p>}
          <button className="primary-button full-button" disabled={busy}>{busy ? <InlineLoader /> : mode === 'login' ? <>تسجيل الدخول <ArrowLeft size={18} /></> : <><UserPlus size={18} />إنشاء طلب الحساب</>}</button>
        </form>
        <div className="auth-actions">{mode === 'login' && <button onClick={() => void resetPassword()} disabled={busy}>نسيت كلمة المرور؟</button>}<button onClick={() => { setMode((current) => current === 'login' ? 'signup' : 'login'); setError(null); setMessage(null) }}>{mode === 'login' ? 'تسجيل جهة أو محل جديد' : 'لديك حساب بالفعل؟ سجّل الدخول'}</button></div>
        <p className="auth-note"><Mail size={15} />لا نخزن بيانات العملاء أو رموز الجلسة في تخزين المتصفح الدائم.</p>
      </div>
    </section>
  </main>
}
