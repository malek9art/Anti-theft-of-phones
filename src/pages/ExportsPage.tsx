import { useState } from 'react'
import { Download, FileBarChart2, FileText, Printer, ShieldCheck } from 'lucide-react'
import { PageHeader } from '../components/PageHeader'
import { InlineLoader } from '../components/LoadingState'
import { ApiError, readableError } from '../lib/api'
import { requireSupabase } from '../lib/supabase'

type ReportKind = 'sales' | 'repairs' | 'formats' | 'reports'
const choices: Array<{ kind: ReportKind; title: string; description: string }> = [
  { kind: 'sales', title: 'تقرير مبيعات المحل', description: 'عمليات البيع المصرح بها ضمن نطاقك.' },
  { kind: 'repairs', title: 'تقرير عمليات الصيانة', description: 'سجل عمليات الصيانة حسب الفترة.' },
  { kind: 'formats', title: 'تقرير عمليات الفرمتة', description: 'عمليات الفرمتة المسجلة ونهايات IMEI فقط.' },
  { kind: 'reports', title: 'تقرير البلاغات', description: 'بلاغات مسموح بها دون كشف هوية المبلّغ.' },
]

export function ExportsPage() {
  const [from, setFrom] = useState(new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().slice(0, 10))
  const [to, setTo] = useState(new Date().toISOString().slice(0, 10))
  const [busy, setBusy] = useState<ReportKind | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function download(kind: ReportKind) {
    setBusy(kind); setError(null)
    try {
      const client = requireSupabase()
      const { data: sessionData } = await client.auth.getSession()
      const token = sessionData.session?.access_token
      if (!token) throw new ApiError('انتهت الجلسة. سجّل الدخول مجددًا.', 'AUTH_REQUIRED')
      const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/generate-report`
      const response = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${token}`, apikey: import.meta.env.VITE_SUPABASE_ANON_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ kind, from: new Date(`${from}T00:00:00`).toISOString(), to: new Date(`${to}T23:59:59`).toISOString() }) })
      if (!response.ok) {
        const body = await response.json().catch(() => null)
        throw new ApiError(body?.error?.message_ar ?? 'تعذر توليد التقرير.', body?.error?.code)
      }
      const blob = await response.blob()
      const objectUrl = URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = objectUrl; anchor.download = `himaya-${kind}-${from}-${to}.csv`; anchor.click()
      URL.revokeObjectURL(objectUrl)
    } catch (caught) { setError(readableError(caught)) } finally { setBusy(null) }
  }

  return <><PageHeader eyebrow="توليد خادمي" title="التقارير والتصدير" description="تُطبق الصلاحيات داخل التقرير قبل إنشائه. لا تحتوي الملفات المصدرة على بيانات الهوية المشفرة أو الأدلة الخاصة." actions={<button className="secondary-button" onClick={() => window.print()}><Printer size={17} />طباعة / حفظ PDF</button>} /><section className="export-range panel"><FileText size={22} /><div><b>الفترة الزمنية</b><small>يُنشأ الملف بصيغة CSV متوافقة مع Excel مع حماية من صيَغ الجداول الضارة.</small></div><label>من<input type="date" dir="ltr" value={from} onChange={(event) => setFrom(event.target.value)} /></label><label>إلى<input type="date" dir="ltr" value={to} onChange={(event) => setTo(event.target.value)} /></label></section>{error && <div className="inline-alert danger page-alert">{error}</div>}<section className="export-grid">{choices.map((choice) => <article className="export-card" key={choice.kind}><span><FileBarChart2 size={25} /></span><h2>{choice.title}</h2><p>{choice.description}</p><button className="primary-button" disabled={busy !== null || !from || !to} onClick={() => void download(choice.kind)}>{busy === choice.kind ? <InlineLoader /> : <><Download size={17} />تنزيل CSV / Excel</>}</button></article>)}</section><section className="print-note"><ShieldCheck size={19} /><div><b>نسخة PDF للطباعة</b><p>استخدم «طباعة / حفظ PDF» لإنشاء نسخة PDF متوافقة مع صلاحيات الشاشة الحالية. يفضل ضبط خدمة عرض PDF خادمية موقعة قبل استخدام تقارير قضائية رسمية.</p></div></section></>
}
