import { CheckCircle2, CircleAlert, FileKey2, ServerCog } from 'lucide-react'
import { Logo } from '../components/Logo'

export function ConfigurationPage() {
  return <main className="configuration-page"><section className="configuration-card"><Logo /><span className="eyebrow">إعداد آمن مطلوب</span><h1>لم يتم ربط المنصة بعد</h1><p>الواجهة لا تتضمن مفاتيح سرية ولا بيانات تجريبية. اربط مشروع Supabase المعتمد قبل استخدام أي عملية.</p><div className="configuration-steps"><div><FileKey2 /><span><b>1. أضف القيم العامة فقط</b><small>انسخ <code>.env.example</code> إلى <code>.env</code> وأضف رابط المشروع والمفتاح العام Anon/Publishable.</small></span></div><div><ServerCog /><span><b>2. طبّق المخطط والدوال</b><small>شغّل migrations وEdge Functions، ثم اضبط أسرار الوظائف في Supabase.</small></span></div><div><CheckCircle2 /><span><b>3. أنشئ أول مدير بشكل موثوق</b><small>امنح الدور من جلسة إدارة خاضعة للمراجعة، وليس من متصفح المستخدم.</small></span></div></div><div className="inline-alert warning"><CircleAlert size={18} />لن تعمل المنصة بوضع محاكاة حتى لا تختلط بيانات تجريبية بالبيانات الحساسة.</div></section></main>
}
