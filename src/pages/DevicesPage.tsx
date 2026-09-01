import { useEffect, useState } from 'react'
import { AlertTriangle, ArrowLeft, Database, Smartphone } from 'lucide-react'
import { Link } from 'react-router-dom'
import { EmptyState } from '../components/EmptyState'
import { LoadingState } from '../components/LoadingState'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { invoke, readableError } from '../lib/api'
import { useAuth } from '../contexts/AuthContext'
import { formatDate } from '../lib/format'
import type { DeviceStatus } from '../types/domain'

type DeviceRow = { id: string; brand: string; model: string; color: string | null; serial_number: string | null; status: DeviceStatus; created_at: string; imeis: Array<{ slot: number; imei: string }> }

export function DevicesPage() {
  const { can } = useAuth()
  const [devices, setDevices] = useState<DeviceRow[] | null>(null)
  const [status, setStatus] = useState('')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => { setDevices(null); setError(null); void invoke<DeviceRow[]>('get-devices', { status: status || null, limit: 50, offset: 0 }).then(setDevices).catch((caught) => setError(readableError(caught))) }, [status])

  return <><PageHeader eyebrow="سجل الهوية" title="الأجهزة" description="تظهر فقط الأجهزة الواقعة ضمن نطاق الوصول المعتمد للحساب." actions={can('create_device') ? <Link className="primary-button" to="/devices/new">تسجيل جهاز</Link> : undefined} /><div className="filter-row"><label>حالة الجهاز<select value={status} onChange={(event) => setStatus(event.target.value)}><option value="">كل الحالات</option><option value="registered">مسجل</option><option value="available">متاح</option><option value="sold">مباع</option><option value="in_repair">قيد الصيانة</option><option value="formatted">تمت الفرمتة</option><option value="flagged">تحت التنبيه</option><option value="stolen">مسروق</option><option value="recovered">مسترد</option><option value="blocked">محظور</option></select></label></div>{error ? <EmptyState icon={AlertTriangle} title="تعذر تحميل الأجهزة" description={error} /> : !devices ? <LoadingState /> : !devices.length ? <EmptyState icon={Database} title="لا توجد أجهزة ضمن النطاق" description="سجّل جهازًا جديدًا أو غيّر عامل التصفية." /> : <section className="table-panel"><div className="responsive-table"><table><thead><tr><th>الجهاز</th><th>IMEI</th><th>الحالة</th><th>تاريخ التسجيل</th><th /></tr></thead><tbody>{devices.map((device) => <tr key={device.id}><td><span className="table-icon"><Smartphone size={18} /></span><b>{device.brand} {device.model}</b>{device.color && <small>{device.color}</small>}</td><td dir="ltr">{device.imeis.map((item) => <span key={item.slot} className="imei-cell">{item.imei}{item.slot === 2 && <small> SIM 2</small>}</span>)}</td><td><StatusBadge status={device.status} /></td><td>{formatDate(device.created_at)}</td><td><Link className="table-link" to={`/devices/${device.id}`} aria-label="عرض سجل الجهاز"><ArrowLeft size={18} /></Link></td></tr>)}</tbody></table></div></section>}</>
}
