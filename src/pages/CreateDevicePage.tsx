import { useMemo, useState, type FormEvent } from 'react'
import { CheckCircle2, ImagePlus, ShieldCheck, Smartphone } from 'lucide-react'
import { Link } from 'react-router-dom'
import { InlineLoader } from '../components/LoadingState'
import { PageHeader } from '../components/PageHeader'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { isValidImei } from '../lib/imei'
import { uploadDeviceImage } from '../lib/media'

export function CreateDevicePage() {
  const { bootstrap } = useAuth()
  const shops = useMemo(() => (bootstrap?.shops ?? []).filter((shop) => shop.status === 'approved' && shop.verification_status === 'verified'), [bootstrap])
  const [shopId, setShopId] = useState(shops[0]?.id ?? '')
  const [brand, setBrand] = useState('')
  const [model, setModel] = useState('')
  const [color, setColor] = useState('')
  const [serial, setSerial] = useState('')
  const [imei1, setImei1] = useState('')
  const [imei2, setImei2] = useState('')
  const [photos, setPhotos] = useState<File[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [created, setCreated] = useState<{ device_id: string; imei1: string } | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault(); setError(null); setCreated(null)
    if (!shopId) { setError('اختر محلًا معتمدًا قبل تسجيل الجهاز.'); return }
    if (!isValidImei(imei1) || (imei2 && !isValidImei(imei2)) || imei1 === imei2) { setError('تحقق من رقم IMEI الأول والثاني باستخدام رقم تحقق صحيح.'); return }
    setBusy(true)
    try {
      const result = await invoke<{ device_id: string; imei1: string }>('create-device', { shop_id: shopId, brand, model, color: color || null, serial_number: serial || null, imei1, imei2: imei2 || null })
      for (const photo of photos) await uploadDeviceImage(photo, result.device_id)
      setCreated(result)
      setPhotos([])
    } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  if (created) return <><PageHeader eyebrow="تم الحفظ" title="تم تسجيل الجهاز بنجاح" description="حُفظت هوية الجهاز وسجّل النظام العملية في خط الزمن وسجل التدقيق." /><section className="success-receipt"><CheckCircle2 size={38} /><div><h2>تم إنشاء سجل جهاز موثوق</h2><p>IMEI: <b dir="ltr">{created.imei1}</b></p><div className="result-actions"><Link className="primary-button" to={`/devices/${created.device_id}`}>عرض سجل الجهاز</Link><button className="secondary-button" onClick={() => { setCreated(null); setImei1(''); setImei2(''); setBrand(''); setModel('') }}>تسجيل جهاز آخر</button></div></div></section></>

  return <><PageHeader eyebrow="سجل الهوية" title="تسجيل جهاز جديد" description="يتحقق الخادم من صحة IMEI بخوارزمية Luhn ومن عدم تكراره قبل حفظ أي سجل." />{!shops.length ? <section className="inline-alert warning"><ShieldCheck size={19} />لا يوجد محل معتمد مرتبط بالحساب. لا يمكن تسجيل أجهزة حتى اعتماد المحل.</section> : <form className="form-card form-grid" onSubmit={submit}><label>المحل المعتمد<select value={shopId} onChange={(event) => setShopId(event.target.value)} required>{shops.map((shop) => <option value={shop.id} key={shop.id}>{shop.name}</option>)}</select></label><label>العلامة التجارية<input value={brand} onChange={(event) => setBrand(event.target.value)} maxLength={100} required placeholder="مثال: Apple" /></label><label>الموديل<input value={model} onChange={(event) => setModel(event.target.value)} maxLength={160} required placeholder="مثال: iPhone 15" /></label><label>اللون <span className="optional">اختياري</span><input value={color} onChange={(event) => setColor(event.target.value)} maxLength={100} /></label><label>IMEI 1<input dir="ltr" inputMode="numeric" maxLength={15} value={imei1} onChange={(event) => setImei1(event.target.value.replace(/\D/g, '').slice(0, 15))} required placeholder="000000000000000" /></label><label>IMEI 2 <span className="optional">Dual SIM</span><input dir="ltr" inputMode="numeric" maxLength={15} value={imei2} onChange={(event) => setImei2(event.target.value.replace(/\D/g, '').slice(0, 15))} placeholder="اختياري" /></label><label className="form-span-2">الرقم التسلسلي <span className="optional">اختياري</span><input dir="ltr" value={serial} onChange={(event) => setSerial(event.target.value)} maxLength={160} /></label><label className="file-field form-span-2">صور الجهاز <span className="optional">اختياري · JPG / PNG / WebP بحد أقصى 10MB</span><span><ImagePlus size={18} />اختيار صور<input type="file" accept="image/jpeg,image/png,image/webp" multiple onChange={(event) => setPhotos(Array.from(event.target.files ?? []).slice(0, 6))} /></span>{photos.length > 0 && <small>{photos.length} صور جاهزة للرفع الخاص بعد الحفظ.</small>}</label>{error && <div className="inline-alert danger form-span-2">{error}</div>}<div className="form-footer form-span-2"><span><Smartphone size={17} />لا يمكن حذف هوية الجهاز بعد تسجيلها.</span><button className="primary-button" disabled={busy}>{busy ? <InlineLoader /> : 'تسجيل الجهاز'}</button></div></form>}</>
}
