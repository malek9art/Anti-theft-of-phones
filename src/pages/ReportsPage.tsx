import { useEffect, useState, type FormEvent } from 'react'
import { AlertTriangle, FilePlus2, FileWarning, Filter, Plus, SearchCheck } from 'lucide-react'
import { Link, useSearchParams } from 'react-router-dom'
import { EmptyState } from '../components/EmptyState'
import { InlineLoader, LoadingState } from '../components/LoadingState'
import { Modal } from '../components/Modal'
import { PageHeader } from '../components/PageHeader'
import { SeverityBadge, StatusBadge } from '../components/StatusBadge'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { formatDate } from '../lib/format'
import { isValidImei } from '../lib/imei'
import type { ReportStatus, ReportSummary } from '../types/domain'

const statuses: Array<{ value: ReportStatus | ''; label: string }> = [
  { value: '', label: 'كل الحالات' }, { value: 'submitted', label: 'مقدّم' }, { value: 'under_review', label: 'قيد المراجعة' },
  { value: 'verified', label: 'تم التحقق' }, { value: 'active', label: 'نشط' }, { value: 'assigned', label: 'مُحال' },
  { value: 'recovered', label: 'مسترد' }, { value: 'closed', label: 'مغلق' }, { value: 'rejected', label: 'مرفوض' },
]

export function ReportsPage() {
  const { can } = useAuth()
  const [searchParams, setSearchParams] = useSearchParams()
  const [reports, setReports] = useState<ReportSummary[] | null>(null)
  const [status, setStatus] = useState<ReportStatus | ''>('')
  const [newOpen, setNewOpen] = useState(searchParams.get('new') === '1')
  const [error, setError] = useState<string | null>(null)

  function load() { setReports(null); setError(null); void invoke<ReportSummary[]>('get-reports', { status: status || null, limit: 50, offset: 0 }).then(setReports).catch((caught) => setError(readableError(caught))) }
  useEffect(load, [status]) // eslint-disable-line react-hooks/exhaustive-deps
  function closeModal() { setNewOpen(false); setSearchParams({}) }

  return <><PageHeader eyebrow="Stolen Reports" title="البلاغات" description="إدارة دورة البلاغ ضمن الصلاحيات؛ لا تظهر هوية المبلّغ أو أدلته من هذه القائمة." actions={can('create_stolen_report') ? <button className="primary-button" onClick={() => setNewOpen(true)}><Plus size={18} />بلاغ جديد</button> : undefined} /><section className="filter-row"><Filter size={17} /><label>الحالة<select value={status} onChange={(event) => setStatus(event.target.value as ReportStatus | '')}>{statuses.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label></section>{error ? <EmptyState icon={AlertTriangle} title="تعذر تحميل البلاغات" description={error} /> : !reports ? <LoadingState /> : !reports.length ? <EmptyState icon={FileWarning} title="لا توجد بلاغات ضمن النطاق" description="ستظهر البلاغات المحولة إليك أو المخولة لك هنا." action={can('create_stolen_report') ? <button className="secondary-button" onClick={() => setNewOpen(true)}>فتح بلاغ</button> : undefined} /> : <section className="report-list">{reports.map((report) => <Link to={`/reports/${report.id}`} className="report-row" key={report.id}><span className="report-icon"><FileWarning size={21} /></span><div><b dir="ltr">{report.report_number}</b><p>{report.report_type} · IMEI ينتهي بـ <strong dir="ltr">{report.imei_last4}</strong></p><small>{formatDate(report.created_at)}</small></div><div className="report-row-status"><SeverityBadge severity={report.priority} /><StatusBadge status={report.status} /></div></Link>)}</section>}{newOpen && <NewReportModal onClose={closeModal} onCreated={() => { closeModal(); load() }} />}</>
}

function NewReportModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [imei, setImei] = useState('')
  const [imei2, setImei2] = useState('')
  const [brand, setBrand] = useState('')
  const [model, setModel] = useState('')
  const [reportType, setReportType] = useState('سرقة جهاز')
  const [incidentAt, setIncidentAt] = useState(new Date().toISOString().slice(0, 16))
  const [priority, setPriority] = useState('normal')
  const [description, setDescription] = useState('')
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [nationalId, setNationalId] = useState('')
  const [address, setAddress] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault(); setError(null)
    if (!isValidImei(imei) || (imei2 && !isValidImei(imei2)) || imei === imei2) { setError('تحقق من رقم IMEI. يجب أن يمر رقم مكون من 15 رقمًا بخوارزمية Luhn.'); return }
    setBusy(true)
    try {
      await invoke('create-stolen-report', { imei, imei2: imei2 || null, brand: brand || null, model: model || null, report_type: reportType, incident_at: new Date(incidentAt).toISOString(), priority, description, reporter: { full_name: name, phone, national_id: nationalId || null, address: address || null } })
      onCreated()
    } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  return <Modal title="إنشاء بلاغ سرقة" onClose={onClose} wide><p className="modal-intro">تُشفّر بيانات المبلّغ داخل وظيفة موثوقة. سيصبح الجهاز تحت تنبيه فوري بمجرد تقديم البلاغ.</p><form className="form-grid" onSubmit={submit}><label>IMEI 1<input dir="ltr" inputMode="numeric" maxLength={15} value={imei} onChange={(event) => setImei(event.target.value.replace(/\D/g, '').slice(0, 15))} required /></label><label>IMEI 2 <span className="optional">اختياري</span><input dir="ltr" inputMode="numeric" maxLength={15} value={imei2} onChange={(event) => setImei2(event.target.value.replace(/\D/g, '').slice(0, 15))} /></label><label>نوع البلاغ<input value={reportType} onChange={(event) => setReportType(event.target.value)} required maxLength={100} /></label><label>تاريخ ووقت الواقعة<input type="datetime-local" dir="ltr" value={incidentAt} onChange={(event) => setIncidentAt(event.target.value)} required /></label><label>الأولوية<select value={priority} onChange={(event) => setPriority(event.target.value)}><option value="low">منخفضة</option><option value="normal">عادية</option><option value="high">مرتفعة</option><option value="critical">حرجة</option></select></label><label>العلامة والموديل <span className="optional">للجهاز غير المسجل</span><div className="dual-input"><input value={brand} onChange={(event) => setBrand(event.target.value)} placeholder="العلامة" maxLength={100} /><input value={model} onChange={(event) => setModel(event.target.value)} placeholder="الموديل" maxLength={160} /></div></label><label className="form-span-2">وصف الواقعة<textarea rows={4} value={description} onChange={(event) => setDescription(event.target.value)} minLength={5} maxLength={6000} required /></label><fieldset className="form-span-2 sensitive-fieldset"><legend>بيانات المبلّغ</legend><p>محمية بالتشفير ولا تظهر للمستخدمين غير المخولين.</p><div className="form-grid nested-grid"><label>الاسم الكامل<input value={name} onChange={(event) => setName(event.target.value)} required maxLength={160} /></label><label>رقم الهاتف<input dir="ltr" value={phone} onChange={(event) => setPhone(event.target.value)} required maxLength={30} /></label><label>رقم الهوية <span className="optional">حسب السياسة</span><input dir="ltr" value={nationalId} onChange={(event) => setNationalId(event.target.value)} maxLength={80} /></label><label>العنوان <span className="optional">اختياري</span><input value={address} onChange={(event) => setAddress(event.target.value)} maxLength={1000} /></label></div></fieldset>{error && <div className="inline-alert danger form-span-2"><AlertTriangle size={18} />{error}</div>}<div className="modal-actions form-span-2"><button type="button" className="secondary-button" onClick={onClose}>إلغاء</button><button className="danger-button" disabled={busy}>{busy ? <InlineLoader /> : <><FilePlus2 size={17} />تقديم البلاغ</>}</button></div></form></Modal>
}
