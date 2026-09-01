# مراجعة أمنية وتشغيلية

## ضوابط منفذة

- **مصادقة:** Supabase Auth، جلسة JWT مدتها ساعة في local config، دعم TOTP MFA، واجهة enrollment، وإلغاء الجلسات الأخرى. كل RPC/Edge عملية حساسة تتطلب AAL2 من الخادم ولا يعتمد ذلك على إخفاء واجهة أو خيار المستخدم.
- **كلمات المرور:** حد أدنى 12 رمزًا ومتطلبات lower/upper/digit/symbol في `supabase/config.toml`، مع تأكيد بريد إلكتروني.
- **RBAC:** جداول `roles`, `permissions`, `role_permissions`, `user_roles`؛ لا يوجد `if role` وحيد في الواجهة كآلية أمان.
- **RLS:** مفعّل لجميع جداول الأعمال والحساسية؛ لا توجد سياسات كتابة مباشرة للسجلات الحرجة.
- **تفويض خادمي:** Edge Functions تستدعي `api_*`، والدوال تتحقق من `auth.uid()`, account status, permission, scope, ومحل معتمد.
- **PII:** AES-256-GCM في ذاكرة Edge Function فقط؛ HMAC blind indexes مختلفة المفتاح للبحث الدقيق؛ لا plaintext columns.
- **Storage:** buckets خاصة (`evidence-private`, `device-media-private`, `identity-private`) وسياسات deny للمتصفح؛ Signed URLs مؤقتة فقط.
- **عدم العبث:** trigger يمنع حذف أو تحديث sale/repair/format/report history/evidence access/device events/audit. التصحيح عبر `record_corrections`.
- **Audit:** سجل متسلسل بــ SHA-256 hash chain و`pg_advisory_xact_lock` لمنع سباق كتابة chain، مع منع UPDATE/DELETE.
- **مراقبة:** rate limit ذري لكل المستخدم/IP hash، وعدادات IMEI، `security_events` وnotifications، وسجل وصول منفصل للبيانات الحساسة.
- **إدخال/إخراج:** IMEI Luhn في الواجهة وEdge وPostgres، validation لحجم/type الملفات، CSV formula injection protection، CSP وsecurity headers.

## GitHub Pages وPWA

GitHub Pages يستضيف الواجهة الثابتة فقط. `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY` قيمتا متصفح عامتان ويمكن تمريرهما كـ GitHub Actions Secrets للبناء، لكنهما تصبحان جزءًا من bundle المنشور. لا تمرر `SUPABASE_SERVICE_ROLE_KEY` أو مفاتيح التشفير أو `AUTH_EVENT_INGEST_SECRET` لأي متغير `VITE_*` أو workflow Pages. يتوفر قالب workflow خلفي يدوي محمي بـ GitHub Environments لنقل الأسرار إلى Supabase فقط؛ أضفه يدويًا من [ملف workflows](GITHUB_WORKFLOWS_MANUAL.md) ثم راجع [دليل GitHub Pages PWA](GITHUB_PAGES_PWA.md).

## أسرار يجب ضبطها خارج Git

استخدم `supabase/.env.example` كقالب. القيم الآتية لا تدخل أبدًا في `VITE_*` أو التطبيق:

- `SUPABASE_SERVICE_ROLE_KEY`
- `SENSITIVE_DATA_ENCRYPTION_KEY`
- `SENSITIVE_DATA_LOOKUP_KEY`
- `AUTH_EVENT_INGEST_SECRET`

نفّذ قبل النشر:

```bash
supabase secrets set --env-file supabase/.env
npm run secrets:check
```

## ضوابط تشغيلية لازمة قبل الإنتاج

1. عيّن `ALLOWED_ORIGINS` إلى قائمة hosts دقيقة، بلا `*`.
2. غيّر `site_url` وredirect URLs إلى نطاقات الإنتاج فقط.
3. فعّل حماية brute-force / CAPTCHA / rate limits من لوحة Supabase Auth وفق سياسة الجهة.
4. أنشئ أول مدير في جلسة إدارة مقيدة. لا تضف role في client أو migration. اجعله نشطًا، وسجّل دخوله وفعّل TOTP؛ العمليات الحساسة مرفوضة خادميًا ما لم تحمل الجلسة AAL2. يظل `mfa_required` مؤشر سياسة/واجهة إضافيًا وليس وسيلة لتخفيف هذا الشرط.
5. اربط أحداث Auth (`failed_login`, MFA، reset) إلى `ingest-auth-event` بطلب server-to-server يتضمن `x-auth-event-secret`. لا تقبل هذه الدالة JWT للمستخدم.
6. اضبط رصد الأخطاء ومراقبة Edge Functions واحتفظ بالـ logs خارج الحساب التشغيلي.
7. ضع قاعدة بيانات المشروع وStorage تحت نسخ Supabase الاحتياطية، مع backup مشفر وaccess-controlled وversioned واختبار restore دوري.
8. راجع retention القانوني للـ PII والأدلة قبل إدخال بيانات حقيقية؛ حذف قانوني يحتاج event/retention process معتمد، لا DELETE عادي.
9. استخدم خدمة antivirus/quarantine عند الحاجة للملفات قبل تغيير evidence إلى `uploaded` في بيئة متطلبات جنائية.
10. راجع حساب مالك قاعدة البيانات ونسخ backups: hash chain يمنع العبث عبر التطبيق، لكنه ليس بديلًا عن فصل واجبات DB superadmin والنسخ غير القابلة للتعديل.

## حدود الضمان

- الحقول المخفية في UI ليست حماية؛ الحماية الفعلية موجودة في RLS/RPC/Edge.
- `service_role` يتجاوز RLS، لذلك لا يُستخدم إلا داخل Edge Function بعد تفويض RPC واضح؛ لا يوجد في source المتصفح.
- metadata الأدلة قد تكون حساسة. لا يُعاد `storage_path` أو Signed URL في قوائم البلاغات.
- رابط Signed URL قابل للاستخدام حتى انتهاء مدته؛ لذلك يبقى قصيرًا و`Cache-Control: no-store`.

## استجابة مختصرة للحوادث

1. علق الحساب أو المحل عبر API الإدارية وسجّل سببًا.
2. نفّذ «إنهاء الجلسات الأخرى» للحساب المشتبه به.
3. راجع `security_events`, `audit_logs`, `evidence_access_logs`, و`sensitive_data_access_logs`.
4. صدّر تقريرًا ضمن الصلاحية وحافظ على نسخة مشفرة.
5. لا تحذف أي سجل أو دليل أثناء التحقيق؛ استخدم status/correction فقط.
