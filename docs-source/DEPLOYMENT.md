# تشغيل ونشر حماية

> لنشر الواجهة كتطبيق قابل للتثبيت عبر GitHub Pages، راجع أيضًا [دليل GitHub Pages PWA](GITHUB_PAGES_PWA.md). لا تضع أسرار الخادم في متغيرات `VITE_*`.

## المتطلبات

- Node.js 22+
- Supabase CLI حديث
- Docker لتشغيل Supabase محليًا (غير متاح داخل هذه بيئة Arena الحالية)
- مشروع Supabase منفصل لكل بيئة: development / staging / production

## تشغيل الواجهة

```bash
cp .env.example .env
# أضف VITE_SUPABASE_URL و VITE_SUPABASE_ANON_KEY فقط
npm ci
npm run dev
```

المفتاح العام Anon/Publishable آمن للمتصفح عند وجود RLS. **لا تضف** service role key إلى `.env` الخاص بالواجهة.

## إعداد Supabase محليًا

```bash
supabase start
supabase db reset
# انسخ القيم التي يعرضها supabase status إلى supabase/.env (غير متعقب)
supabase secrets set --env-file supabase/.env
bash scripts/deploy-functions.sh
```

لإنشاء حسابات وهمية محلية فقط:

```bash
export SUPABASE_URL=http://127.0.0.1:54321
export SUPABASE_ANON_KEY=...
export SUPABASE_SERVICE_ROLE_KEY=...
ALLOW_DEVELOPMENT_SEED=true npm run seed:dev
```

يرفض `seed-dev.mjs` أي URL ليس `localhost`/`127.0.0.1`. لا توجد seeds تلقائية في migrations ولا بيانات تجريبية في الإنتاج.

## نشر staging/production

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase secrets set --env-file supabase/.env
bash scripts/deploy-functions.sh
npm run verify
```

قبل النشر عدّل `supabase/config.toml` أو لوحة المشروع لتضبط production `site_url`, redirect URLs وMFA. اضبط متغير `ALLOWED_ORIGINS` على كل origins للواجهة (بدون wildcard).

## إنشاء أول مدير نظام

بعد تطبيق migrations وتأكيد حساب المدير عبر Supabase Auth، استخدم السكربت الآمن الذي يتوقف ذاتيًا عند غياب migrations أو الحساب أو تأكيد البريد:

```text
supabase/scripts/bootstrap_first_system_admin.sql
```

افتحه في Supabase SQL Editor، واستبدل القيمة الوحيدة `REPLACE_WITH_AUTH_USER_UUID` بمعرّف حساب Auth المؤكد، ثم نفّذه مرة واحدة. السكربت يضمن وجود ملف `public.users`، يفعّل الحساب، يمنح دور `system_admin`، ويكتب حدثًا في سجل التدقيق. لا يحتوي على UUID أو بريد أو بيانات شخصية ثابتة.

يسجل المدير الدخول ويفعّل TOTP من «أمان الحساب» قبل أي عملية إدارية حساسة. ترفض الدوال الحساسة من الخادم جلسات AAL1 لجميع الأدوار، بغض النظر عن قيمة `mfa_required`؛ راجع سجل التدقيق بعد الإجراء.

## الاختبارات

```bash
npm run check
npm run check:pwa
npm run check:edge
npm test
npm run build
npm run secrets:check
# مع Docker/Supabase المحلي:
npx supabase test db
```

`npm test` يغطي Luhn، state transitions، وعدم تسريب service role، ووجود RLS/immutable audit/storage policy. اختبار pgTAP في `supabase/tests` يضيف تحقق schema/RLS عند وجود Supabase محلي.

## النسخ الاحتياطي والتعافي

- فعّل daily PITR/backup من مزود Supabase المناسب للسياسة.
- نسخ export مشفرة خارج الحساب التشغيلي، access-controlled وversioned.
- اختبر restore إلى مشروع معزول كل ربع سنة، ثم تحقق من `audit_logs.entry_hash` chain.
- وثّق RPO/RTO قانونيًا؛ لا تفترض أن backup وحده يحقق عدم العبث.
