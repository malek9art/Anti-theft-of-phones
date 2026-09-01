import { useEffect, useState } from 'react'
import { AlertTriangle, BellRing, CheckCircle2, ShieldAlert } from 'lucide-react'
import { EmptyState } from '../components/EmptyState'
import { InlineLoader, LoadingState } from '../components/LoadingState'
import { PageHeader } from '../components/PageHeader'
import { SeverityBadge } from '../components/StatusBadge'
import { invoke, readableError } from '../lib/api'
import { formatDate } from '../lib/format'
import type { SecurityEvent } from '../types/domain'

const labels: Record<string, string> = { high_volume_imei_search: 'كثافة غير معتادة في فحص IMEI', repeated_reported_device_search: 'تكرار فحص جهاز مُبلغ عنه', attempted_repair_of_reported_device: 'محاولة صيانة جهاز عليه بلاغ', attempted_format_of_reported_device: 'محاولة فرمتة جهاز عليه بلاغ', stolen_report_submitted: 'بلاغ سرقة جديد', failed_login: 'محاولة دخول فاشلة', suspicious_login: 'دخول يحتاج مراجعة' }

export function SecurityEventsPage() {
  const [events, setEvents] = useState<SecurityEvent[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const load = () => { setEvents(null); void invoke<SecurityEvent[]>('get-security-events', { limit: 100, unresolved_only: true }).then(setEvents).catch((caught) => setError(readableError(caught))) }
  useEffect(load, []) // eslint-disable-line react-hooks/exhaustive-deps
  async function resolve(id: string) { setBusy(id); try { await invoke('resolve-security-event', { event_id: id }); setEvents((current) => current?.filter((event) => event.id !== id) ?? null) } catch (caught) { setError(readableError(caught)) } finally { setBusy(null) } }
  return <><PageHeader eyebrow="مراقبة استباقية" title="الأمن والتنبيهات" description="ترصد المنصة الأنماط غير الطبيعية وتوجهها للمراجعة؛ لا تُعلق الحسابات تلقائيًا إلا وفق سياسة صريحة." />{error && <div className="inline-alert danger page-alert">{error}</div>}{!events ? <LoadingState /> : !events.length ? <EmptyState icon={CheckCircle2} title="لا توجد أحداث أمنية غير معالجة" description="لا تزال جميع عمليات الحظر والرفض مسجلة في سجل التدقيق." /> : <section className="security-events-list">{events.map((event) => <article key={event.id} className={`security-event severity-${event.severity}`}><span><ShieldAlert size={24} /></span><div><h2>{labels[event.event_type] ?? event.event_type}</h2><p>{Object.keys(event.metadata).length ? Object.entries(event.metadata).map(([key, value]) => `${key}: ${String(value)}`).join(' · ') : 'لا توجد تفاصيل إضافية معروضة.'}</p><small>{formatDate(event.created_at)}</small></div><SeverityBadge severity={event.severity} /><button className="secondary-button small-button" disabled={busy === event.id} onClick={() => void resolve(event.id)}>{busy === event.id ? <InlineLoader /> : <><BellRing size={16} />تمت المراجعة</>}</button></article>)}</section>}</>
}
