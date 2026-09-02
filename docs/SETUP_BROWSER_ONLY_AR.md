# تشخيص وإعداد «حماية» من المتصفح فقط (بدون تيرمينال)

هذا الدليل لمن لا يستخدم سطر الأوامر إطلاقًا، ويعمل من المتصفح فقط: تشخيص سبب عدم اتصال التطبيق بالقاعدة، ثم إنشاء الجداول، واعتماد حساب المسؤول، وتسجيل الدخول وتجربة التطبيق.

> **الفكرة الأساسية:** التطبيق المنشور على GitHub Pages هو ملفات ثابتة فقط. قاعدة البيانات والمصادقة والتخزين والدوال تعيش كلها في **Supabase**. لذلك «عدم الاتصال» لا يعني عطلًا في الواجهة، بل يعني عادةً أحد أمرين: (أ) لم تُضمَّن إعدادات الاتصال في البناء، أو (ب) مشروع Supabase فارغ (لا جداول ولا أدوار ولا دوال).

---

## 1) تشخيص سريع حسب ما تراه في الشاشة

| ما تراه في التطبيق | السبب المرجح | الحل |
|---|---|---|
| شاشة **«يلزم إعداد الاتصال الآمن»** | البناء لم يتضمن `VITE_SUPABASE_URL` أو `VITE_SUPABASE_ANON_KEY` | أضف السرّين في GitHub ثم أعد تشغيل بناء Pages (القسم 4) |
| صفحة تسجيل الدخول تظهر، لكن بعد الدخول يتوقف التحميل أو تظهر أخطاء | لا توجد جداول/أدوار، أو دوال Edge غير منشورة | طبّق المخطط (القسم 3 أو 5) وانشر الدوال (القسم 4) |
| في وحدة التحكم (F12) تظهر أخطاء `Failed to fetch` أو `404` لدوال مثل `/functions/v1/bootstrap` | دوال Edge غير منشورة | انشر الدوال عبر workflow الخلفي (القسم 4) |
| خطأ `relation "public.users" does not exist` في SQL Editor | migrations لم تُطبَّق على هذا المشروع أو أنك على مشروع آخر | طبّق المخطط على المشروع الصحيح (القسم 3/5) |
| خطأ `لم يُعثر على حساب Auth ...` | الحساب غير موجود أو بريده غير مؤكد | أنشئ الحساب وأكد بريده ثم نفّذ bootstrap (القسم 6) |

---

## 2) أين تُحفظ كل قطعة

| القطعة | مكانها |
|---|---|
| الواجهة | GitHub Pages (`https://malek9art.github.io/Anti-theft-of-phones/`) |
| المصادقة + الجداول + RLS | Supabase (PostgreSQL + Auth) |
| الدوال الحساسة | Supabase Edge Functions |
| الملفات (أدلة/هوية) | Supabase Storage (buckets خاصة) |

لا يوجد أي اتصال مباشر بين GitHub Pages وقاعدة بياناتك إلا عبر عنوان مشروع Supabase الذي يُزرع في الواجهة وقت البناء.

---

## 3) إنشاء الجداول يدويًا من المتصفح (SQL Editor) — الطريقة البديلة الآمنة

هذه الطريقة تنشئ كل الجداول والدوال والسياسات دفعة واحدة، بدون CLI.

### 3.1 جهّز ملف المخطط الكامل

في المستودع يوجد ملف جاهز يدمج كل الـ migrations بالترتيب الصحيح داخل معاملة واحدة:

```text
supabase/scripts/schema_combined.sql
```

افتح الملف على GitHub من:
`https://github.com/malek9art/Anti-theft-of-phones/blob/main/supabase/scripts/schema_combined.sql`

اضغط زر **Copy raw file** (أو افتح Raw وانسخ الكل).

> إن غُيّرت الـ migrations لاحقًا، أعد توليد هذا الملف بأمر `node scripts/build-schema-combined.mjs` (يتطلب تيرمينال)، واختبار `tests/security/schema-combined.test.mjs` يمنع نسيان المزامنة.

### 3.2 الصقه في SQL Editor

1. افتح [Supabase Dashboard](https://supabase.com/dashboard) → اختر **مشروعك**.
2. من القائمة اليسرى اختر **SQL Editor**.
3. أنشئ query جديد، والصق **محتوى الملف كاملًا** (يبدأ بتعليقات عربية وينتهي بـ `commit;`).
4. اضغط **Run**.

ينفَّذ كل شيء داخل `begin; ... commit;` فإما نجح الكل أو لم يُطبَّق شيء.

### 3.3 تحقق من النتيجة

نفّذ هذا الاستعلام بعدها:

```sql
select to_regclass('public.users')    as users_ok,
       to_regclass('public.roles')    as roles_ok,
       to_regclass('public.user_roles') as user_roles_ok,
       (select count(*) from public.roles where key = 'system_admin') as system_admin_role;
```

النتيجة الصحيحة: الأعمدة الثلاثة الأولى ليست `null` (تعيد أسماء الجداول)، والعدد `1` لدور `system_admin`.

### 3.4 تحذير مهم بخصوص سجل الـ migrations

طريقة SQL Editor تنشئ الكائنات لكنها **لا تسجّل** الملفات في `supabase_migrations.schema_migrations`. لذلك إذا استخدمت لاحقًا `supabase db push` على نفس المشروع فسيحاول إعادة تطبيق الملفات فيتعارض مع الكائنات الموجودة.

- **الأفضل:** استخدم workflow الخلفي (القسم 4) لتطبيق المخطط، واجعل SQL Editor للعمليات غير المتعلقة بالمخطط فقط (مثل bootstrap المسؤول).
- **إن اضطررت لطريقة SQL Editor ثم أردت CLI لاحقًا:** نفّذ `supabase migration repair --status applied <version>` لكل ملف (مستند في `docs/RUNBOOK_AR.md`)، أو أنشئ مشروعًا جديدًا وطبّق بالطريقة الصحيحة.

---

## 4) النشر الكامل من المتصفح عبر GitHub Actions (الطريقة الموصى بها)

هذه الطريقة تطبّق الجداول وترسل أسرار الدوال وتنشر الـ 48 دالة Edge — كلها بأزرار في المتصفح.

### 4.1 أنشئ مشروع Supabase وخذ القيم

1. من Dashboard → **New project**، اختر اسمًا ومنطقة قريبة، وسجّل **Database password** في مكان آمن.
2. بعد الإنشاء افتح **Project Settings → API** وانسخ:
   - `Project URL` (مثل `https://xxxx.supabase.co`)
   - `anon` / `publishable` key
   - `service_role` key (ستضعه في GitHub Environment فقط، لا في المتصفح)
3. من **Project Settings → General** انسخ **Reference ID** (هو `xxxx` في الرابط).

### 4.2 أضف ملفات workflow يدويًا (خطوة مالك المستودع)

اتصال التكامل الحالي لا يملك صلاحية `workflows`، لذا لا يمكنه رفعها عنك. من مستودع GitHub افتح **Add file → Create new file** والصق كل ملف من النسخ الكاملة في:

```text
docs/GITHUB_WORKFLOWS_MANUAL.md
```

المسارات الثلاثة المطلوبة:

```text
.github/workflows/ci.yml
.github/workflows/deploy-pages.yml
.github/workflows/deploy-supabase.yml
```

### 4.3 أضف أسرار الواجهة (لبناء Pages)

`Settings → Secrets and variables → Actions → Secrets → New repository secret`:

```text
VITE_SUPABASE_URL        =  https://xxxx.supabase.co
VITE_SUPABASE_ANON_KEY   =  مفتاح anon/publishable
```

هاتان القيمتان عامّتان للمتصفح بطبيعتهما، ولا تكشفان أي سر خادم.

### 4.4 أنشئ بيئة staging وأسرار الخلفية

`Settings → Environments` → أنشئ بيئة `staging`، وأضف فيها Environment Secrets:

```text
SUPABASE_ACCESS_TOKEN      (من حساب Supabase: Account → Access Tokens)
SUPABASE_PROJECT_REF       (المرجع xxxx)
SUPABASE_DB_PASSWORD       (كلمة مرور قاعدة البيانات التي سجلتها)
SUPABASE_URL
SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
ALLOWED_ORIGINS            (مثل https://malek9art.github.io بلا نجمات)
APP_REDIRECT_URL           (مثل https://malek9art.github.io/Anti-theft-of-phones/)
SENSITIVE_DATA_ENCRYPTION_KEY   (مفتاح base64url طوله 32 بايت)
SENSITIVE_DATA_LOOKUP_KEY       (مفتاح آخر مختلف تمامًا)
AUTH_EVENT_INGEST_SECRET        (سلسلة عشوائية طويلة)
```

لتوليد مفتاحي التشفير دون تيرمينال: افتح أي مولد base64url عشوائي أو استخدم أدوات مثل `https://generate-secret.vercel.app/32` وأزل أي `=`. **يجب أن يختلف المفتاحان عن بعضهما.**

> `SUPABASE_DB_PASSWORD` ضروري ليعمل `supabase db push` في بيئة CI غير التفاعلية.

### 4.5 شغّل نشر الخلفية

1. تبويب **Actions** → اختر **Deploy Himaya Supabase backend**.
2. **Run workflow** → اختر `staging`.
3. انتظر انتهاء الخطوات (تطبّق migrations، ترسل الأسرار، تنشر الدوال).

### 4.6 شغّل بناء الواجهة

1. تبويب **Actions** → **Deploy Himaya PWA to GitHub Pages** → **Run workflow**.
2. بعد النجاح افتح الرابط من صفحة workflow أو من `Settings → Pages`.

---

## 5) اعتماد أول مسؤول نظام من المتصفح (SQL Editor)

بعد أن تصبح الجداول جاهزة (بالطريقة 3 أو 4):

1. افتح رابط التطبيق وسجّل **حسابًا جديدًا** من شاشة الدخول/التسجيل.
2. أكد البريد الإلكتروني:
   - من رابط التأكيد في بريدك، أو
   - من Supabase Dashboard → **Authentication → Users** → اختر المستخدم → زر **Confirm user**.
3. انسخ **User UUID** من صفحة المستخدم نفسها.
4. في SQL Editor افتح السكربت:

   ```text
   supabase/scripts/bootstrap_first_system_admin.sql
   ```

   (افتحه على GitHub من `https://github.com/malek9art/Anti-theft-of-phones/blob/main/supabase/scripts/bootstrap_first_system_admin.sql` وانسخه.)

5. استبدل القيمة الوحيدة:

   ```sql
   v_target := 'REPLACE_WITH_AUTH_USER_UUID';
   ```

   بمعرّف الحساب الذي نسخته، ثم **Run**.

6. السكربت يتوقف تلقائيًا عند: غياب الجداول، غياب الحساب، أو عدم تأكيد البريد — برسالة عربية واضحة. عند النجاح سيعيد صفًا يتضمن دور `system_admin`.

7. عد إلى التطبيق وسجّل الدخول بهذا الحساب.

---

## 6) تفعيل التحقق بخطوتين (MFA) وتجربة التطبيق

1. بعد الدخول، افتح **أمان الحساب** → **إعداد تطبيق المصادقة (TOTP)**.
2. امسح رمز QR بتطبيق مثل Google Authenticator وأدخل الرمز لتأكيده.
3. الآن جلستك AAL2 ويمكنك تنفيذ العمليات الإدارية الحساسة.
4. ابدأ التجربة وفق سيناريو القبول في `docs/RUNBOOK_AR.md` (قسم «تنفيذ سيناريو القبول الكامل يدويًا»): اعتماد محل، تسجيل جهاز وIMEI، بيع، صيانة وفرمتة، بلاغ، تنبيه عند الفحص، تعيين، استرداد وإغلاق، ومراجعة Timeline وسجل التدقيق.

> للبيانات الحساسة (اسم المشتري/هويته) لا تُعرض نصوص صريحة في الجداول — كلها تُشفَّر في دوال Edge، لذلك **يجب أن تكون الدوال منشورة** (الطريقة 4) قبل تجربة البيع والبلاغ.

---

## 7) حدود العمل من المتصفح فقط (بصراحة)

| المطلوب | هل يمكن من المتصفح؟ | الطريقة |
|---|---|---|
| إنشاء مشروع Supabase | نعم | Dashboard |
| إنشاء الجداول | نعم | SQL Editor (الملف المدمج) أو workflow الخلفي |
| اعتماد أول مسؤول | نعم | SQL Editor (سكربت bootstrap) |
| تفعيل MFA | نعم | من التطبيق |
| نشر Edge Functions | نعم فقط عبر **workflow الخلفي** | لوحة Actions (القسم 4) |
| كتابة/تعديل ملفات workflow | نعم يدويًا | GitHub web editor (نسخ من الملف المرجعي) |
| تطبيق `supabase migration repair` | لا | يتطلب CLI (لاحقًا فقط إذا خلطت الطريقتين) |

**خلاصة القرار:**

- **المسار الكامل الموصى به من المتصفح:** القسم 4 (workflow يطبّق كل شيء) ثم القسم 5 (اعتماد المسؤول) ثم القسم 6 (MFA وتجربة).
- **المسار الاحتياطي للمخطط فقط:** القسم 3 (SQL Editor) ثم القسم 5 و6، مع العلم أنك ستحتاج workflow الخلفي (القسم 4) على أي حال لنشر الدوال اللازمة للبيع/البلاغ.

---

## 8) أسئلة متكررة

**س: لماذا تظهر شاشة الإعداد رغم أن الموقع منشور؟**
ج: لأن البناء الحالي لم يتضمن `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`. أضفهما كأسرار GitHub وأعد تشغيل بناء Pages.

**س: الجداول موجودة والدوال منشورة، لكن الطلب يرجع «مصدر الطلب غير مسموح»؟**
ج: قيمة `ALLOWED_ORIGINS` في أسرار الدوال لا تشمل أصل الموقع. اجعلها `https://malek9art.github.io` (بلا `/` أخيرة وبلا نجمات) ثم أعد نشر الدوال.

**س: هل أحتاج Service Role Key في أي مكان من المتصفح؟**
ج: لا. ضعه فقط في GitHub Environment Secret (لنقله إلى Supabase) أو في أسرار Supabase، ولا تضعه أبدًا في متغير يبدأ بـ `VITE_` أو في SQL Editor.
