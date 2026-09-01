import { useState, type FormEvent } from 'react'
import { AlertTriangle, ArrowLeft, FileSearch, Search, ShieldCheck, UserSearch } from 'lucide-react'
import { Link } from 'react-router-dom'
import { PageHeader } from '../components/PageHeader'
import { InlineLoader } from '../components/LoadingState'
import { StatusBadge } from '../components/StatusBadge'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'

export function AdvancedSearchPage() {
  const { can } = useAuth()
  const [mode, setMode] = useState('report')
  const [query, setQuery] = useState('')
  const [purpose, setPurpose] = useState('')
  const [result, setResult] = useState<unknown>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const sensitive = ['phone', 'full_name', 'national_id'].includes(mode)

  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(null); setResult(null)
    try {
      const data = sensitive
        ? await invoke('search-sensitive-customer', { lookup_type: mode, query, purpose, limit: 20 })
        : await invoke('search-records', { mode, query, limit: 25 })
      setResult(data)
    } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  return <><PageHeader eyebrow="بحث مركزي" title="البحث المتقدم" description="تُطبق صلاحيات الوصول داخل الاستعلام. لا يسمح البحث بالاسم أو الهاتف دون صلاحية بيانات حساسة وسبب وصول موثق." /><section className="advanced-search panel"><form onSubmit={submit}><label>نوع البحث<select value={mode} onChange={(event) => { setMode(event.target.value); setResult(null) }}><option value="report">رقم البلاغ</option><option value="operation">رقم العملية</option><option value="shop">اسم المحل</option><option value="imei">IMEI</option>{can('view_sensitive_data') && <><option value="phone">رقم الهاتف — حساس</option><option value="full_name">اسم العميل — حساس</option><option value="national_id">رقم الهوية — حساس</option></>}</select></label><label>عبارة البحث<input dir={mode === 'imei' || mode === 'phone' || mode === 'national_id' ? 'ltr' : undefined} value={query} onChange={(event) => setQuery(event.target.value)} minLength={2} maxLength={160} required placeholder={mode === 'imei' ? '000000000000000' : 'أدخل قيمة البحث'} /></label>{sensitive && <label>سبب الوصول<input value={purpose} onChange={(event) => setPurpose(event.target.value)} minLength={5} maxLength={500} required placeholder="مثال: مطابقة بيانات قضية مصرح بها" /></label>}<button className="primary-button" disabled={busy}>{busy ? <InlineLoader /> : <><Search size={18} />بحث</>}</button></form>{sensitive && <p className="sensitive-search-note"><ShieldCheck size={16} />تُحوّل القيمة إلى بصمة HMAC داخل وظيفة موثوقة؛ لا تُرسل قيمة بحث مكشوفة إلى قاعدة البيانات.</p>}</section>{error && <div className="inline-alert danger page-alert"><AlertTriangle size={18} />{error}</div>}{result !== null && <SearchResult mode={mode} result={result} />}</>
}

function SearchResult({ mode, result }: { mode: string; result: unknown }) {
  if (mode === 'imei' && result && typeof result === 'object' && !Array.isArray(result)) {
    const data = result as { found?: boolean; security_alert?: boolean; message_ar?: string; device?: { id: string; brand: string; model: string; status: string } | null; report?: { id: string; report_number: string } | null }
    return <section className="search-results panel"><div className="panel-heading"><div><span className="eyebrow">نتيجة الفحص</span><h2>{data.security_alert ? 'تنبيه أمني' : 'نتيجة IMEI'}</h2></div></div><p>{data.message_ar}</p>{data.device && <Link className="result-row" to={`/devices/${data.device.id}`}><FileSearch size={19} /><span>{data.device.brand} {data.device.model}</span><StatusBadge status={data.device.status} /><ArrowLeft size={17} /></Link>}{data.report && <Link className="result-row" to={`/reports/${data.report.id}`}><FileSearch size={19} /><span dir="ltr">{data.report.report_number}</span><ArrowLeft size={17} /></Link>}</section>
  }
  const entries = Array.isArray(result) ? result : result && typeof result === 'object' ? Object.entries(result as Record<string, unknown>).flatMap(([, value]) => Array.isArray(value) ? value : [value]) : []
  return <section className="search-results panel"><div className="panel-heading"><div><span className="eyebrow">نتائج ضمن النطاق</span><h2>{entries.length} نتيجة</h2></div><UserSearch size={20} /></div>{entries.length ? <div className="generic-results">{entries.map((entry, index) => { const row = entry as Record<string, unknown>; const target = typeof row.id === 'string' ? mode === 'report' ? `/reports/${row.id}` : mode === 'operation' && typeof row.device_id === 'string' ? `/devices/${row.device_id}` : null : null; const content = <><b dir="ltr">{String(row.report_number ?? row.operation_number ?? row.reference_code ?? row.shop_name ?? 'نتيجة')}</b><small>{Object.entries(row).filter(([key]) => !['id', 'report_number', 'operation_number', 'reference_code', 'shop_name'].includes(key)).map(([key, value]) => `${key}: ${String(value)}`).join(' · ')}</small></>; return target ? <Link key={index} className="result-row" to={target}><FileSearch size={18} /><span>{content}</span><ArrowLeft size={17} /></Link> : <div key={index} className="result-row"><FileSearch size={18} /><span>{content}</span></div> })}</div> : <p className="panel-empty">لم يُعثر على نتائج ضمن صلاحياتك.</p>}</section>
}
