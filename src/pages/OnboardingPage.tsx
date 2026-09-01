import { useState, type FormEvent } from 'react'
import { Clock3, LogOut, Send, Store } from 'lucide-react'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { InlineLoader } from '../components/LoadingState'
import { Logo } from '../components/Logo'
import { StatusBadge } from '../components/StatusBadge'

export function OnboardingPage() {
  const { bootstrap, refresh, signOut } = useAuth()
  const [shopName, setShopName] = useState('')
  const [commercialName, setCommercialName] = useState('')
  const [phone, setPhone] = useState('')
  const [address, setAddress] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const submitted = (bootstrap?.shops.length ?? 0) > 0

  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(null)
    try {
      await invoke('submit-shop', { shop_name: shopName, commercial_name: commercialName || null, business_phone: phone || null, address_text: address || null })
      await refresh()
    } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) }
  }

  return <main className="onboarding-layout"><section className="onboarding-card"><Logo /><div className="onboarding-heading"><span className="eyebrow">خطوة الاعتماد</span><h1>مرحبًا، {bootstrap?.user.display_name}</h1><p>لا يمكن تنفيذ أي عملية على الأجهزة قبل اعتماد الحساب والمحل من الإدارة المختصة.</p></div>{submitted ? <div className="pending-view"><div className="pending-icon"><Clock3 size={32} /></div><h2>طلبك قيد المراجعة</h2><p>سيتم تفعيل الحساب بعد التحقق من بيانات المحل وتعيين الصلاحيات. ستصلك إشعارات عند اكتمال المراجعة.</p><div className="pending-shops">{bootstrap?.shops.map((shop) => <div key={shop.id}><Store size={18} /><span><b>{shop.name}</b><small>{shop.title ?? 'طلب محل'}</small></span><StatusBadge status={shop.status} /></div>)}</div><button className="secondary-button" onClick={() => void refresh()}>تحديث حالة الطلب</button></div> : <form onSubmit={submit} className="form-stack"><label>اسم المحل<input value={shopName} onChange={(event) => setShopName(event.target.value)} placeholder="مثال: حماية للهواتف" required maxLength={180} /></label><label>الاسم التجاري <span className="optional">اختياري</span><input value={commercialName} onChange={(event) => setCommercialName(event.target.value)} maxLength={180} /></label><label>هاتف المحل <span className="optional">اختياري</span><input dir="ltr" value={phone} onChange={(event) => setPhone(event.target.value)} maxLength={40} /></label><label>عنوان المحل <span className="optional">اختياري</span><textarea value={address} onChange={(event) => setAddress(event.target.value)} maxLength={1000} rows={3} /></label>{error && <div className="inline-alert danger">{error}</div>}<button className="primary-button full-button" disabled={busy}>{busy ? <InlineLoader /> : <><Send size={18} />إرسال طلب الاعتماد</>}</button></form>}<button className="link-button centered" onClick={() => void signOut()}><LogOut size={16} />تسجيل الخروج</button></section></main>
}
