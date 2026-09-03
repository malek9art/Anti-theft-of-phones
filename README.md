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

ثم اتبع [دليل التشغيل العربي خطوة بخطوة](docs-source/RUNBOOK_AR.md) لإعداد مشروع Supabase، الأسرار، migrations، Edge Functions، واختبار سيناريو القبول.

> **من المتصفح فقط (بدون تيرمينال):** اتبع [دليل الإعداد والتشخيص من المتصفح](docs-source/SETUP_BROWSER_ONLY_AR.md) — نشر الواجهة عبر الفرع، إنشاء الجداول يدويًا في SQL Editor، اعتماد أول مسؤول، ونشر الدوال مرة واحدة.

## GitHub Pages + PWA (نشر عبر الفرع)

الواجهة المبنية جاهزة في مجلد `docs/` وتُنشر عبر **GitHub Pages → Deploy from a branch** (الفرع + مجلد `/docs`). تعتمد الواجهة على قيمتين عامتين فقط توضعان في `docs/config.js`: `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY`. لا تضع Service Role أو مفاتيح AES/HMAC في أي متغير `VITE_*`. راجع [دليل GitHub Pages PWA](docs-source/GITHUB_PAGES_PWA.md) و[نسخة workflows](docs-source/GITHUB_WORKFLOWS_MANUAL.md) قبل النشر.

## التحقق

```bash
npm run verify
npm run secrets:check
# مع Supabase محلي/Docker
npx supabase test db
```

## المستندات

- [المعمارية](docs-source/ARCHITECTURE.md)
- [المراجعة الأمنية](docs-source/SECURITY.md)
- [التشغيل والنشر](docs-source/DEPLOYMENT.md)
- [النشر كتطبيق PWA عبر GitHub Pages](docs-source/GITHUB_PAGES_PWA.md)
- [الإعداد والتشخيص من المتصفح فقط](docs-source/SETUP_BROWSER_ONLY_AR.md)

## تنبيه قانوني وتشغيلي

قبل إدخال أي بيانات حقيقية، اعتمد سياسة جمع الهوية والاحتفاظ بها والجهات المخولة وإجراءات البلاغ مع الجهة القانونية المختصة. التصميم يطبق Data Minimization وLeast Privilege، لكنه لا يغني عن الضوابط القانونية وإدارة مفاتيح الإنتاج والنسخ الاحتياطي والتدقيق التشغيلي.
