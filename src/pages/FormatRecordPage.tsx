import { useMemo, useState, type FormEvent } from 'react'
import { AlertOctagon, CheckCircle2, HardDrive, SearchCheck, ShieldAlert } from 'lucide-react'
import { Link } from 'react-router-dom'
import { InlineLoader } from '../components/LoadingState'
import { PageHeader } from '../components/PageHeader'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { isValidImei } from '../lib/imei'
import type { ImeiResult } from '../types/domain'

export function FormatRecordPage() {
  const { bootstrap } = useAuth()
  const shops = useMemo(() => (bootstrap?.shops ?? []).filter((shop) => shop.status === 'approved' && shop.verification_status === 'verified'), [bootstrap])
  const [shopId, setShopId] = useState(shops[0]?.id ?? '')
  const [imei, setImei] = useState('')
  const [check, setCheck] = useState<ImeiResult | null>(null)
  const [formatType, setFormatType] = useState('إعادة ضبط المصنع')
  const [notes, setNotes] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [receipt, setReceipt] = useState<{ operation_number: string; device_id: string } | null>(null)

  async function inspect() { setError(null); if (!isValidImei(imei)) { setError('أدخل رقم IMEI صحيحًا أولًا.'); return } setBusy(true); try { setCheck(await invoke<ImeiResult>('check-imei', { imei })) } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  async function submit(event: FormEvent) { event.preventDefault(); setError(null); if (!check || check.security_alert) { setError('افحص الجهاز أولًا. لا يمكن إجراء فرمتة لجهاز مسجل عليه بلاغ نشط.'); return } setBusy(true); try { setReceipt(await invoke('create-format-record', { shop_id: shopId, imei, format_type: formatType, notes: notes || null })); } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }

  if (receipt) return <><PageHeader eyebrow="تم الحفظ" title="تم تسجيل عملية الفرمتة" description="حُفظت العملية في السجل الثابت وتغيرت حالة الجهاز عبر مسار الحالة المعتمد." /><section className="success-receipt"><CheckCircle2 size={38} /><div><h2>تم إنشاء سجل فرمتة موثّق</h2><p>رقم العملية: <b dir="ltr">{receipt.operation_number}</b></p><Link className="primary-button" to={`/devices/${receipt.device_id}`}>عرض سجل الجهاز</Link></div></section></>
  return <><PageHeader eyebrow="عمليات حساسة" title="تسجيل فرمتة" description="لا تتوفر هذه العملية دون فحص مباشر للخادم. الجهاز المبلغ عنه يوقف التدفق تلقائيًا." />{!shops.length ? <div className="inline-alert warning">لا يوجد محل معتمد مرتبط بالحساب.</div> : <form className="form-card form-grid" onSubmit={submit}><div className="form-span-2 check-inline"><label>رقم IMEI<input dir="ltr" inputMode="numeric" maxLength={15} value={imei} onChange={(event) => { setImei(event.target.value.replace(/\D/g, '').slice(0, 15)); setCheck(null) }} required /></label><button className="secondary-button" type="button" onClick={() => void inspect()} disabled={busy}>{busy ? <InlineLoader /> : <><SearchCheck size={17} />فحص الجهاز</>}</button>{check && <span className={check.security_alert ? 'check-result-danger' : 'check-result-good'}>{check.security_alert ? <ShieldAlert size={17} /> : <CheckCircle2 size={17} />}{check.security_alert ? 'تنبيه أمني — الفرمتة مرفوضة' : 'الفحص سليم'}</span>}</div><label>المحل<select value={shopId} onChange={(event) => setShopId(event.target.value)}>{shops.map((shop) => <option value={shop.id} key={shop.id}>{shop.name}</option>)}</select></label><label>نوع الفرمتة<select value={formatType} onChange={(event) => setFormatType(event.target.value)} disabled={!check || check.security_alert}><option>إعادة ضبط المصنع</option><option>تهيئة برمجية</option><option>استعادة نظام</option></select></label><label className="form-span-2">ملاحظات <span className="optional">اختياري</span><textarea rows={4} value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={3000} disabled={!check || check.security_alert} /></label>{error && <div className="inline-alert danger form-span-2"><AlertOctagon size={18} />{error}</div>}<div className="form-footer form-span-2"><span><HardDrive size={17} />لا يمكن حذف سجل الفرمتة بعد حفظه.</span><button className="primary-button" disabled={busy || !check || check.security_alert}>{busy ? <InlineLoader /> : 'تسجيل الفرمتة'}</button></div></form>}</>
}
