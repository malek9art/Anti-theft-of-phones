import { useEffect, useState, type FormEvent } from 'react'
import { AlertTriangle, ArrowRight, CheckCircle2, ClipboardPenLine, Eye, FileUp, History, MapPin, Save, Send, UserRoundCheck } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import { EmptyState } from '../components/EmptyState'
import { InlineLoader, LoadingState } from '../components/LoadingState'
import { Modal } from '../components/Modal'
import { PageHeader } from '../components/PageHeader'
import { SeverityBadge, StatusBadge } from '../components/StatusBadge'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { bytes, compactId, formatDate } from '../lib/format'
import { reportStatusLabel } from '../lib/imei'
import { uploadEvidence } from '../lib/media'
import type { ReportDetail, ReportStatus } from '../types/domain'

const transitions: Partial<Record<ReportStatus, ReportStatus[]>> = {
  draft: ['submitted', 'cancelled'], submitted: ['under_review', 'rejected', 'cancelled'], under_review: ['verified', 'rejected', 'cancelled'],
  verified: ['active', 'assigned', 'rejected'], active: ['assigned', 'recovered', 'closed'], assigned: ['active', 'recovered', 'closed'], recovered: ['closed'],
}

export function ReportDetailPage() {
  const { id } = useParams()
  const { can } = useAuth()
  const [detail, setDetail] = useState<ReportDetail | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [status, setStatus] = useState<ReportStatus | ''>('')
  const [note, setNote] = useState('')
  const [followUp, setFollowUp] = useState('')
  const [evidenceFile, setEvidenceFile] = useState<File | null>(null)
  const [evidenceDescription, setEvidenceDescription] = useState('')
  const [busy, setBusy] = useState(false)
  const [viewEvidence, setViewEvidence] = useState<{ id: string; name: string } | null>(null)
  const [purpose, setPurpose] = useState('')
  const [assignees, setAssignees] = useState<Array<{ id: string; display_name: string; role: 'officer' | 'delegate' }>>([])
  const [officerId, setOfficerId] = useState('')
  const [delegateId, setDelegateId] = useState('')
  const [assignmentNote, setAssignmentNote] = useState('')

  const load = () => { if (!id) return; setDetail(null); setError(null); void invoke<ReportDetail>('get-report-detail', { report_id: id }).then(setDetail).catch((caught) => setError(readableError(caught))) }
  useEffect(load, [id]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    setAssignees([])
    setOfficerId('')
    setDelegateId('')
    if (id && can('assign_case')) {
      void invoke<Array<{ id: string; display_name: string; role: 'officer' | 'delegate' }>>('get-case-assignees', { report_id: id })
        .then(setAssignees)
        .catch(() => undefined)
    }
  }, [can, id])

  async function changeStatus(event: FormEvent) { event.preventDefault(); if (!id || !status) return; setBusy(true); setError(null); try { await invoke('update-report-status', { report_id: id, status, note: note || null }); setStatus(''); setNote(''); load() } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  async function addFollowUp(event: FormEvent) { event.preventDefault(); if (!id) return; setBusy(true); setError(null); try { await invoke('add-report-follow-up', { report_id: id, note: followUp }); setFollowUp(''); load() } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  async function assignCase(event: FormEvent) { event.preventDefault(); if (!id || (!officerId && !delegateId)) return; setBusy(true); setError(null); try { await invoke('assign-report', { report_id: id, assigned_officer_id: officerId || null, assigned_delegate_id: delegateId || null, note: assignmentNote || null }); setAssignmentNote(''); load() } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  async function upload(event: FormEvent) { event.preventDefault(); if (!id || !evidenceFile) return; setBusy(true); setError(null); try { await uploadEvidence(evidenceFile, id, 'مرفق بلاغ', evidenceDescription, 'restricted'); setEvidenceFile(null); setEvidenceDescription(''); load() } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  async function openEvidence(event: FormEvent) { event.preventDefault(); if (!viewEvidence) return; setBusy(true); setError(null); try { const data = await invoke<{ signed_url: string }>('get-evidence-url', { evidence_id: viewEvidence.id, purpose }); const link = document.createElement('a'); link.href = data.signed_url; link.target = '_blank'; link.rel = 'noopener noreferrer'; document.body.appendChild(link); link.click(); link.remove(); setViewEvidence(null); setPurpose('') } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }

  if (error && !detail) return <><Link className="back-link" to="/reports"><ArrowRight size={17} />العودة للبلاغات</Link><EmptyState icon={AlertTriangle} title="تعذر فتح البلاغ" description={error} /></>
  if (!detail) return <LoadingState label="جارٍ تحميل تفاصيل البلاغ…" />
  const { report } = detail
  const allowedTransitions = transitions[report.status] ?? []

  return <><Link className="back-link" to="/reports"><ArrowRight size={17} />العودة للبلاغات</Link><PageHeader eyebrow="Stolen Report" title={report.report_number} description={`IMEI: ${report.imei_snapshot}`} actions={<><SeverityBadge severity={report.priority} /><StatusBadge status={report.status} /></>} />{error && <div className="inline-alert danger page-alert">{error}</div>}<section className="case-summary panel"><div><span className="eyebrow">بيانات القضية المصرح بها</span><h2>{report.report_type}</h2><p>{report.description}</p></div><dl><div><dt>تاريخ الواقعة</dt><dd>{formatDate(report.incident_at)}</dd></div><div><dt>IMEI 1</dt><dd dir="ltr">{report.imei_snapshot}</dd></div>{report.imei2_snapshot && <div><dt>IMEI 2</dt><dd dir="ltr">{report.imei2_snapshot}</dd></div>}<div><dt>الجهاز</dt><dd><Link to={`/devices/${report.device_id}`}>عرض سجل الجهاز</Link></dd></div></dl></section><section className="case-grid"><article className="panel"><div className="panel-heading"><div><span className="eyebrow">الحالة</span><h2>تسلسل البلاغ</h2></div><History size={20} /></div><ol className="status-history">{detail.status_history.map((item) => <li key={item.id}><span /><div><b>{item.from_status ? `${reportStatusLabel[item.from_status]} ← ` : ''}{reportStatusLabel[item.to_status]}</b>{item.note && <p>{item.note}</p>}<small>{formatDate(item.changed_at)} · {compactId(item.changed_by)}</small></div></li>)}</ol>{can('change_report_status') && allowedTransitions.length > 0 && <form className="compact-form" onSubmit={changeStatus}><label>تحديث الحالة<select value={status} onChange={(event) => setStatus(event.target.value as ReportStatus)} required><option value="">اختر الإجراء</option>{allowedTransitions.map((next) => <option key={next} value={next}>{reportStatusLabel[next]}</option>)}</select></label><label>ملاحظة <span className="optional">اختياري</span><input value={note} onChange={(event) => setNote(event.target.value)} maxLength={3000} /></label><button className="primary-button" disabled={busy || !status}>{busy ? <InlineLoader /> : <><Save size={17} />حفظ التحديث</>}</button></form>}</article><article className="panel"><div className="panel-heading"><div><span className="eyebrow">متابعة ميدانية</span><h2>إجراءات المتابعة</h2></div><MapPin size={20} /></div>{detail.follow_ups.length ? <div className="follow-up-list">{detail.follow_ups.map((item) => <div key={item.id}><ClipboardPenLine size={17} /><span><p>{item.note}</p><small>{formatDate(item.created_at)}</small></span></div>)}</div> : <p className="panel-empty">لم تُسجل متابعة بعد.</p>}{can('update_follow_up') && <form className="compact-form" onSubmit={addFollowUp}><label>إضافة متابعة<textarea rows={3} value={followUp} onChange={(event) => setFollowUp(event.target.value)} minLength={5} maxLength={3000} required /></label><button className="secondary-button" disabled={busy}>{busy ? <InlineLoader /> : <><Send size={17} />إضافة متابعة</>}</button></form>}</article></section>{can('assign_case') && <section className="panel assignment-panel"><div className="panel-heading"><div><span className="eyebrow">تحويل القضية</span><h2>تعيين موظف أو مندوب</h2></div><UserRoundCheck size={20} /></div><form className="assignment-form" onSubmit={assignCase}><label>الموظف المختص<select value={officerId} onChange={(event) => setOfficerId(event.target.value)}><option value="">دون تعيين</option>{assignees.filter((person) => person.role === 'officer').map((person) => <option key={person.id} value={person.id}>{person.display_name}</option>)}</select></label><label>المندوب<select value={delegateId} onChange={(event) => setDelegateId(event.target.value)}><option value="">دون تعيين</option>{assignees.filter((person) => person.role === 'delegate').map((person) => <option key={person.id} value={person.id}>{person.display_name}</option>)}</select></label><label>ملاحظة <span className="optional">اختياري</span><input value={assignmentNote} onChange={(event) => setAssignmentNote(event.target.value)} maxLength={3000} /></label><button className="secondary-button" disabled={busy || (!officerId && !delegateId)}>{busy ? <InlineLoader /> : 'تأكيد التعيين'}</button></form></section>}<section className="panel evidence-panel"><div className="panel-heading"><div><span className="eyebrow">Private Evidence</span><h2>الأدلة والمرفقات</h2></div><FileUp size={20} /></div>{detail.evidence.length ? <div className="evidence-list">{detail.evidence.map((evidence) => <div key={evidence.id}><FileUp size={19} /><span><b>{evidence.original_name}</b><small>{evidence.evidence_type} · {bytes(evidence.size_bytes)} · {formatDate(evidence.uploaded_at)}</small>{evidence.description && <small>{evidence.description}</small>}</span><SeverityBadge severity={evidence.access_level === 'sealed' ? 'critical' : evidence.access_level === 'investigation' ? 'important' : 'info'} />{can('view_evidence') && <button className="icon-button" onClick={() => setViewEvidence({ id: evidence.id, name: evidence.original_name })} aria-label={`فتح ${evidence.original_name}`}><Eye size={18} /></button>}</div>)}</div> : <p className="panel-empty">لا توجد أدلة مرفوعة متاحة لك.</p>}{can('upload_evidence') && <form className="upload-evidence-form" onSubmit={upload}><label className="file-field"><span>إرفاق دليل <span className="optional">صورة أو PDF، حتى 15MB</span></span><span><FileUp size={18} />اختيار ملف<input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" onChange={(event) => setEvidenceFile(event.target.files?.[0] ?? null)} required /></span>{evidenceFile && <small>{evidenceFile.name}</small>}</label><label>وصف الدليل<input value={evidenceDescription} onChange={(event) => setEvidenceDescription(event.target.value)} maxLength={3000} required /></label><button className="secondary-button" disabled={busy || !evidenceFile}>{busy ? <InlineLoader /> : 'رفع إلى التخزين الخاص'}</button></form>}</section>{viewEvidence && <Modal title="سبب الاطلاع على الدليل" onClose={() => setViewEvidence(null)}><p className="modal-intro">سيُنشأ رابط مؤقت فقط، وتسجل عملية العرض مع السبب في سجل الأدلة.</p><form className="form-stack" onSubmit={openEvidence}><label>الدليل<b>{viewEvidence.name}</b></label><label>سبب الوصول<textarea rows={3} minLength={5} maxLength={500} value={purpose} onChange={(event) => setPurpose(event.target.value)} required placeholder="مثال: مراجعة أدلة القضية قبل اتخاذ إجراء" /></label><div className="modal-actions"><button type="button" className="secondary-button" onClick={() => setViewEvidence(null)}>إلغاء</button><button className="primary-button" disabled={busy}>{busy ? <InlineLoader /> : <><Eye size={17} />فتح الرابط المؤقت</>}</button></div></form></Modal>}</>
}
