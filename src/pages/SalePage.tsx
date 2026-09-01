import { useMemo, useState, type FormEvent } from 'react'
import { AlertTriangle, CheckCircle2, CircleDollarSign, FileUp, SearchCheck, ShieldAlert, UserRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import { InlineLoader } from '../components/LoadingState'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { isValidImei } from '../lib/imei'
import { uploadIdentityDocument } from '../lib/media'
import type { ImeiResult } from '../types/domain'

export function SalePage() {
  const { bootstrap } = useAuth()
  const shops = useMemo(() => (bootstrap?.shops ?? []).filter((shop) => shop.status === 'approved' && shop.verification_status === 'verified'), [bootstrap])
  const [shopId, setShopId] = useState(shops[0]?.id ?? '')
  const [imei, setImei] = useState('')
  const [checked, setChecked] = useState<ImeiResult | null>(null)
  const [fullName, setFullName] = useState('')
  const [phone, setPhone] = useState('')
  const [nationalId, setNationalId] = useState('')
  const [address, setAddress] = useState('')
  const [identityDocument, setIdentityDocument] = useState<File | null>(null)
  const [price, setPrice] = useState('')
  const [notes, setNotes] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [receipt, setReceipt] = useState<{ sale_number: string; device_id: string; customer_id: string; customer_reference_code: string } | null>(null)
  const [postSaveWarning, setPostSaveWarning] = useState<string | null>(null)

  async function check() {
    setError(null); setChecked(null)
    if (!isValidImei(imei)) { setError('أدخل رقم IMEI صحيحًا قبل الفحص.'); return }
    setBusy(true)
    try { setChecked(await invoke<ImeiResult>('check-imei', { imei })) } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }
  async function submit(event: FormEvent) {
    event.preventDefault(); setError(null)
    if (!checked || checked.imei !== imei || checked.security_alert) { setError('يجب فحص الجهاز أولًا، ولا يمكن تسجيل بيع لجهاز عليه تنبيه أمني.'); return }
    if (!shopId) { setError('اختر محلًا معتمدًا.'); return }
    setBusy(true)
    try {
      const result = await invoke<{ sale_number: string; device_id: string; customer_id: string; customer_reference_code: string }>('register-sale', { shop_id: shopId, imei, unit_price: price ? Number(price) : null, notes: notes || null, customer: { full_name: fullName, phone, national_id: nationalId || null, address: address || null } })
      setReceipt(result)
      if (identityDocument) {
        try {
          await uploadIdentityDocument(identityDocument, result.customer_id)
          setIdentityDocument(null)
        } catch {
          setPostSaveWarning('تم تسجيل البيع، لكن تعذر رفع مستند الهوية. يمكن للمخول استكماله من السجل وفق الإجراء المعتمد.')
        }
      }
    } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  if (receipt) return <><PageHeader eyebrow="تم التوثيق" title="تم تسجيل عملية البيع" description="سُجلت العملية في سجل الجهاز وسجل التدقيق؛ بيانات المشتري مشفرة ولا تعرض للمستخدمين غير المخولين." /><section className="success-receipt"><CheckCircle2 size={38} /><div><h2>تم إنشاء عملية بيع موثقة</h2>{postSaveWarning && <div className="inline-alert warning">{postSaveWarning}</div>}<div className="receipt-grid"><span>رقم العملية<b dir="ltr">{receipt.sale_number}</b></span><span>مرجع المشتري<b dir="ltr">{receipt.customer_reference_code}</b></span></div><Link className="primary-button" to={`/devices/${receipt.device_id}`}>عرض خط زمن الجهاز</Link></div></section></>

  return <><PageHeader eyebrow="المبيعات" title="تسجيل عملية بيع" description="افحص الجهاز أولًا. لا يسمح الخادم بإتمام البيع إن كان للجهاز بلاغ نشط أو كانت حالة المحل غير معتمدة." />{!shops.length ? <div className="inline-alert warning">لا يوجد محل معتمد مرتبط بالحساب.</div> : <form className="form-card form-grid" onSubmit={submit}><label>المحل المعتمد<select value={shopId} onChange={(event) => setShopId(event.target.value)}>{shops.map((shop) => <option key={shop.id} value={shop.id}>{shop.name}</option>)}</select></label><div className="form-span-2 check-inline"><label>رقم IMEI<input dir="ltr" inputMode="numeric" maxLength={15} value={imei} onChange={(event) => { setImei(event.target.value.replace(/\D/g, '').slice(0, 15)); setChecked(null) }} required placeholder="000000000000000" /></label><button type="button" className="secondary-button" disabled={busy} onClick={() => void check()}>{busy ? <InlineLoader /> : <><SearchCheck size={17} />فحص قبل البيع</>}</button>{checked && <span className={checked.security_alert ? 'check-result-danger' : 'check-result-good'}>{checked.security_alert ? <ShieldAlert size={17} /> : <CheckCircle2 size={17} />}{checked.security_alert ? 'تنبيه أمني — لا يمكن إتمام البيع' : 'لا يوجد بلاغ نشط'}{checked.device && <StatusBadge status={checked.device.status} />}</span>}</div><fieldset className="form-span-2 sensitive-fieldset"><legend><UserRound size={17} />بيانات المشتري المطلوبة</legend><p>تنتقل مشفرة إلى الوظيفة الموثوقة ولا تُحفظ في المتصفح أو في سجل العمليات.</p><div className="form-grid nested-grid"><label>الاسم الكامل<input value={fullName} onChange={(event) => setFullName(event.target.value)} maxLength={160} required /></label><label>رقم الهاتف<input dir="ltr" inputMode="tel" value={phone} onChange={(event) => setPhone(event.target.value)} maxLength={30} required /></label><label>رقم الهوية <span className="optional">اختياري حسب السياسة</span><input dir="ltr" value={nationalId} onChange={(event) => setNationalId(event.target.value)} maxLength={80} /></label><label>العنوان <span className="optional">اختياري</span><input value={address} onChange={(event) => setAddress(event.target.value)} maxLength={1000} /></label><label className="file-field form-span-2"><span>صورة الهوية <span className="optional">اختيارية حسب السياسة · خاصة ولا تظهر للمحل</span></span><span><FileUp size={18} />اختيار مستند<input type="file" accept="image/jpeg,image/png,application/pdf" onChange={(event) => setIdentityDocument(event.target.files?.[0] ?? null)} /></span>{identityDocument && <small>{identityDocument.name}</small>}</label></div></fieldset><label>قيمة البيع <span className="optional">اختياري</span><div className="input-with-icon"><CircleDollarSign size={17} /><input dir="ltr" type="number" min="0" step="0.01" value={price} onChange={(event) => setPrice(event.target.value)} /></div></label><label>ملاحظات <span className="optional">اختياري</span><input value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={2000} /></label>{error && <div className="inline-alert danger form-span-2"><AlertTriangle size={18} />{error}</div>}<div className="form-footer form-span-2"><span>تُنشأ العملية برقم فريد وغير قابل للحذف.</span><button className="primary-button" disabled={busy}>{busy ? <InlineLoader /> : 'تسجيل البيع'}</button></div></form>}</>
}
