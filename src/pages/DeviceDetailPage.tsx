import { useEffect, useState } from 'react'
import { AlertTriangle, ArrowRight, CalendarDays, Clock3, History, Smartphone } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import { EmptyState } from '../components/EmptyState'
import { LoadingState } from '../components/LoadingState'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { invoke, readableError } from '../lib/api'
import { formatDate } from '../lib/format'
import type { DeviceTimeline } from '../types/domain'

const eventLabels: Record<string, string> = {
  device_registered: 'تم تسجيل الجهاز', device_registered_from_report: 'تم تسجيل الجهاز ضمن بلاغ', device_sold: 'تم بيع الجهاز',
  device_in_repair: 'دخل الجهاز إلى الصيانة', repair_registered: 'تم تسجيل عملية صيانة', device_formatted: 'تمت فرمتة الجهاز',
  device_reported: 'تم فتح بلاغ على الجهاز', report_submitted: 'تم تقديم بلاغ', report_status_changed: 'تم تحديث حالة البلاغ',
  report_verified_or_active: 'تم تفعيل التنبيه الأمني', report_assigned: 'تم تعيين متابعة للبلاغ', report_follow_up_added: 'تمت إضافة متابعة',
  device_recovered: 'تم تسجيل استرداد الجهاز', device_photo_uploaded: 'تم رفع صورة للجهاز', report_closed_without_activation: 'تم إنهاء التنبيه',
}

export function DeviceDetailPage() {
  const { id } = useParams()
  const [timeline, setTimeline] = useState<DeviceTimeline | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loadingMore, setLoadingMore] = useState(false)

  useEffect(() => { if (!id) return; setTimeline(null); setError(null); void invoke<DeviceTimeline>('get-device-timeline', { device_id: id, limit: 40 }).then(setTimeline).catch((caught) => setError(readableError(caught))) }, [id])
  async function loadMore() {
    if (!id || !timeline?.events.length) return
    setLoadingMore(true)
    try { const next = await invoke<DeviceTimeline>('get-device-timeline', { device_id: id, limit: 40, before: timeline.events[timeline.events.length - 1].occurred_at }); setTimeline((current) => current ? { ...current, events: [...current.events, ...next.events] } : next) } catch (caught) { setError(readableError(caught)) } finally { setLoadingMore(false) }
  }

  if (error) return <><Link className="back-link" to="/devices"><ArrowRight size={17} />العودة للأجهزة</Link><EmptyState icon={AlertTriangle} title="تعذر فتح سجل الجهاز" description={error} /></>
  if (!timeline) return <LoadingState label="جارٍ تحميل خط الزمن…" />
  const { device, events } = timeline
  return <><Link className="back-link" to="/devices"><ArrowRight size={17} />العودة للأجهزة</Link><PageHeader eyebrow="هوية الجهاز وسجل عملياته" title={`${device.brand} ${device.model}`} description={`IMEI 1: ${device.imeis[0]?.imei ?? '—'}`} actions={<StatusBadge status={device.status} />} /><section className="device-overview panel"><div className="device-illustration"><Smartphone size={36} /></div><div><span className="eyebrow">بيانات عامة</span><h2>{device.brand} {device.model}</h2><p>{device.color ?? 'لم يُسجل اللون'} · {device.serial_number ? `الرقم التسلسلي: ${device.serial_number}` : 'لا يوجد رقم تسلسلي مسجل'}</p></div><div className="imei-pills">{device.imeis.map((item) => <span key={item.slot}><small>IMEI {item.slot}</small><b dir="ltr">{item.imei}</b></span>)}</div></section><section className="timeline-panel panel"><div className="panel-heading"><div><span className="eyebrow">سجل غير قابل للحذف</span><h2>خط زمن الجهاز</h2></div><span className="subdued"><History size={16} />{events.length} حدث ظاهر</span></div>{events.length ? <ol className="timeline">{events.map((event) => <li key={event.id}><span className="timeline-dot" /><div className="timeline-content"><div><b>{eventLabels[event.event_type] ?? event.event_type}</b>{event.operation_number && <span className="operation-tag" dir="ltr">{event.operation_number}</span>}</div>{event.notes && <p>{event.notes}</p>}<small><CalendarDays size={14} />{formatDate(event.occurred_at)}{event.shop_id && ' · عملية ضمن محل معتمد'}</small></div></li>)}</ol> : <EmptyState icon={Clock3} title="لا توجد أحداث إضافية" description="سيظهر تاريخ الجهاز هنا عند تسجيل العمليات." />}{events.length >= 40 && <button className="secondary-button centered-button" onClick={() => void loadMore()} disabled={loadingMore}>{loadingMore ? 'جارٍ التحميل…' : 'تحميل أحداث أقدم'}</button>}</section></>
}
