import { useEffect, useState } from 'react'
import { AlertTriangle, BookOpenCheck, Fingerprint, Link2 } from 'lucide-react'
import { EmptyState } from '../components/EmptyState'
import { LoadingState } from '../components/LoadingState'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { invoke, readableError } from '../lib/api'
import { compactId, formatDate } from '../lib/format'
import type { AuditLog } from '../types/domain'

const actionLabels: Record<string, string> = {
  create_device: 'تسجيل جهاز', search_imei: 'فحص IMEI', create_sale: 'تسجيل بيع', create_repair: 'تسجيل صيانة',
  create_format_record: 'تسجيل فرمتة', create_report: 'إنشاء بلاغ', change_report_status: 'تغيير حالة بلاغ',
  upload_evidence: 'رفع دليل', view_evidence: 'عرض دليل', view_sensitive_data: 'عرض بيانات حساسة', approve_shop: 'اعتماد محل',
  suspend_shop: 'إيقاف محل', change_permission: 'تغيير صلاحية', export_report: 'تصدير تقرير', login: 'تسجيل دخول', logout: 'تسجيل خروج',
}

export function AuditLogsPage() {
  const [logs, setLogs] = useState<AuditLog[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => { void invoke<AuditLog[]>('get-audit-logs', { limit: 100 }).then(setLogs).catch((caught) => setError(readableError(caught))) }, [])
  return <><PageHeader eyebrow="Tamper-evident ledger" title="سجل التدقيق" description="سجل append-only متسلسل بسلسلة تجزئة SHA-256. لا يمكن للمستخدمين حذفه أو تعديله." />{error ? <EmptyState icon={AlertTriangle} title="تعذر تحميل سجل التدقيق" description={error} /> : !logs ? <LoadingState /> : !logs.length ? <EmptyState icon={BookOpenCheck} title="لا توجد أحداث تدقيق بعد" description="ستظهر العمليات الحساسة ونتائجها هنا." /> : <section className="audit-list">{logs.map((log) => <article key={log.id} className="audit-row"><span className="audit-sequence">#{log.sequence_number}</span><Fingerprint size={20} /><div><b>{actionLabels[log.action] ?? log.action}</b><p>{log.entity_type} · {compactId(log.entity_id)} · {log.actor_roles.join('، ') || 'نظام'}</p><small>{formatDate(log.occurred_at)}</small></div><div className="audit-proof"><StatusBadge status={log.result === 'success' ? 'available' : log.result === 'denied' ? 'blocked' : 'flagged'} label={log.result === 'success' ? 'نجاح' : log.result === 'denied' ? 'مرفوض' : 'فشل'} /><span title={log.entry_hash}><Link2 size={14} />{log.entry_hash.slice(0, 12)}…</span></div></article>)}</section>}</>
}
