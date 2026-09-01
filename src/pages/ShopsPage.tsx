import { useEffect, useState, type FormEvent } from 'react'
import { AlertTriangle, Building2, CheckCircle2, CircleOff, Search, Store } from 'lucide-react'
import { EmptyState } from '../components/EmptyState'
import { InlineLoader, LoadingState } from '../components/LoadingState'
import { Modal } from '../components/Modal'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { formatDate } from '../lib/format'
import type { Shop } from '../types/domain'

export function ShopsPage() {
  const { can } = useAuth()
  const [shops, setShops] = useState<Shop[] | null>(null)
  const [status, setStatus] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [suspending, setSuspending] = useState<Shop | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)

  const load = () => { setShops(null); setError(null); void invoke<Shop[]>('get-shops', { status: status || null, limit: 100, offset: 0 }).then(setShops).catch((caught) => setError(readableError(caught))) }
  useEffect(load, [status]) // eslint-disable-line react-hooks/exhaustive-deps
  async function approve(shop: Shop) { setBusyId(shop.id); try { await invoke('approve-shop', { shop_id: shop.id }); load() } catch (caught) { setError(readableError(caught)) } finally { setBusyId(null) } }

  return <><PageHeader eyebrow="إدارة الاعتماد" title="المحلات" description="إيقاف المحل يمنع العمليات الجديدة فورًا مع الاحتفاظ الكامل بالتاريخ السابق." /><section className="filter-row"><Search size={17} /><label>الحالة<select value={status} onChange={(event) => setStatus(event.target.value)}><option value="">كل الحالات</option><option value="pending">بانتظار الاعتماد</option><option value="approved">معتمد</option><option value="suspended">موقوف</option><option value="rejected">مرفوض</option></select></label></section>{error && <div className="inline-alert danger page-alert">{error}</div>}{!shops ? <LoadingState /> : !shops.length ? <EmptyState icon={Store} title="لا توجد محلات ضمن النطاق" description="ستظهر طلبات المحلات المتاحة لك هنا." /> : <section className="shop-grid">{shops.map((shop) => <article className="shop-card" key={shop.id}><div className="shop-card-icon"><Building2 size={22} /></div><div className="shop-card-main"><div><h2>{shop.shop_name}</h2>{shop.commercial_name && <p>{shop.commercial_name}</p>}</div><div className="badges"><StatusBadge status={shop.status} />{shop.verification_status === 'verified' && <span className="verified-mini"><CheckCircle2 size={14} />موثق</span>}</div><small>قُدم في {formatDate(shop.created_at)}</small>{shop.suspension_reason && <p className="suspension-reason">سبب الإيقاف: {shop.suspension_reason}</p>}</div><div className="shop-card-actions">{shop.status === 'pending' && can('approve_shop') && <button className="primary-button small-button" disabled={busyId === shop.id} onClick={() => void approve(shop)}>{busyId === shop.id ? <InlineLoader /> : 'اعتماد'}</button>}{shop.status === 'approved' && can('suspend_shop') && <button className="danger-outline-button small-button" onClick={() => setSuspending(shop)}><CircleOff size={16} />إيقاف</button>}</div></article>)}</section>}{suspending && <SuspendShopModal shop={suspending} onClose={() => setSuspending(null)} onDone={() => { setSuspending(null); load() }} />}</>
}

function SuspendShopModal({ shop, onClose, onDone }: { shop: Shop; onClose: () => void; onDone: () => void }) {
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); setError(null); try { await invoke('suspend-shop', { shop_id: shop.id, reason }); onDone() } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  return <Modal title="إيقاف محل" onClose={onClose}><p className="modal-intro">سيُمنع المحل من تسجيل عمليات أو أجهزة جديدة، ولن يُحذف تاريخه السابق.</p><form className="form-stack" onSubmit={submit}><label>المحل<b>{shop.shop_name}</b></label><label>سبب الإيقاف<textarea rows={4} value={reason} onChange={(event) => setReason(event.target.value)} minLength={5} maxLength={1000} required /></label>{error && <div className="inline-alert danger">{error}</div>}<div className="modal-actions"><button className="secondary-button" type="button" onClick={onClose}>إلغاء</button><button className="danger-button" disabled={busy}>{busy ? <InlineLoader /> : 'تأكيد الإيقاف'}</button></div></form></Modal>
}
