import { useState, type FormEvent } from 'react'
import { ShieldCheck, Smartphone } from 'lucide-react'
import { useAuth } from '../contexts/AuthContext'
import { readableError } from '../lib/api'
import { Logo } from '../components/Logo'
import { InlineLoader } from '../components/LoadingState'

export function MfaPage() {
  const { verifyMfa, signOut } = useAuth()
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setBusy(true); setError(null)
    try { await verifyMfa(code) } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  return <main className="mfa-layout"><section className="mfa-card"><Logo /><div className="mfa-icon"><Smartphone size={30} /></div><span className="eyebrow">تحقق إضافي مطلوب</span><h1>أكمل التحقق بخطوتين</h1><p>للحفاظ على بيانات الأجهزة والبلاغات، أدخل الرمز الظاهر في تطبيق المصادقة الخاص بك.</p>{error && <div className="inline-alert danger">{error}</div>}<form className="form-stack" onSubmit={submit}><label>رمز التحقق<input className="mfa-code" dir="ltr" inputMode="numeric" autoComplete="one-time-code" value={code} onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 8))} placeholder="000000" required /></label><button className="primary-button full-button" disabled={busy}>{busy ? <InlineLoader /> : <><ShieldCheck size={18} />تحقق ومتابعة</>}</button></form><button className="link-button centered" onClick={() => void signOut()}>استخدام حساب آخر</button></section></main>
}
