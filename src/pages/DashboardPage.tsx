import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, ArrowLeft, Building2, FileWarning, HardDrive, PlusCircle, SearchCheck, ShieldAlert, Smartphone, Wrench } from 'lucide-react'
import { Link } from 'react-router-dom'
import { PageHeader } from '../components/PageHeader'
import { EmptyState } from '../components/EmptyState'
import { LoadingState } from '../components/LoadingState'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import type { DashboardMetrics } from '../types/domain'

const metricsConfig: Array<{ key: keyof Omit<DashboardMetrics, 'period'>; label: string; icon: typeof Smartphone; accent: string }> = [
  { key: 'devices_registered', label: 'أجهزة مسجلة', icon: Smartphone, accent: 'blue' },
  { key: 'devices_sold', label: 'أجهزة مباعة', icon: PlusCircle, accent: 'teal' },
  { key: 'repair_operations', label: 'عمليات صيانة', icon: Wrench, accent: 'violet' },
  { key: 'format_operations', label: 'عمليات فرمتة', icon: HardDrive, accent: 'slate' },
  { key: 'active_reports', label: 'بلاغات نشطة', icon: FileWarning, accent: 'red' },
  { key: 'recovered_devices', label: 'أجهزة مستردة', icon: ShieldAlert, accent: 'green' },
]

export function DashboardPage() {
  const { bootstrap, can } = useAuth()
  const [metrics, setMetrics] = useState<DashboardMetrics | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    void invoke<DashboardMetrics>('get-dashboard', {}).then(setMetrics).catch((caught) => setError(readableError(caught)))
  }, [])

  const quickActions = useMemo(() => [
    can('search_imei') && { to: '/check', icon: SearchCheck, title: 'فحص الجهاز', text: 'تحقق خادمي فوري من رقم IMEI' },
    can('create_device') && { to: '/devices/new', icon: PlusCircle, title: 'تسجيل جهاز', text: 'إضافة هوية جهاز برقم IMEI' },
    can('create_sale') && { to: '/sales/new', icon: Building2, title: 'تسجيل بيع', text: 'ربط الجهاز بعملية بيع موثقة' },
    can('create_repair') && { to: '/intake', icon: Wrench, title: 'استلام وصيانة', text: 'تسجيل عملية فني برقم فريد' },
    can('create_stolen_report') && { to: '/reports?new=1', icon: AlertTriangle, title: 'فتح بلاغ', text: 'إنشاء بلاغ ضمن الصلاحيات' },
  ].filter(Boolean) as Array<{ to: string; icon: typeof SearchCheck; title: string; text: string }>, [can])

  const roleTitle = bootstrap?.roles.includes('technician') ? 'مساحة الفني' : bootstrap?.roles.some((role) => ['investigation_officer', 'authorized_officer', 'system_admin'].includes(role)) ? 'المتابعة الأمنية' : 'ملخص التشغيل'
  const visibleMetrics = metricsConfig.filter((metric) => metric.key !== 'active_reports' || can('view_all_reports') || can('update_follow_up'))

  return <>
    <PageHeader eyebrow={roleTitle} title={`أهلًا، ${bootstrap?.user.display_name ?? ''}`} description="اطّلع على مؤشرات نطاق عملك، ثم ابدأ من أسرع إجراء مطلوب." />
    {error ? <EmptyState icon={AlertTriangle} title="تعذر تحميل لوحة التحكم" description={error} action={<button className="secondary-button" onClick={() => window.location.reload()}>إعادة المحاولة</button>} /> : !metrics ? <LoadingState /> : <>
      <section className="metrics-grid">{visibleMetrics.map((metric) => { const Icon = metric.icon; return <article className={`metric-card metric-${metric.accent}`} key={metric.key}><div className="metric-icon"><Icon size={21} /></div><div><span>{metric.label}</span><strong>{Number(metrics[metric.key]).toLocaleString('ar')}</strong><small>ضمن الفترة المحددة</small></div></article> })}</section>
      <section className="dashboard-grid">
        <article className="panel activity-panel"><div className="panel-heading"><div><span className="eyebrow">إجراءات سريعة</span><h2>ابدأ عملية موثقة</h2></div></div><div className="quick-actions">{quickActions.length ? quickActions.map((action) => { const Icon = action.icon; return <Link className="quick-action" key={action.to} to={action.to}><span><Icon size={21} /></span><div><b>{action.title}</b><small>{action.text}</small></div><ArrowLeft size={17} /></Link> }) : <p className="panel-empty">لا توجد صلاحيات تشغيل ممنوحة لهذا الحساب بعد.</p>}</div></article>
        <article className="panel chart-panel"><div className="panel-heading"><div><span className="eyebrow">نظرة تشغيلية</span><h2>حجم العمليات</h2></div><span className="subdued">الفترة الحالية</span></div><div className="mini-bars">{(['devices_registered', 'devices_sold', 'repair_operations', 'format_operations', 'new_reports'] as const).map((key) => { const values = [metrics.devices_registered, metrics.devices_sold, metrics.repair_operations, metrics.format_operations, metrics.new_reports]; const max = Math.max(...values, 1); const label: Record<string, string> = { devices_registered: 'تسجيل', devices_sold: 'بيع', repair_operations: 'صيانة', format_operations: 'فرمتة', new_reports: 'بلاغات' }; return <div key={key}><span style={{ height: `${Math.max(8, Number(metrics[key]) / max * 100)}%` }} title={`${label[key]}: ${metrics[key]}`} /><small>{label[key]}</small></div> })}</div></article>
      </section>
      {(can('view_security_events') || can('manage_shops')) && <section className="security-summary">{can('view_security_events') && <div><ShieldAlert size={20} /><span><b>{metrics.suspicious_operations}</b><small>عملية أو حدث يحتاج مراجعة</small></span><Link to="/security-events">مراجعة</Link></div>}{can('manage_shops') && <div><Building2 size={20} /><span><b>{metrics.active_shops}</b><small>محل معتمد نشط</small></span><Link to="/shops">إدارة المحلات</Link></div>}</section>}
    </>}
  </>
}
