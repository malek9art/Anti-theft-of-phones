import { ShieldX } from 'lucide-react'
import { Link } from 'react-router-dom'
import { PageHeader } from '../components/PageHeader'

export function ForbiddenPage() {
  return <><PageHeader eyebrow="وصول مرفوض" title="لا تملك صلاحية هذه الشاشة" description="تفرض المنصة هذا القيد في الواجهة والخادم وقاعدة البيانات؛ لا يكفي إخفاء الزر للوصول إلى بيانات محمية." /><section className="empty-state"><ShieldX size={36} /><h3>هذه العملية خارج نطاق دورك</h3><p>تواصل مع مدير النظام المعتمد إذا كان الوصول مطلوبًا لإنجاز مهمة رسمية.</p><Link className="primary-button" to="/">العودة إلى لوحة التحكم</Link></section></>
}
