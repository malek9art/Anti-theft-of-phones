import { useState, type FormEvent } from 'react'
import { CheckCircle2, KeyRound, LogOut, QrCode, ShieldCheck, Smartphone, TriangleAlert } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { InlineLoader } from '../components/LoadingState'
import { Modal } from '../components/Modal'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'

export function SecuritySettingsPage() {
  const { bootstrap, enrollMfa, verifyEnrollment } = useAuth()
  const [enrollment, setEnrollment] = useState<{ factorId: string; qrCode: string; secret: string } | null>(null)
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function beginMfa() { setBusy(true); setError(null); try { setEnrollment(await enrollMfa()) } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  async function verify(event: FormEvent) { event.preventDefault(); if (!enrollment) return; setBusy(true); setError(null); try { await verifyEnrollment(enrollment.factorId, code); setEnrollment(null); setCode(''); setMessage('تم تفعيل التحقق بخطوتين لهذه الجلسة.'); } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  async function revokeOtherSessions() { setBusy(true); setError(null); try { await invoke('revoke-other-sessions', {}); setMessage('تم إلغاء الجلسات الأخرى للحساب.'); } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }

  return <><PageHeader eyebrow="حماية الحساب" title="أمان الجلسة والتحقق بخطوتين" description="رموز الجلسة ذاكرية فقط في هذه الواجهة، وتنتهي وفق سياسة Supabase. لا تحفظ المنصة بيانات العمل الحساسة في الجهاز." />{message && <div className="inline-alert success page-alert"><CheckCircle2 size={18} />{message}</div>}{error && <div className="inline-alert danger page-alert"><TriangleAlert size={18} />{error}</div>}<section className="security-settings-grid"><article className="security-setting-card"><span><KeyRound size={24} /></span><div><h2>التحقق بخطوتين</h2><p>{bootstrap?.user.mfa_required ? 'مطلوب لهذا الحساب عند تنفيذ العمليات الحساسة.' : 'غير مفروض من الإدارة، لكن يوصى بتفعيله.'}</p><ul><li>تطبيق مصادقة يدعم TOTP</li><li>التحقق يحدث قبل العمليات الحساسة</li><li>لا ترسل رموزك إلى الدعم أو أي طرف آخر</li></ul><button className="primary-button" disabled={busy} onClick={() => void beginMfa()}>{busy ? <InlineLoader /> : <><Smartphone size={17} />إعداد تطبيق المصادقة</>}</button></div></article><article className="security-setting-card"><span><LogOut size={24} /></span><div><h2>إدارة الجلسات</h2><p>ألغِ جميع الجلسات الأخرى إذا فقدت جهازًا أو اشتبهت بوصول غير مصرح به.</p><ul><li>تبقى الجلسة الحالية مفتوحة</li><li>يُسجّل الإجراء في سجل التدقيق</li><li>يتطلب تنفيذ الإجراء جلسة صالحة</li></ul><button className="danger-outline-button" disabled={busy} onClick={() => void revokeOtherSessions()}>{busy ? <InlineLoader /> : <><LogOut size={17} />إنهاء الجلسات الأخرى</>}</button></div></article></section>{enrollment && <Modal title="تفعيل التحقق بخطوتين" onClose={() => setEnrollment(null)}><div className="mfa-enroll"><QrCode size={22} /><p>امسح الرمز من تطبيق المصادقة، ثم أدخل الرمز المؤقت لإكمال التفعيل.</p>{enrollment.qrCode ? <img src={enrollment.qrCode} alt="رمز QR لتطبيق المصادقة" /> : null}<label>المفتاح اليدوي <input dir="ltr" value={enrollment.secret} readOnly /></label><form className="form-stack" onSubmit={verify}><label>الرمز المؤقت<input className="mfa-code" dir="ltr" inputMode="numeric" autoComplete="one-time-code" value={code} onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 8))} required /></label><button className="primary-button full-button" disabled={busy}>{busy ? <InlineLoader /> : <><ShieldCheck size={17} />تأكيد التفعيل</>}</button></form></div></Modal>}</>
}
