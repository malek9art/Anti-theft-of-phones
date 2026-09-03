# تشغيل «حماية» من المتصفح فقط (نشر عبر الفرع + SQL يدوي)

هذا الدليل يشرح التشغيل الكامل بدون تيرمينال:
- **الواجهة:** ننشرها **عبر الفرع** (GitHub Pages → Deploy from a branch)، وتعتمد على قيمتين فقط: `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY` (توضعان في ملف `docs/config.js`).
- **الجداول والسياسات:** تُنفَّذ يدويًا في **SQL Editor** في Supabase (ملف واحد جاهز).
- **الدوال (Edge Functions):** خطوة واحدة لا يمكن تنفيذها من SQL Editor — تُنشر مرة واحدة عبر زر في GitHub Actions أو CLI (مفصلة في القسم 5).

> **الفكرة الأساسية:** الموقع على GitHub Pages ملفات ثابتة فقط. القاعدة والمصادقة والتخزين والدوال كلها في Supabase. «عدم الاتصال» سببه عادة: القيمتان غير موجودتين في `docs/config.js`، أو أن مشروع Supabase فارغ (لا جداول ولا دوال).

---

## 1) تشخيص سريع حسب ما تراه

| ما تراه | السبب المرجح | الحل |
|---|---|---|
| شاشة «يلزم إعداد الاتصال الآمن» | `docs/config.js` فارغ أو قيمه غير صحيحة | املأ القيمتين في `docs/config.js` (القسم 2) |
| بعد تسجيل الدخول يتوقف التحميل على «جارٍ التحقق من صلاحيات الحساب…» | دوال Edge غير منشورة (أولها `bootstrap`) | انشر الدوال مرة واحدة (القسم 5) |
| خطأ `relation "public.users" does not exist` في SQL Editor | الجداول لم تُنشأ | نفّذ `schema_combined.sql` (القسم 4) |
| خطأ `لم يُعثر على حساب Auth ...` | الحساب غير موجود أو بريده غير مؤكد | أنشئ الحساب وأكد بريده ثم نفّذ bootstrap (القسم 6) |

---

## 2) نشر الواجهة عبر الفرع (وليس Actions)

### 2.1 فعّل Pages من الفرع

1. افتح مستودع GitHub → **Settings → Pages**.
2. عند **Build and deployment** اختر **Source: Deploy from a branch**.
3. **Branch:** اختر الفرع `arena/01a06464-anti-theft-of-phones` (أو `main` بعد الدمج).
4. **Folder:** اختر `/docs` ثم **Save**.

الموقع المنشور موجود مسبقًا في مجلد `docs/` (الواجهة المبنية). أي push لهذا الفرع يحدّث الموقع تلقائيًا.

### 2.2 ضع القيمتين في ملف الإعداد

الواجهة تقرأ القيمتين وقت التشغيل من `docs/config.js` (لأن النشر عبر الفرع لا يحقن أسرار GitHub):

1. في المستودع افتح الملف `docs/config.js` واضغط أيقونة التعديل (✏️).
2. ضع القيمتين:

   ```js
   window.__HIMAYA_CONFIG__ = {
     SUPABASE_URL: "https://xxxx.supabase.co",   // Project URL
     SUPABASE_ANON_KEY: "eyJ...",                // anon/publishable key
   };
   ```

3. اضغط **Commit changes**.

> هاتان القيمتان عامّتان بطبيعتهما (تظهران في متصفح كل زائر)، والحماية الفعلية في RLS والدوال. **لا تضع هنا** Service Role Key أو مفاتيح التشفير. القيمتان نفسهما هما `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY` اللتان وضعتهما في أسرار GitHub — تُقرآن هنا مباشرة.

---

## 3) متطلبات في Supabase (Dashboard فقط)

1. من **Project Settings → API** انسخ `Project URL` و`anon/publishable key` — هما قيمتا القسم 2.2.
2. تأكد من **Authentication → Providers → Email** مفعّل (وهو مفعّل افتراضيًا).
3. لاحقًا اضبط **Authentication → URL Configuration**:
   - `Site URL`: `https://malek9art.github.io/Anti-theft-of-phones/`
   - `Redirect URLs`: أضف `https://malek9art.github.io/Anti-theft-of-phones/`

---

## 4) إنشاء الجداول وسياسات الأمان يدويًا (SQL Editor)

### 4.1 انسخ ملف المخطط الكامل

في المستودع يوجد ملف جاهز يدمج كل الـ migrations (الجداول + الدوال + RLS + السياسات + الـ buckets الخاصة) بالترتيب داخل معاملة واحدة:

```text
supabase/scripts/schema_combined.sql
```

افتحه من GitHub (اختر فرعك الحالي) واضغط **Copy raw file**، أو افتح الرابط:

```text
https://raw.githubusercontent.com/malek9art/Anti-theft-of-phones/arena/01a06464-anti-theft-of-phones/supabase/scripts/schema_combined.sql
```

### 4.2 الصقه ونفّذه

1. [Supabase Dashboard](https://supabase.com/dashboard) → مشروعك → **SQL Editor**.
2. query جديد → الصق المحتوى كاملًا → **Run**.

ينفَّذ الكل داخل `begin; ... commit;` فإما نجح كل شيء أو لم يُطبَّق شيء.

### 4.3 تحقق

```sql
select to_regclass('public.users') as users_ok,
       to_regclass('public.roles') as roles_ok,
       to_regclass('public.user_roles') as user_roles_ok,
       (select count(*) from public.roles where key = 'system_admin') as system_admin_role;
```

الصحيح: الأعمدة الثلاثة الأولى ليست `null`، والعدد `1`.

> **ملاحظة صريحة:** هذه الطريقة تنشئ الكائنات لكنها لا تسجّل الملفات في سجل `supabase_migrations`. إذا استخدمت لاحقًا `supabase db push` على نفس المشروع فقد يتعارض؛ الحل موثق في `docs-source/RUNBOOK_AR.md` (قسم migration repair).

---

## 5) نشر الدوال (Edge Functions) — خطوة واحدة لا يمكن عملها في SQL Editor

الـ 48 دالة Edge (تشمل `bootstrap` التي يحتاجها تسجيل الدخول نفسه، والتشفير، والروابط الموقّعة، ومعدل الطلبات) **ليست كائنات قاعدة بيانات**، فلا يمكن إنشاؤها من SQL Editor. تُنشر بطريقة واحدة من الاثنتين:

### الطريقة أ — زر واحد في GitHub Actions (أسهل للمتصفح)

1. أضف ملف `.github/workflows/deploy-supabase.yml` يدويًا (انسخ محتواه من `docs-source/GITHUB_WORKFLOWS_MANUAL.md` عبر **Add file → Create new file**).
2. ضع أسرار الخلفية في **Repository secrets** (متاحة لكل الـ workflows):

   ```text
   SUPABASE_ACCESS_TOKEN      ← من supabase.com → حسابك → Access Tokens
   SUPABASE_PROJECT_REF       ← من Project Settings → General
   SUPABASE_DB_PASSWORD       ← كلمة مرور القاعدة
   SUPABASE_URL
   SUPABASE_ANON_KEY
   SUPABASE_SERVICE_ROLE_KEY
   ALLOWED_ORIGINS            ← https://malek9art.github.io  (بلا نجمات)
   APP_REDIRECT_URL           ← https://malek9art.github.io/Anti-theft-of-phones/
   SENSITIVE_DATA_ENCRYPTION_KEY   ← سلسلة عشوائية 32 بايت base64url
   SENSITIVE_DATA_LOOKUP_KEY       ← سلسلة عشوائية أخرى مختلفة
   AUTH_EVENT_INGEST_SECRET        ← سلسلة عشوائية طويلة
   ```

3. أنشئ بيئة فارغة باسم `staging` (Settings → Environments) لأن الـ workflow يشير إليها.
4. تبويب **Actions → Deploy Himaya Supabase backend → Run workflow → staging**.

> هذه خطوة **نشر خلفي لمرة واحدة**، وهي منفصلة تمامًا عن نشر الواجهة عبر الفرع الذي اخترته — ليست جزءًا من تشغيلك اليومي.

### الطريقة ب — Supabase CLI (إن توفر تيرمينال عندك)

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set --env-file supabase/.env
bash scripts/deploy-functions.sh
```

> بدون الدوال، سيتوقف التطبيق عند شاشة «جارٍ التحقق من صلاحيات الحساب…» بعد تسجيل الدخول، لأن أول طلب (`bootstrap`) يمر عبر دالة Edge.

---

## 6) اعتماد أول مسؤول نظام (SQL Editor)

بعد إنشاء الجداول ونشر الدوال:

1. سجّل حسابًا جديدًا من شاشة الدخول/التسجيل.
2. أكد البريد: من رابط التأكيد، أو من Dashboard → **Authentication → Users → Confirm user**.
3. انسخ **User UUID** من صفحة المستخدم.
4. افتح السكربت `supabase/scripts/bootstrap_first_system_admin.sql` من GitHub وانسخه إلى SQL Editor، واستبدل القيمة الوحيدة:

   ```sql
   v_target := 'REPLACE_WITH_AUTH_USER_UUID';
   ```

5. **Run**. السكربت يتوقف تلقائيًا عند غياب الجداول أو الحساب أو تأكيد البريد، ويمنح دور `system_admin` ويسجّل الحدث في سجل التدقيق.
6. سجّل الدخول وستجد صلاحيات المدير.

---

## 7) تفعيل MFA وتجربة التطبيق

1. من التطبيق: **أمان الحساب → إعداد تطبيق المصادقة (TOTP)**، امسح QR وأدخل الرمز.
2. بعدها جلستك AAL2 ويمكنك تنفيذ العمليات الحساسة.
3. جرّب السيناريو الكامل (موثق في `docs-source/RUNBOOK_AR.md`): اعتماد محل → تسجيل جهاز وIMEI → بيع → صيانة وفرمتة → بلاغ → تنبيه عند الفحص → تعيين → استرداد وإغلاق → Timeline وسجل التدقيق.

---

## 8) أسئلة متكررة

**س: لماذا أرى شاشة الإعداد رغم أن الموقع منشور؟**
ج: `docs/config.js` لا يحتوي القيمتين أو أن القيم غير صحيحة. عدّل الملف ثم Commit.

**س: أين أضع مفتاح Service Role؟**
ج: فقط في أسرار GitHub (للـ workflow الخلفي) أو أسرار Supabase. لا في `config.js` ولا في SQL Editor ولا في أي `VITE_*`.

**س: لماذا لا تكفي الجداول وحدها؟**
ج: الجداول توفر البيانات والصلاحيات، لكن التطبيق يتكلم مع قاعدة البيانات عبر 48 دالة Edge (للتشفير والروابط الموقّعة ومعدل الطلبات). لا بد من نشرها مرة واحدة (القسم 5).
