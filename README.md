# حماية | نظام مكافحة سرقة الأجهزة وإدارة دورة الحياة

منصة عربية RTL لإدارة هوية الجهاز برقم IMEI وربط البيع والصيانة والفرمتة والبلاغات والأدلة ضمن صلاحيات دقيقة وسجل تدقيق قابل للمراجعة.

> **لا تدّعي المنصة تتبع الموقع الحالي لجهاز من IMEI.** دورها هو التحقق من هوية الجهاز وسجله التشغيلي والبلاغات المسجلة بطريقة موثوقة.

## ما نُفذ

- واجهة Responsive عربية حقيقية: تسجيل دخول/MFA، onboarding محل، Dashboard حسب الدور، فحص IMEI، تسجيل جهاز/بيع/صيانة/فرمتة، بلاغات، أدلة خاصة، Timeline، إدارة محلات ومستخدمين، أمن وتدقيق وتقارير CSV/Print-PDF.
- Supabase/PostgreSQL: Schema منظم، FK/index/IMEI Luhn constraint، dual-SIM، RBAC قابل للتوسعة، RLS، state machines، append-only critical records، audit SHA-256 hash chain.
- Edge Functions: مدخل آمن لكل عملية حساسة، تشفير AES-GCM للـ PII، HMAC blind-index search، signed upload/view URLs، rate limits، ومراقبة أمنية.
- لا يوجد Service Role أو مفتاح تشفير في الواجهة أو Git، ولا يوجد وضع demo يختلط بالإنتاج.

## البدء السريع

```bash
cp .env.example .env
npm ci
npm run dev
```

ثم اتبع [دليل التشغيل العربي خطوة بخطوة](docs/RUNBOOK_AR.md) لإعداد مشروع Supabase، الأسرار، migrations، Edge Functions، واختبار سيناريو القبول.

> **من المتصفح فقط (بدون تيرمينال):** اتبع [دليل الإعداد والتشخيص من المتصفح](docs/SETUP_BROWSER_ONLY_AR.md) — ينشئ الجداول ويعتمد أول مسؤول وينشر الدوال عبر لوحة Supabase وGitHub Actions.

## GitHub Pages + PWA

توجد قوالب workflows جاهزة لبناء الواجهة ضمن GitHub Pages وتحويلها إلى PWA قابل للتثبيت؛ أضفها يدويًا من [نسخة workflows للإضافة اليدوية](docs/GITHUB_WORKFLOWS_MANUAL.md). أضف فقط `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY` إلى GitHub Actions Secrets؛ لا تضع Service Role أو مفاتيح AES/HMAC تحت `VITE_*`. راجع [دليل GitHub Pages PWA](docs/GITHUB_PAGES_PWA.md) قبل النشر.

## التحقق

```bash
npm run verify
npm run secrets:check
# مع Supabase محلي/Docker
npx supabase test db
```

## المستندات

- [المعمارية](docs/ARCHITECTURE.md)
- [المراجعة الأمنية](docs/SECURITY.md)
- [التشغيل والنشر](docs/DEPLOYMENT.md)
- [النشر كتطبيق PWA عبر GitHub Pages](docs/GITHUB_PAGES_PWA.md)
- [الإعداد والتشخيص من المتصفح فقط](docs/SETUP_BROWSER_ONLY_AR.md)

## تنبيه قانوني وتشغيلي

قبل إدخال أي بيانات حقيقية، اعتمد سياسة جمع الهوية والاحتفاظ بها والجهات المخولة وإجراءات البلاغ مع الجهة القانونية المختصة. التصميم يطبق Data Minimization وLeast Privilege، لكنه لا يغني عن الضوابط القانونية وإدارة مفاتيح الإنتاج والنسخ الاحتياطي والتدقيق التشغيلي.
