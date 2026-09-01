# نشر «حماية» كتطبيق PWA عبر GitHub Pages

تجهز هذه الإعدادات الواجهة كـ **PWA قابل للتثبيت** على GitHub Pages، مع بقاء المصادقة وقاعدة البيانات وEdge Functions في Supabase.

> GitHub Pages يستضيف ملفات HTML/CSS/JavaScript فقط. لا يمكنه استضافة PostgreSQL أو Supabase Auth أو Edge Functions أو حفظ مفاتيح خادمية بأمان للتطبيق وقت التشغيل.

## قاعدة أمنية لا يمكن تجاوزها

| نوع القيمة | أين تحفظ | هل تصبح مرئية لزائر التطبيق؟ |
|---|---|---|
| `VITE_SUPABASE_URL` | GitHub Repository Secret في بناء Pages | نعم، URL عام بطبيعته |
| `VITE_SUPABASE_ANON_KEY` | GitHub Repository Secret في بناء Pages | نعم، هذا مفتاح Anon/Publishable مقصود للمتصفح ومقيد بـ RLS |
| `SUPABASE_SERVICE_ROLE_KEY` | GitHub **Environment Secret** فقط لإرسالها إلى Supabase runtime، أو Supabase Secrets مباشرة | لا، إذا لم يسبق الاسم `VITE_` ولم يدخل build الواجهة |
| `SENSITIVE_DATA_ENCRYPTION_KEY` | Supabase Edge Function Secret؛ يمكن للـ workflow اليدوي نقلها من GitHub Environment Secret | لا |
| `SENSITIVE_DATA_LOOKUP_KEY` | Supabase Edge Function Secret مستقل | لا |
| `AUTH_EVENT_INGEST_SECRET` | Supabase Edge Function Secret / خدمة hook موثوقة | لا |

أي متغير يبدأ بـ `VITE_` يُضمّن في JavaScript المنشور على GitHub Pages، حتى إن أُدخل كـ GitHub Secret. لذلك **لا تضع Service Role أو مفاتيح AES/HMAC أو token إداري تحت اسم `VITE_*`**.

---

## 1) تفعيل GitHub Pages

1. افتح مستودع GitHub.
2. اذهب إلى **Settings → Pages**.
3. عند **Build and deployment** اختر **Source: GitHub Actions**.
4. لا تستخدم خيار النشر من branch؛ ملف workflow هو المسؤول عن النشر.

قالب الـ workflow موجود في [ملف الإضافة اليدوية](GITHUB_WORKFLOWS_MANUAL.md). أضف منه الملف التالي يدويًا في GitHub:

```text
.github/workflows/deploy-pages.yml
```

بعد إضافته يعمل عند push إلى `main` أو فرع العمل الحالي، أو يدويًا من تبويب **Actions**.

---

## 2) إعداد أسرار الواجهة الآمنة للنشر

في GitHub افتح:

```text
Settings → Secrets and variables → Actions → Secrets → New repository secret
```

أضف هذين السرّين فقط لبناء GitHub Pages:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
```

القيم النموذجية:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-or-publishable-key
```

- خذ **Project URL** و**anon/publishable key** من Supabase Dashboard → Project Settings → API.
- لا تستخدم `service_role` بدل anon key.
- يكون anon key ظاهرًا بعد البناء، وهذا طبيعي فقط لأن RLS وRPC/Edge Functions هي طبقة الحماية الحقيقية.

### مسار GitHub Pages

لرابط project Pages المعتاد:

```text
https://OWNER.github.io/REPOSITORY/
```

لا تحتاج لأي إعداد إضافي؛ workflow يبني تلقائيًا داخل:

```text
/REPOSITORY/
```

إذا ستستخدم custom domain من جذر النطاق، أضف Repository Variable (وليس secret) باسم:

```text
PAGES_BASE_PATH
```

وقيمته:

```text
/
```

يستخدم نشر Pages روابط hash مثل:

```text
https://OWNER.github.io/REPOSITORY/#/check
```

وهذا مقصود لأن GitHub Pages لا يدعم SPA rewrite لمسارات مثل `/check` عند إعادة التحميل.

---

## 3) ضبط Supabase لقبول GitHub Pages

قبل فتح التطبيق للجمهور، اضبط في Supabase Edge Function Secrets:

```dotenv
ALLOWED_ORIGINS=https://OWNER.github.io
APP_REDIRECT_URL=https://OWNER.github.io/REPOSITORY/
```

- `ALLOWED_ORIGINS` هو **origin فقط**: بدون اسم المستودع وبدون `/` في النهاية.
- `APP_REDIRECT_URL` هو الرابط الكامل للتطبيق، ويتضمن اسم المستودع في Project Pages.
- لا تضع wildcard مثل `*`.

ثم في Supabase Dashboard → **Authentication → URL Configuration** اضبط:

```text
Site URL:
https://OWNER.github.io/REPOSITORY/

Redirect URLs:
https://OWNER.github.io/REPOSITORY/
https://OWNER.github.io/REPOSITORY/#/
```

أضف روابط الاستعادة/التأكيد الفعلية التي تعتمدها المؤسسة فقط. استخدم custom domain في الإنتاج متى أمكن.

---

## 4) حفظ أسرار الخادم في GitHub بأمان نسبيًا

يوجد قالب workflow منفصل يدوي فقط في [ملف الإضافة اليدوية](GITHUB_WORKFLOWS_MANUAL.md)، أضفه بالمسار:

```text
.github/workflows/deploy-supabase.yml
```

لا يبني الواجهة بهذه القيم. عند تشغيله يدويًا، يطبق migrations، يرسل الأسرار إلى Supabase Edge runtime، ثم ينشر Edge Functions.

### أنشئ GitHub Environments

من:

```text
Settings → Environments
```

أنشئ على الأقل:

```text
staging
production
```

ضع approval/reviewer مطلوبًا لبيئة `production`، وامنح صلاحية تشغيل workflow لعدد محدود من المسؤولين.

### أسرار كل Environment

أضف القيم التالية تحت البيئة المناسبة، لا كـ repository secrets عامة:

```text
SUPABASE_ACCESS_TOKEN
SUPABASE_PROJECT_REF
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
ALLOWED_ORIGINS
APP_REDIRECT_URL
SENSITIVE_DATA_ENCRYPTION_KEY
SENSITIVE_DATA_LOOKUP_KEY
AUTH_EVENT_INGEST_SECRET
```

#### توليد مفاتيح التشفير

أنشئ ناتجين مستقلين تمامًا:

```bash
openssl rand -base64 32 | tr '+/' '-_' | tr -d '='
openssl rand -base64 32 | tr '+/' '-_' | tr -d '='
```

ضع الأول في `SENSITIVE_DATA_ENCRYPTION_KEY` والثاني في `SENSITIVE_DATA_LOOKUP_KEY`.

#### تشغيل نشر Supabase

1. افتح تبويب **Actions**.
2. اختر **Deploy Himaya Supabase backend**.
3. اختر **Run workflow**.
4. اختر `staging` أولًا.
5. راجع migrations وEdge Function logs واختبر السيناريو الكامل.
6. بعد الموافقة، كرر التشغيل لبيئة `production`.

الـ workflow يتحقق من:

- وجود جميع الأسرار المطلوبة دون طباعتها.
- HTTPS للروابط.
- منع wildcard في `ALLOWED_ORIGINS`.
- صحة طول مفاتيح AES/HMAC وتباينها.
- تطبيق `supabase db push` قبل نشر الدوال.

> GitHub Secrets آمنة من العرض المباشر في logs، لكنها متاحة للـ workflows المصرح بها. لا تمنح write access للمستودع أو approve access لبيئة production إلا للمسؤولين الموثوقين، ولا تسمح بتشغيل workflow من pull request غير موثوق.

---

## 5) نشر الواجهة إلى GitHub Pages

بعد إضافة `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY`:

1. ارفع commit إلى الفرع المفعّل (`main` بعد الدمج هو الخيار المعتاد).
2. افتح **Actions → Deploy Himaya PWA to GitHub Pages**.
3. انتظر مرحلتي build وdeploy.
4. افتح رابط deployment الناتج من workflow أو من **Settings → Pages**.

الـ workflow يبني بإعدادات:

```text
VITE_APP_ENV=production
VITE_ROUTER_MODE=hash
VITE_BASE_PATH=/REPOSITORY/
```

ولا يستخدم أو ينقل أسرار قاعدة البيانات الخاصة إلى ملفات `dist`.

---

## 6) تثبيت التطبيق كتطبيق PWA

بعد فتح الرابط عبر HTTPS:

### Chrome أو Edge على الكمبيوتر

1. افتح الموقع.
2. اضغط أيقونة التثبيت في شريط العنوان، أو القائمة ⋮.
3. اختر **Install حماية** / **تثبيت التطبيق**.
4. سيظهر كتطبيق مستقل في النظام.

### Chrome على Android

1. افتح الموقع في Chrome.
2. افتح القائمة ⋮.
3. اختر **Install app** أو **إضافة إلى الشاشة الرئيسية**.
4. وافق على التثبيت.

### Safari على iPhone/iPad

1. افتح الموقع في Safari، وليس متصفحًا مدمجًا داخل تطبيق آخر.
2. اضغط زر المشاركة.
3. اختر **Add to Home Screen / إضافة إلى الشاشة الرئيسية**.
4. اختر **إضافة**.

التطبيق يحتوي على manifest وأيقونات 192/512 وخدمة Service Worker. الخدمة تخزن **الواجهة والملفات الثابتة فقط** لتوفير shell بسيط عند ضعف الاتصال؛ لا تخزن جلسة المستخدم أو API responses أو بيانات العملاء أو الأدلة أو Signed URLs في Cache Storage.

عمليات IMEI والبيع والصيانة والبلاغات والأدلة تتطلب اتصالًا مباشرًا بـ Supabase/Edge Functions. يظهر تنبيه واضح عند انقطاع الاتصال.

---

## 7) التحديثات

عند نشر إصدار جديد إلى GitHub Pages:

- يتحقق المتصفح من Service Worker الجديد تلقائيًا.
- أغلق التطبيق المثبت وافتحه مجددًا أو حدث الصفحة للحصول على الإصدار الجديد سريعًا.
- إذا ظهرت نسخة قديمة أثناء التطوير، امسح بيانات الموقع أو ألغِ Service Worker من DevTools → Application → Service Workers، ثم حدث الصفحة.

---

## 8) قيود GitHub Pages في الإنتاج الحساس

- GitHub Pages لا يسمح بضبط headers مخصصة من المستودع؛ ملف `public/_headers` لا تعتمد عليه GitHub Pages كطبقة حماية.
- إن كان التطبيق إنتاجيًا لبيانات حساسة، استخدم custom domain وراء Cloudflare/بوابة مؤسسية أو static host يدعم CSP وHSTS وWAF وheaders مثل `X-Frame-Options`.
- لا تعتمد على GitHub Pages لحماية البيانات؛ الحماية الفعلية يجب أن تبقى في Supabase Auth، RLS، RPC، Edge Functions، Storage policies، ومفاتيح الخادم.
- لا تشغّل `seed:dev` أو `supabase db reset` أو بيانات اختبار على production.

---

## 9) قائمة تحقق قبل الإتاحة للمستخدمين

- [ ] GitHub Pages مفعّل من GitHub Actions.
- [ ] `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY` موجودان فقط لبناء الواجهة.
- [ ] تم نشر migrations وEdge Functions على staging أولًا.
- [ ] `ALLOWED_ORIGINS` يتضمن `https://OWNER.github.io` فقط بلا wildcard.
- [ ] Site URL وRedirect URLs في Supabase تتضمن مسار repository الصحيح.
- [ ] Service Role ومفاتيح التشفير ليست في أي `VITE_*` أو `.env` منشور أو browser bundle.
- [ ] اختبرت MFA، صلاحيات الأدوار، رفع الهوية/الدليل، تنبيه IMEI، Timeline وAudit Log.
- [ ] ضبطت حماية GitHub Environment ومراجعة قبل production.
- [ ] وضعت custom domain/طبقة headers مناسبة قبل استخدام بيانات حقيقية حساسة.
