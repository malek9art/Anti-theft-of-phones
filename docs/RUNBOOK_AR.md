# دليل تشغيل «حماية» خطوة بخطوة

هذا الدليل يشرح تشغيل الواجهة وربطها بـ Supabase، تجهيز أول مدير، تشغيل اختبارات الأمان، ثم التحقق من سيناريو العمل الكامل. لا تبدأ بإدخال بيانات حقيقية قبل تطبيق قسم **التحضير للإنتاج**.

> **حدود المنتج:** المنصة تتحقق من IMEI وسجل الجهاز والبلاغات المسجلة فيها. لا تتعقب موقع هاتف عبر IMEI وحده.

---

## 1) ما الذي تحتاجه

| الغرض | المتطلب |
|---|---|
| تشغيل الواجهة | Node.js 22 أو أحدث وnpm |
| قاعدة محلية واختبارات pgTAP | Docker Desktop شغال وSupabase CLI حديث |
| بيئة staging/production | مشروع Supabase منفصل، وصلاحية إدارة له |
| MFA | تطبيق TOTP مثل Google Authenticator أو Microsoft Authenticator أو 1Password |

تحقق من الأدوات:

```bash
node --version
npm --version
npx supabase --version
```

> في بيئة Arena الحالية لا يتوفر Docker أو مشروع Supabase مزود بالمفاتيح، لذا يمكن معاينة الواجهة والتحقق البرمجي، لكن لا يمكن تشغيل قاعدة البيانات أو سيناريو E2E الحقيقي هنا حتى توفر تلك المتطلبات.

---

## 2) معاينة الواجهة فقط (بدون قاعدة بيانات)

هذه الطريقة مناسبة لفحص التصميم العربي RTL وشاشة الإعداد. لا تنفذ بيعًا أو بلاغًا لأن الاتصال غير مهيأ.

```bash
cd Anti-theft-of-phones
npm ci
npm run dev
```

افتح العنوان الذي يعرضه Vite، غالبًا:

```text
http://localhost:5173
```

إذا ظهرت شاشة **«يلزم إعداد الاتصال الآمن»** فهذه النتيجة متوقعة إلى أن تضبط المتغيرين في الخطوة التالية.

---

## 3) تشغيل محلي كامل مع Supabase

### 3.1 تشغيل الخدمات المحلية وتطبيق المخطط

من جذر المشروع:

```bash
npx supabase start
npx supabase db reset
npx supabase status -o env
```

- الأمر الأول يحتاج Docker ويشغل PostgreSQL وAuth وStorage وStudio محليًا.
- الأمر الثاني يطبق كل ملفات `supabase/migrations` بالترتيب ويعيد القاعدة المحلية فقط.
- احتفظ بقيم `API URL` و`anon key` و`service_role key` التي يعرضها `supabase status -o env`؛ لا تشارك مفتاح `service_role` ولا تضعه في `.env` الخاص بالواجهة.

### 3.2 إعداد متغيرات الواجهة

```bash
cp .env.example .env
```

حرر `.env` وضع القيم المحلية التي ظهرت في `supabase status`:

```dotenv
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=ضع-مفتاح-anon-المحلي-هنا
VITE_APP_ENV=development
```

> `.env` للمتصفح: يقبل **فقط** `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY`. لا تضع فيه `SUPABASE_SERVICE_ROLE_KEY` أو مفاتيح التشفير.

### 3.3 إعداد أسرار Edge Functions محليًا

```bash
cp supabase/.env.example supabase/.env
```

املأ الملف `supabase/.env` بالقيم المحلية وأسرار تطوير مستقلة. مثال للأصلين:

```dotenv
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=ضع-مفتاح-anon-المحلي
SUPABASE_SERVICE_ROLE_KEY=ضع-service-role-المحلي
ALLOWED_ORIGINS=http://localhost:5173
APP_REDIRECT_URL=http://localhost:5173
SENSITIVE_DATA_ENCRYPTION_KEY=مفتاح-base64url-32-byte
SENSITIVE_DATA_LOOKUP_KEY=مفتاح-base64url-مختلف-32-byte
AUTH_EVENT_INGEST_SECRET=سر-طويل-محلي
```

أنشئ كل مفتاح تشفير بشكل مستقل، مثلًا في macOS/Linux/Git Bash:

```bash
openssl rand -base64 32 | tr '+/' '-_' | tr -d '='
```

لا تعيد استخدام ناتج `SENSITIVE_DATA_ENCRYPTION_KEY` كمفتاح بحث. الأول لتشفير AES-GCM، والثاني لـ HMAC blind indexes.

شغّل الدوال محليًا في نافذة طرفية مستقلة:

```bash
npx supabase functions serve --env-file supabase/.env
```

ثم في نافذة أخرى:

```bash
npm run dev
```

الواجهة تعمل على `http://localhost:5173` والدوال خلف نفس مشروع Supabase المحلي. يجب أن يكون هذا الأصل مطابقًا حرفيًا لـ `ALLOWED_ORIGINS`.

---

## 4) تجهيز أول مدير نظام بأمان

التسجيل العادي ينشئ ملف مستخدم بحالة `pending` **دون أي دور**. هذا مقصود لمنع إنشاء مدير من المتصفح.

1. سجّل أول حساب من شاشة الدخول/التسجيل، وأكد بريده في البريد المحلي أو من Supabase Studio.
2. من SQL Editor محلي مقيد أو عملية bootstrap موثقة واحدة، نفّذ التالي بعد استبدال المعرف:

   ```sql
   update public.users
   set account_status = 'active'
   where id = 'USER_UUID';

   insert into public.user_roles (user_id, role_id)
   select 'USER_UUID'::uuid, id
   from public.roles
   where key = 'system_admin'
   on conflict do nothing;
   ```

3. سجّل الدخول بهذا الحساب.
4. افتح **أمان الحساب**، اختر **إعداد تطبيق المصادقة**، امسح QR في تطبيق TOTP، ثم أدخل الرمز لتأكيده.
5. بعد MFA تكون جلسة المدير AAL2 ويمكنه تنفيذ العمليات الإدارية الحساسة.

**مهم:** كل دالة حساسة ترفض جلسة AAL1 خادميًا، حتى لو كانت قيمة `mfa_required` للمستخدم `false`. هذا يشمل إدارة المستخدمين، اعتماد المحلات، البلاغات، الأدلة، التعيين، التدقيق، والتقارير الحساسة.

---

## 5) اختصار بيانات تطوير محلية فقط

بعد أن تعمل القاعدة والدوال المحلية، تستطيع إنشاء سبعة حسابات تطويرية وأدوارها ووكالة محلية بالسكربت المحمي:

```bash
set -a
source supabase/.env
set +a
ALLOW_DEVELOPMENT_SEED=true npm run seed:dev
```

السكربت يرفض تلقائيًا أي URL ليس `localhost` أو `127.0.0.1`. لا تستخدمه مطلقًا في staging أو production.

الحسابات التي ينشئها (كلمة المرور الافتراضية `Himaya!Dev2026` ما لم تغير `DEV_TEST_PASSWORD`) هي:

| البريد | الدور | ملاحظة |
|---|---|---|
| `system_admin@himaya.test` | مدير النظام | يحتاج تسجيل TOTP قبل العمل الإداري الحساس |
| `authorized_officer@himaya.test` | موظف مختص | مربوط بوكالة التطوير؛ يحتاج TOTP قبل البلاغ/تغيير الحالة/التعيين |
| `investigation_officer@himaya.test` | بحث جنائي | مربوط بوكالة التطوير؛ يحتاج TOTP |
| `delegate@himaya.test` | مندوب | مربوط بالوكالة وقابل للتعيين؛ يحتاج TOTP قبل المتابعة/الأدلة |
| `shop_manager@himaya.test` | مدير محل | يبدأ onboarding ويستطيع عمليات المحل غير الحساسة |
| `technician@himaya.test` | فني | يربطه المدير بالمحل بعد اعتماده |
| `auditor@himaya.test` | مدقق | يحتاج TOTP للوصول إلى التدقيق/التقارير الحساسة |

بعد تشغيل السكربت، ادخل إلى حساب المدير وفعل MFA أولًا. ثم استخدم الواجهة لإكمال اعتماد محل وربط الفني بدل التعديل المباشر في قاعدة البيانات.

---

## 6) ماذا تستطيع أن تفعل من الواجهة

تعتمد القوائم والأزرار على الصلاحيات التي يعيدها الخادم؛ إخفاء زر ليس آلية حماية.

### مدير النظام

1. راجع لوحة المؤشرات والتنبيهات.
2. اعتمد أو علّق المحلات من **المحلات** مع تسجيل السبب.
3. أرسل دعوات المستخدمين واضبط أدوارهم وحالتهم من **المستخدمون والصلاحيات**.
4. اربط مدير المحل أو الفني بالمحل المعتمد.
5. راجع **الأحداث الأمنية**، حلّ الحدث، وافتح **سجل التدقيق**.
6. عدل الحدود المسموح بها فقط في **الإعدادات الأمنية** (معدل فحص IMEI، مدة الرابط الموقّع، مدة الاحتفاظ).
7. صدّر تقاريرًا ضمن صلاحيتك.

### مدير المحل

1. قدّم طلب محل من onboarding عند عدم وجود محل معتمد.
2. بعد الاعتماد، سجّل جهازًا جديدًا باسم العلامة والموديل وIMEI 1، وإضافة IMEI 2 اختياريًا.
3. سجّل بيعًا، وأدخل بيانات المشتري. تُشفّر البيانات في Edge Function ولا تعود ضمن بيانات البيع العادية.
4. أرفق مستند هوية اختياريًا أثناء البيع؛ يرفع إلى bucket خاص ولا يستطيع عرضه إلا صاحب `view_identity` وبسبب وصول موثق.
5. راجع أجهزة المحل، المبيعات، وسجل الجهاز ضمن نطاق محلّه.

### الفني

1. سجّل استلام/فحص/صيانة الجهاز ضمن محل معتمد.
2. سجّل فرمتة مرتبطة بالصيانة عند الحاجة.
3. افحص IMEI قبل التعامل مع الجهاز.
4. إذا كان الجهاز مبلغًا عنه، يرى تنبيهًا أمنيًا فوريًا فقط ولا يرى هوية المبلّغ أو تفاصيل القضية.
5. لا يستطيع الفني متابعة إصلاح أو فرمتة جهاز عليه بلاغ نشط؛ تسجل المحاولة كحدث أمني.

### الموظف المختص / البحث الجنائي

1. افتح بلاغًا جديدًا مع IMEI، وقت الواقعة، الوصف، والأولوية. يرتبط البلاغ تلقائيًا بوكالة المستخدم؛ لا يسمح بإسناده إلى وكالة خارج النطاق.
2. انتقل بالحالة فقط عبر مسار الحالات المسموح: مقدّم → قيد المراجعة → تم التحقق → نشط/محال → مسترد → مغلق.
3. عيّن موظفًا أو مندوبًا من الدليل الذي يعيده الخادم لحالة القضية نفسها، وليس من قائمة محلية عامة.
4. أضف الأدلة بصور أو PDF. الملفات في تخزين خاص، وفتحها يتطلب سبب وصول ورابطًا مؤقتًا.
5. عند وجود صلاحية صريحة، اطلب بيانات العميل الحساسة لغرض محدد؛ فك التشفير لا يحدث في المتصفح أو PostgreSQL.
6. بعد الاسترداد أغلق القضية، ثم راجع Timeline وسجل التدقيق.

### المندوب

1. يرى الحالات المسندة إليه فقط.
2. يضيف متابعات ميدانية موثقة ضمن القضية المفتوحة.
3. يرفع أدلة ضمن صلاحياته، دون الوصول التلقائي إلى هوية المبلّغ.

### المدقق

1. يراجع سجل التدقيق المتسلسل، الأحداث الأمنية، والتقارير ضمن صلاحياته.
2. لا يعدّل سجلات البيع أو الصيانة أو الأدلة أو Timeline؛ التصحيح يتم عبر **Correction Event** موثق فقط.

---

## 7) تنفيذ سيناريو القبول الكامل يدويًا

استخدم حسابات التطوير أعلاه بعد تشغيل MFA للحسابات الحساسة. هذا السيناريو يغطي المسار المطلوب من طرف إلى طرف:

1. سجّل دخول `shop_manager@himaya.test` وأنشئ طلب **محل A**.
2. سجّل دخول المدير (AAL2)، اعتمد محل A، واربط `technician@himaya.test` به كفني نشط.
3. عد إلى مدير المحل وسجل جهازًا بـ IMEI صالح، مثل:

   ```text
   490154203237518
   ```

4. من **تسجيل بيع**، بع الجهاز لمشترٍ وأدخل بياناته، ثم أرفق مستند هوية JPEG/PNG/PDF إذا كان مطلوبًا وفق سياسة الجهة.
5. سجّل دخول الفني، سجّل صيانة/فحص ثم فرمتة لنفس IMEI.
6. سجّل دخول `authorized_officer@himaya.test` بعد TOTP، وافتح بلاغ سرقة لنفس IMEI. ينتقل الجهاز فورًا إلى تنبيه/حالة مبلّغ عنها.
7. عد إلى الفني وافحص IMEI: يجب أن يظهر تنبيه حرج دون بيانات PII أو تفاصيل قضية.
8. عد إلى الموظف المختص، حدّث البلاغ إلى قيد المراجعة ثم تم التحقق ثم نشط، وعيّن موظفًا/مندوبًا من نموذج التعيين.
9. سجّل دخول المندوب بعد TOTP، وأضف متابعة ميدانية للقضية المسندة إليه.
10. سجّل دخول الموظف المختص، حدّث الحالة إلى مسترد ثم مغلق.
11. افتح سجل الجهاز للتحقق من Timeline، ثم افتح سجل التدقيق بحساب المدير/المدقق للتحقق من أحداث البيع والصيانة والفرمتة والبلاغ والتعيين والاسترداد والإغلاق.

هناك اختبار pgTAP مطابق تقريبًا لهذا السيناريو في:

```text
supabase/tests/002_lifecycle_permission_scenario.sql
```

---

## 8) الاختبارات قبل دمج أو نشر أي تغيير

من جذر المشروع:

```bash
npm run check          # TypeScript للواجهة
npm run check:pwa      # صحة manifest وService Worker وأيقونات التطبيق
npm run check:edge     # فحص Deno لكل Edge Function
npm test               # اختبارات Luhn/state machine/static security
npm run build          # بناء إنتاجي للواجهة
npm run secrets:check  # يمنع مفاتيح service-role وJWT-like secrets في الملفات المتعقبة
npm run verify         # يشغل كل ما سبق بالتسلسل
```

وعند توفر Docker وSupabase المحلي:

```bash
npx supabase test db
```

لا تتجاوز `supabase test db`: هو يتحقق من IMEI وRLS وappend-only audit، ويشغل سيناريو دورة الحياة والصلاحيات ورفض جلسة MFA من AAL1.

---

## 9) نشر staging

نفّذ أولًا على مشروع staging منفصل، وليس production:

```bash
supabase login
supabase link --project-ref YOUR_STAGING_PROJECT_REF
cp supabase/.env.example supabase/.env
# املأ supabase/.env بقيم staging وأسرار مستقلة
supabase secrets set --env-file supabase/.env
supabase db push
bash scripts/deploy-functions.sh
npm run verify
```

اضبط من Supabase Dashboard أو إعدادات مشروعك أيضًا:

1. **Auth:** نطاق `site_url` الصحيح وروابط redirect الدقيقة فقط.
2. **Auth:** تأكيد البريد، قوة كلمة المرور، rate limits/anti-brute-force، وTOTP MFA.
3. **Edge secrets:** `ALLOWED_ORIGINS` كقائمة origins كاملة ودقيقة، مثل `https://staging.example.gov`، بلا `*`.
4. **Edge secrets:** مفتاحا التشفير والبحث مختلفان وعشوائيان 32-byte base64url، ولا يخرجان من secret manager.
5. **Storage:** تأكد من تطبيق migrations التي تنشئ `evidence-private` و`device-media-private` و`identity-private` كـ buckets خاصة.
6. **Frontend hosting:** اضبط متغيرات البناء فقط:

   ```dotenv
   VITE_SUPABASE_URL=https://YOUR_STAGING_PROJECT.supabase.co
   VITE_SUPABASE_ANON_KEY=مفتاح-anon-أو-publishable-فقط
   VITE_APP_ENV=staging
   ```

7. **Frontend hosting:** فعّل HTTPS وHSTS و`X-Content-Type-Options: nosniff` و`X-Frame-Options: DENY` وCSP مناسبة لنطاق Supabase الفعلي.
8. نفّذ سيناريو القسم 7 بحسابات staging حقيقية ومقيدة، ثم راجع audit/security logs.

---

## 10) النشر كتطبيق PWA عبر GitHub Pages

توجد قوالب workflow للنشر إلى GitHub Pages مع Service Worker وmanifest وأيقونات قابلة للتثبيت. اتبع الدليل المخصص، ثم أضف القوالب يدويًا من الملف المرفق:

- [النشر كتطبيق PWA عبر GitHub Pages](GITHUB_PAGES_PWA.md)
- [محتوى workflows للإضافة اليدوية](GITHUB_WORKFLOWS_MANUAL.md)

الخلاصة الأمنية: احفظ `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY` فقط في Secrets بناء الواجهة، لأنهما سيظهران في bundle المنشور. احفظ `SUPABASE_SERVICE_ROLE_KEY` ومفاتيح AES/HMAC داخل Supabase Edge Secrets أو GitHub **Environment Secrets** التي يستهلكها workflow الخلفي اليدوي فقط، ولا تضعها تحت أي اسم يبدأ بـ`VITE_`.

## 11) التحضير للإنتاج

بعد نجاح staging فقط:

1. أنشئ مشروع Supabase production مستقلًا. لا تنسخ قاعدة staging أو أسرارها كما هي.
2. أنشئ مفاتيح تشفير/بحث/ingest جديدة، وضعها في secret manager ثم `supabase secrets set`؛ لا تسجلها في terminal history أو Git.
3. املأ `ALLOWED_ORIGINS` بنطاق الإنتاج النهائي فقط، وحدث `APP_REDIRECT_URL` وAuth redirect URLs.
4. راجع كل role/permission واربط كل موظف بوكالته وكل عامل بالمحل المعتمد قبل تفعيل الحساب.
5. جهز أول مدير عبر bootstrap المقيد، ثم فعّل TOTP له قبل أي إدارة من الواجهة.
6. فعّل النسخ الاحتياطية المشفرة وPITR، واختبر الاستعادة في مشروع معزول، وحدد RPO/RTO قانونيًا.
7. راجع سياسة الاحتفاظ بالهوية والأدلة، إجراءات الإفصاح، التفويضات، ومسؤولية DB superadmin.
8. نفّذ `supabase db push` و`bash scripts/deploy-functions.sh` من pipeline محمي، ثم اختبر health/flows بدون بيانات PII حقيقية أولًا.
9. راقب Edge Function logs، محاولات الرفض، rate limits، `security_events`، وhash chain للتدقيق.

**لا تستخدم** `supabase db reset` أو `seed:dev` أو تعديل الجداول مباشرة في الإنتاج. التصحيحات التشغيلية تكون بأحداث تصحيح موثقة؛ وأي تغيير مخطط يكون migration أمامي قابل للمراجعة.

---

## 12) معالجة المشكلات الشائعة

| العرض | السبب المرجح | الإجراء |
|---|---|---|
| شاشة إعداد الاتصال | متغيرات `VITE_*` غير موجودة أو غير صالحة | انسخ `.env.example` وأعد تشغيل Vite بعد ضبط URL/anon key |
| `مصدر الطلب غير مسموح` | `ALLOWED_ORIGINS` لا يطابق origin المتصفح | أضف الأصل كاملاً بلا `/` أخير وأعد نشر/تشغيل الدوال |
| `يلزم التحقق بخطوتين` | الجلسة AAL1 | فعّل TOTP من صفحة أمان الحساب وتحقق من الرمز |
| الحساب pending أو لا تظهر قوائم | لم يمنح دورًا/لم يفعل الحساب | استخدم المدير لتفعيل الحساب وتعيين الدور والنطاق |
| لا يستطيع موظف فتح بلاغ أو رؤية قضية | لا يوجد agency نشط أو هي خارج النطاق | اربط المستخدم بوكالة نشطة؛ لا تتجاوز ذلك بتعديل client |
| لا يستطيع الفني العمل | المحل غير approved/verified أو الفني غير مربوط به | اعتمد المحل واربط الفني كمستخدم محل نشط |
| فشل رفع ملف | نوع/حجم الملف أو object verification غير مطابق | استخدم النوع المسموح والحجم المسموح، وتحقق من bucket/migrations/secrets |
| فشل `supabase test db` | Docker أو Supabase المحلي غير جاهز | شغّل Docker Desktop، ثم `npx supabase start` و`npx supabase db reset` |

---

## 13) أين توجد المراجع التفصيلية

- [المعمارية](ARCHITECTURE.md): جداول البيانات، حدود Edge، وRLS.
- [المراجعة الأمنية](SECURITY.md): الأسرار، MFA، التخزين الخاص، التدقيق، والاستجابة للحوادث.
- [النشر](DEPLOYMENT.md): أوامر النشر المختصرة.
- [GitHub Pages PWA](GITHUB_PAGES_PWA.md): الأسرار، النشر، والمسار والتثبيت من المتصفح.
- `supabase/tests/002_lifecycle_permission_scenario.sql`: سيناريو قبول آلي قابل للتشغيل محليًا.
