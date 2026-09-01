import { useState, type FormEvent } from 'react'
import { AlertOctagon, ArrowLeft, CheckCircle2, CircleHelp, Search, ShieldAlert, Smartphone } from 'lucide-react'
import { Link } from 'react-router-dom'
import { PageHeader } from '../components/PageHeader'
import { InlineLoader } from '../components/LoadingState'
import { SeverityBadge, StatusBadge } from '../components/StatusBadge'
import { invoke, readableError } from '../lib/api'
import { isValidImei, normalizeImei } from '../lib/imei'
import type { ImeiResult } from '../types/domain'

export function DeviceCheckPage() {
  const [imei, setImei] = useState('')
  const [result, setResult] = useState<ImeiResult | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault()
    const normalized = normalizeImei(imei)
    setError(null); setResult(null)
    if (!isValidImei(normalized)) { setError('أدخل رقم IMEI مكوّنًا من 15 رقمًا مع رقم تحقق صحيح.'); return }
    setBusy(true)
    try { setResult(await invoke<ImeiResult>('check-imei', { imei: normalized })) } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  return <>
    <PageHeader eyebrow="التحقق المركزي" title="فحص الجهاز" description="يُنفّذ الفحص عبر الخادم بأحدث حالة متاحة، وتُسجل عملية البحث لأغراض الأمان والتدقيق." />
    <section className="imei-hero panel">
      <div className="imei-hero-icon"><Search size={28} /></div><div><h2>أدخل رقم IMEI</h2><p>يمكنك العثور عليه من إعدادات الجهاز أو عبر الرمز <b dir="ltr">*#06#</b>. لا يتم الاعتماد على نتيجة مخزنة محليًا.</p></div>
      <form onSubmit={submit} className="imei-form"><label className="sr-only" htmlFor="imei">رقم IMEI</label><input id="imei" dir="ltr" inputMode="numeric" maxLength={15} autoFocus value={imei} onChange={(event) => setImei(event.target.value.replace(/\D/g, '').slice(0, 15))} placeholder="000000000000000" /><button className="primary-button" disabled={busy}>{busy ? <InlineLoader /> : <><Search size={18} />فحص الجهاز</>}</button></form>
      <div className="imei-assurance"><ShieldAlert size={16} />لا تظهر البيانات الشخصية أو الأدلة إلا في نطاق الصلاحية المعتمد.</div>
    </section>
    {error && <div className="inline-alert danger page-alert"><AlertOctagon size={19} />{error}</div>}
    {result && (result.security_alert ? <section className="security-result security-critical"><div className="result-symbol"><ShieldAlert size={37} /></div><div className="result-main"><span className="result-kicker">تنبيه أمني</span><h2>هذا الجهاز مسجل ضمن الأجهزة المبلغ عنها</h2><p>{result.message_ar}</p><div className="result-actions">{result.report && <Link className="danger-button" to={`/reports/${result.report.id}`}>عرض البلاغ <ArrowLeft size={17} /></Link>}{result.device && <Link className="ghost-on-danger" to={`/devices/${result.device.id}`}>سجل الجهاز</Link>}</div></div><div className="result-meta">{result.report && <><span>رقم البلاغ<b dir="ltr">{result.report.report_number}</b></span><span>الحالة<StatusBadge status={result.report.status} /></span><span>الأولوية<SeverityBadge severity={result.report.priority} /></span></>}</div></section> : <section className="security-result security-clear"><div className="result-symbol"><CheckCircle2 size={37} /></div><div className="result-main"><span className="result-kicker">نتيجة الفحص</span><h2>{result.found ? 'الجهاز غير مسجل عليه بلاغ نشط' : 'لم يُعثر على الجهاز في السجل المركزي'}</h2><p>{result.message_ar}</p>{result.device && <div className="result-actions"><Link className="secondary-button" to={`/devices/${result.device.id}`}>عرض سجل الجهاز <ArrowLeft size={17} /></Link></div>}</div>{result.device && <div className="result-meta"><span>الجهاز<b>{result.device.brand} {result.device.model}</b></span><span>الحالة<StatusBadge status={result.device.status} /></span></div>}</section>)}
    {!result && !error && <section className="check-guidance"><CircleHelp size={22} /><div><b>نتيجة واحدة، حسب صلاحيتك</b><p>النتيجة الأمنية لا تكشف هوية المبلّغ أو رقم هويته أو هاتفه أو أي دليل خاص للمستخدم غير المخوّل.</p></div></section>}
  </>
}
