import { useMemo, useState, type FormEvent } from 'react'
import { AlertOctagon, Camera, CheckCircle2, ClipboardCheck, SearchCheck, ShieldAlert, Wrench } from 'lucide-react'
import { Link } from 'react-router-dom'
import { InlineLoader } from '../components/LoadingState'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { formatDate } from '../lib/format'
import { isValidImei } from '../lib/imei'
import { uploadRepairImage } from '../lib/media'
import type { ImeiResult, RepairReceipt } from '../types/domain'

export function TechnicianIntakePage() {
  const { bootstrap } = useAuth()
  const shops = useMemo(() => (bootstrap?.shops ?? []).filter((shop) => shop.status === 'approved' && shop.verification_status === 'verified'), [bootstrap])
  const [shopId, setShopId] = useState(shops[0]?.id ?? '')
  const [imei, setImei] = useState('')
  const [check, setCheck] = useState<ImeiResult | null>(null)
  const [operationType, setOperationType] = useState('')
  const [notes, setNotes] = useState('')
  const [resultText, setResultText] = useState('تم الاستلام للفحص')
  const [beforeFiles, setBeforeFiles] = useState<File[]>([])
  const [afterFiles, setAfterFiles] = useState<File[]>([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [receipt, setReceipt] = useState<RepairReceipt | null>(null)

  async function inspect() {
    setError(null); setCheck(null)
    if (!isValidImei(imei)) { setError('رقم IMEI غير صالح. تحقق من 15 رقمًا ورقم Luhn النهائي.'); return }
    setBusy(true)
    try { setCheck(await invoke<ImeiResult>('check-imei', { imei })) } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  async function submit(event: FormEvent) {
    event.preventDefault(); setError(null)
    if (!check || check.imei !== imei) { setError('افحص IMEI أولًا قبل إنشاء عملية الصيانة.'); return }
    if (check.security_alert) { setError('لا يمكن تسجيل صيانة عادية لجهاز عليه بلاغ نشط. اتبع الإجراء المعتمد وتواصل مع الجهة المختصة.'); return }
    if (!shopId) { setError('لا يوجد محل معتمد مرتبط بحساب الفني.'); return }
    setBusy(true)
    try {
      const created = await invoke<RepairReceipt>('create-repair', { shop_id: shopId, imei, operation_type: operationType, notes: notes || null, result: resultText, before_images: [], after_images: [] })
      for (const file of beforeFiles) await uploadRepairImage(file, created.device_id, created.repair_id, 'before_repair')
      for (const file of afterFiles) await uploadRepairImage(file, created.device_id, created.repair_id, 'after_repair')
      setReceipt(created)
      setBeforeFiles([]); setAfterFiles([])
    } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  const selectedShop = shops.find((shop) => shop.id === shopId)
  if (receipt) return <><PageHeader eyebrow="بطاقة تأكيد" title="تم تسجيل عملية الصيانة" description="لا يمكن للفني حذف العملية بعد حفظها. الصور، إن وجدت، رفعت إلى تخزين خاص." /><section className="technician-receipt"><CheckCircle2 size={40} /><div><h2>تم إنشاء عملية فنية موثقة</h2><dl><div><dt>اسم الفني</dt><dd>{bootstrap?.user.display_name}</dd></div><div><dt>المحل</dt><dd>{selectedShop?.name}</dd></div><div><dt>IMEI</dt><dd dir="ltr">{imei}</dd></div><div><dt>نوع العملية</dt><dd>{operationType}</dd></div><div><dt>التاريخ والوقت</dt><dd>{formatDate(receipt.created_at)}</dd></div><div><dt>رقم العملية</dt><dd dir="ltr">{receipt.operation_number}</dd></div></dl><Link className="primary-button" to={`/devices/${receipt.device_id}`}>عرض سجل الجهاز</Link></div></section></>

  return <><PageHeader eyebrow="واجهة الفني السريعة" title="استلام جهاز وصيانته" description="IMEI ← فحص خادمي ← تنبيه أمني عند الحاجة ← تسجيل عملية برقم فريد." />{!shops.length ? <div className="inline-alert warning">لا يوجد محل معتمد وفَعّال مرتبط بحساب الفني.</div> : <form className="intake-layout" onSubmit={submit}><section className="intake-step panel"><span className="step-number">1</span><div><h2>فحص الجهاز</h2><p>لا تبدأ إجراءات الصيانة قبل وصول أحدث حالة من الخادم.</p><div className="check-inline"><label>رقم IMEI<input dir="ltr" inputMode="numeric" maxLength={15} value={imei} onChange={(event) => { setImei(event.target.value.replace(/\D/g, '').slice(0, 15)); setCheck(null) }} required placeholder="000000000000000" /></label><button type="button" className="primary-button" disabled={busy} onClick={() => void inspect()}>{busy ? <InlineLoader /> : <><SearchCheck size={18} />فحص</>}</button></div>{check && (check.security_alert ? <div className="intake-critical"><ShieldAlert size={23} /><div><b>تنبيه أمني: الجهاز مسجل ضمن بلاغ</b><p>لا تُكمل صيانة أو فرمتة الجهاز. يرجى التواصل مع الجهة المختصة حسب الإجراء المعتمد.</p>{check.report && <Link to={`/reports/${check.report.id}`}>عرض البلاغ المصرح به</Link>}</div></div> : <div className="intake-clear"><CheckCircle2 size={20} /><span>لا يوجد بلاغ نشط على الجهاز.</span>{check.device && <StatusBadge status={check.device.status} />}</div>)}</div></section><section className={`intake-step panel ${!check || check.security_alert ? 'disabled-panel' : ''}`}><span className="step-number">2</span><div><h2>تفاصيل العملية</h2><p>هذه البيانات جزء من سجل ثابت بعد الحفظ.</p><div className="form-grid nested-grid"><label>المحل<select value={shopId} onChange={(event) => setShopId(event.target.value)}>{shops.map((shop) => <option value={shop.id} key={shop.id}>{shop.name}</option>)}</select></label><label>نوع الخدمة<select value={operationType} onChange={(event) => setOperationType(event.target.value)} required disabled={!check || check.security_alert}><option value="">اختر نوع الخدمة</option><option>فحص وتشخيص</option><option>إصلاح شاشة</option><option>إصلاح بطارية</option><option>صيانة برمجية</option><option>صيانة عامة</option></select></label><label className="form-span-2">نتيجة الاستلام أو الخدمة<input value={resultText} onChange={(event) => setResultText(event.target.value)} maxLength={500} disabled={!check || check.security_alert} required /></label><label className="form-span-2">ملاحظات <span className="optional">اختياري</span><textarea rows={3} value={notes} onChange={(event) => setNotes(event.target.value)} maxLength={3000} disabled={!check || check.security_alert} /></label><label className="file-field"><span>صور قبل الصيانة <span className="optional">حتى 6 صور</span></span><span><Camera size={18} />اختيار صور<input type="file" accept="image/jpeg,image/png,image/webp" multiple disabled={!check || check.security_alert} onChange={(event) => setBeforeFiles(Array.from(event.target.files ?? []).slice(0, 6))} /></span>{beforeFiles.length > 0 && <small>{beforeFiles.length} صور مختارة</small>}</label><label className="file-field"><span>صور بعد الصيانة <span className="optional">حتى 6 صور</span></span><span><Camera size={18} />اختيار صور<input type="file" accept="image/jpeg,image/png,image/webp" multiple disabled={!check || check.security_alert} onChange={(event) => setAfterFiles(Array.from(event.target.files ?? []).slice(0, 6))} /></span>{afterFiles.length > 0 && <small>{afterFiles.length} صور مختارة</small>}</label></div></div></section>{error && <div className="inline-alert danger"><AlertOctagon size={18} />{error}</div>}<div className="intake-submit"><span><ClipboardCheck size={18} />سيتم إنشاء رقم عملية فريد وسجل تدقيق عند الحفظ.</span><button className="primary-button" disabled={busy || !check || check.security_alert}>{busy ? <InlineLoader /> : <><Wrench size={18} />تسجيل عملية الصيانة</>}</button></div></form>}</>
}
