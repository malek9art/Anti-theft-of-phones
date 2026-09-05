# برومبت احترافي: إعادة بناء منصة «حماية | نظام مكافحة سرقة الأجهزة» من الصفر

> **هذا برومبت جاهز للّصق** في أي مساعد برمجة (Arena Agent Mode / Cursor / Claude / غيرها)
> داخل **مستودع GitHub جديد وفارغ**. الهدف: بناء التطبيق كاملًا من الصفر بصورة أكثر
> احترافية، وجاهز للعمل على **نفس مشروع Supabase الحالي** (نفس الحساب/قاعدة البيانات).

---

## 0) سياق التنفيذ (اقرأ أولًا)

1. تعمل داخل مستودع GitHub **جديد كليًا** (فارغ) أنشأه المستخدم لهذا الغرض.
2. القاعدة الخلفية هي **نفس مشروع Supabase القائم** — لا تُنشئ مشروع Supabase جديدًا:
   - `SUPABASE_URL` = `https://chgauqwrfcdjlpmrpjda.supabase.co`
   - `SUPABASE_ANON_KEY` = `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNoZ2F1cXdyZmNkamxwbXJwamRhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyOTExODEsImV4cCI6MjEwMzg2NzE4MX0.FqkoPQU7JqCl0-QWiquVK6UpFoOT0B010ySVlT3x0y0`
3. هاتان القيمتان **عامّتان بطبيعتهما** (مفتاح `anon`) ويجوز وضعهما في ملف إعداد المتصفح.
4. **ممنوع منعًا باتًا** أن يظهر في الكود أو المستودع أو أي متغير يبدأ بـ `VITE_`:
   Service Role Key، كلمة مرور قاعدة البيانات، مفاتيح التشفير، أو أي سر خادم.
   توضع هذه الأسرار في **GitHub Secrets** أو بيئة CLI فقط.
5. قبل البدء، شغّل سكربت التصفير في **Supabase SQL Editor**:
   ملف `supabase/scripts/reset_all_objects.sql` (إن وُجد في المشروع القديم، وإلا أنشئه
   بذات المحتوى المذكور في هذا البرومبت) لمسح كل كائنات البناء السابق. السكربت Idempotent.

---

## 1) المنتج

منصة ويب عربية **RTL** باسم **«حماية | نظام مكافحة سرقة الأجهزة»** لإدارة دورة حياة الأجهزة
(هواتف) بالاعتماد على **IMEI** كمعرّف موثوق، مع ربط الجهات المختصة بمحلات الصيانة والبيع:

- **هوية الجهاز:** تسجيل جهاز برقم IMEI (واختياري IMEI ثانٍ Dual-SIM) + ماركة/موديل/لون/رقم تسلسلي/صور، مع خط زمني غير قابل للحذف.
- **البيع:** تسجيل عملية بيع وربطها بمشتري تُشفَّر بياناته الحساسة (اسم/هاتف/رقم وطني) ولا تُعرض كنص صريح.
- **الصيانة والفرمتة:** استلام فني للجهاز ← فحص خادمي للـ IMEI ← تنبيه أمني إن كان مبلّغًا ← تسجيل عملية صيانة/فرمتة برقم عملية فريد.
- **بلاغات السرقة:** إنشاء بلاغ، مسار حالات (مسودة→مقدّم→قيد المراجعة→تم التحقق→نشط→مُحال→تم الاسترداد→مغلق)، إحالة لموظف/مندوب، متابعات، أدلة (صور/مستندات) بمستويات وصول، ورفع راية "مسروق/تحت التنبيه" على الجهاز فورًا.
- **الاسترداد:** انتقال الحالة إلى "مسترد" عند إغلاق البلاغ بعد الاسترداد.
- **الفحص العام:** أي مستخدم مصرّح يفحص IMEI ويرى نتيجة أمنية (بلاغ نشط؟) دون كشف هوية المبلّغ.
- **الجهات والمحلات:** طلب اعتماد محل ← موافقة/تعليق ← ربط موظفين وفنيين.
- **المستخدمون والأدوار:** إدارة المستخدمين، دعوات، تفعيل/تعطيل، إسناد أدوار وصلاحيات.
- **التدقيق:** سجل تدقيق **تسلسلي التجزئة (hash chain)** مضاد للعبث، وسجل وصول للبيانات الحساسة، وأحداث أمنية.
- **التقارير:** تصدير ملخصات (مبيعات/صيانة/فرمتة/بلاغات) بحدود صلاحيات.
- **الأمان الذاتي:** تسجيل دخول + **MFA (TOTP)** إلزامي للعمليات الحساسة (AAL2)، تغيير كلمة المرور، إلغاء الجلسات الأخرى.
- **التنبيهات:** إشعارات داخلية مرتبطة بالكيانات (جهاز/بلاغ).

---

## 2) الرزم والبنية التقنية

### الواجهة (Frontend)
- **React 18 + TypeScript + Vite** (PWA قابلة للتثبيت، واجهة عربية RTL كاملة).
- توجيه بـ **HashRouter** عند النشر على GitHub Pages (لأن Pages لا يعيد كتابة مسارات BrowserRouter).
- حالة مصادقة مركزية عبر Context، عميل Supabase واحد، استدعاءات الخادم عبر **Edge Functions** فقط.
- تصميم متجاوب بثلاث نقاط توقف (حاسوب / لوحي / جوال) مع **قائمة جانبية + شريط سفلي + قائمة منزلقة (drawer)**.
- إتاحة وصول: روابط تخطّي، ARIA، إدارة تركيز، تباين واضح، دعم لوحة المفاتيح.
- حالات واجهة موحّدة: تحميل / فارغ / خطأ / ممنوع في كل شاشة.

### الخلفية (Backend = Supabase)
- **PostgreSQL + RLS** بمبدأ "المنع افتراضيًا" (Deny by default).
- دوال **SECURITY DEFINER** في مخطط `public` و`private` (مع `set search_path` صريح) لكل عملية حساسة.
- **Edge Functions** (Deno/TypeScript) لكل نقطة دخول أمامية؛ الواجهة لا تلمس الجداول مباشرة.
- **تخزين خاص (private buckets)** مع **روابط موقّعة** تُصدر بعد تحقق قاعدة بيانات + تسجيل وصول.
- **مصادقة Supabase Auth + MFA**، وفرض **AAL2** خادميًا لكل عملية حساسة.
- **تحديد معدل** للطلبات الحساسة، وتسجيل الأحداث المرفوضة.

### النشر
- **GitHub Pages عبر الفرع** (Source = Deploy from a branch → فرع النشر → مجلد `/docs`).
- الموقع المبنى يُحفظ في مجلد `docs/` داخل المستودع.
- إعدادات الاتصال العام تُقرأ وقت التشغيل من `docs/config.js` (شكل `window.__HIMAYA_CONFIG__ = { SUPABASE_URL, SUPABASE_ANON_KEY }`) وتحميلها **قبل** وحدة التطبيق.
- المخطط يُنفَّذ يدويًا في **Supabase SQL Editor** (ملف واحد مُدمج) + سكربت أول مدير.
- دوال الحافة تُنشر **مرة واحدة** عبر GitHub Actions (عمل خلفي بمتغيرات `SUPABASE_ACCESS_TOKEN` و`SUPABASE_PROJECT_ID` و`SUPABASE_DB_PASSWORD`) أو Supabase CLI.

---

## 3) نموذج البيانات (خلاصة — ابنِ تفاصيله في migrations مرقّمة)

- **الهوية/الصلاحيات:** `roles`, `permissions`, `role_permissions`, `user_roles`, `users` (مرتبطة بـ `auth.users`)، `agencies`, `delegates`, `locations`, `shops`, `shop_users`, `technicians`.
- **الأجهزة:** `devices`, `device_imeis`, `device_media`, `device_events`, `device_status_transitions`.
- **التجارة:** `customers`, `customer_sensitive_data` (نص مشفَّر + أعمدة lookup hash)، `sales`, `sale_items`.
- **الصيانة:** `repair_records`, `format_records`.
- **البلاغات:** `stolen_reports`, `report_status_history`, `report_follow_ups`, `evidence`, `evidence_access_logs`, `report_status_transitions`.
- **الرقابة:** `audit_logs` (entry_hash/previous_hash/sequence_number)، `sensitive_data_access_logs`, `security_events`, `record_corrections`, `notifications`, `system_settings`, `api_rate_limit_windows`.
- الأنواع (`enums`): حالات الجهاز، حالات البلاغ، الأولوية، حالة الدليل، حالة الحساب، حالة المحل، نوع الإشعار، نوع الوسائط، حالة التحقق.

---

## 4) الأدوار والصلاحيات (ثابتة — لا تحذف)

**الأدوار:** `system_admin`, `authorized_officer`, `investigation_officer`, `delegate`, `shop_manager`, `technician`, `auditor`.

**الصلاحيات (31):** `view_device`, `view_all_devices`, `search_imei`, `create_device`, `create_sale`, `view_sales`, `create_repair`, `create_format_record`, `view_customer`, `view_identity`, `view_sensitive_data`, `create_stolen_report`, `review_report`, `view_all_reports`, `assign_case`, `change_report_status`, `update_follow_up`, `upload_evidence`, `view_evidence`, `view_audit_logs`, `manage_shops`, `manage_shop_staff`, `approve_shop`, `suspend_shop`, `manage_users`, `manage_permissions`, `view_dashboard`, `generate_reports`, `view_security_events`, `manage_system_settings`, `correct_record`.

**نقاط دخول Edge Functions (الأدنى):** `bootstrap`, `get-dashboard`, `get-notifications`, `mark-notification-read`, `check-imei`, `search-records`, `search-sensitive-customer`, `access-sensitive-data`, `create-device`, `register-sale`, `create-repair`, `create-format-record`, `create-stolen-report`, `add-report-follow-up`, `update-report-status`, `assign-report`, `get-case-assignees`, `submit-shop`, `approve-shop`, `suspend-shop`, `link-shop-user`, `invite-user`, `set-user-roles`, `update-user-status`, `get-users`, `get-shops`, `get-devices`, `get-device-timeline`, `get-reports`, `get-report-detail`, `get-audit-logs`, `get-security-events`, `resolve-security-event`, `generate-report`, `update-system-setting`, `revoke-other-sessions`, `ingest-auth-event`, `security-event` + دوال رفع/تحميل الوسائط والأدلة (create/complete/upload/url).

---

## 5) الثوابت الأمنية (غير قابلة للتفاوض)

1. لا Service Role Key ولا مفاتيح تشفير ولا أسرار خادم في الواجهة أو في أي متغير `VITE_*` (الاستثناء الوحيد: `VITE_SUPABASE_URL` و`VITE_SUPABASE_ANON_KEY`).
2. التنفيذ الخادمي فقط: لا تُوثَّق أي صلاحية اعتمادًا على الواجهة؛ RLS ودوال SECURITY DEFINER هي المرجع.
3. الدلاء التخزينية **خاصة دائمًا**؛ المتصفح يستلم روابط موقّعة مؤقتة فقط.
4. لا حقن كتابة مباشر من `anon`/`authenticated` على السجلات الحرجة.
5. السجلات الحرجة **append-only**: لا حذف ولا تعديل؛ التصحيح فقط عبر حدث تصحيح موثّق (`record_corrections`).
6. التحقق من IMEI: **الطول 15 + أرقام فقط + خوارزمية Luhn** (وليس مجرد regex).
7. لا ادّعاء تتبّع موقع الجهاز من IMEI وحده.
8. لا بيانات تجريبية ولا حساب مدير ثابت؛ أول مدير يُنشأ عبر سكربت bootstrap آمن بعد تسجيل مستخدم Auth.
9. لا تضعف RLS أو MFA أو أذونات التخزين أبدًا لإنجاح الاختبارات.
10. لا تُسأل عن Service Role Key أو كلمة مرور قاعدة البيانات في المحادثة.

---

## 6) المزالق المعروفة من البناء السابق (يجب تفاديها — مع اختبار انحدار لكلٍّ منها)

هذه أخطاء وقعت فعليًا وأُصلحت؛ لا تكررها، وأضف اختبارًا يمنع عودتها:

1. **Luhn:** حلقة `for i in reverse 1..15` لا تنفَّذ إطلاقًا (0 تكرار) فتمر أي 15 رقمًا. الصحيح `for i in reverse 15..1 loop`. أضف اختبار: `is_valid_imei('490154203237518') = true` و`...'490154203237519' = false`.
2. **أقواس `jsonb_agg` داخل `coalesce`:** لا تضع `, '[]'::jsonb)` قبل `from (...)`. الشكل الصحيح:
   `select jsonb_agg(jsonb_build_object(...) order by q.created_at desc) from (...) q` ثم إغلاق `coalesce`.
3. **enum في INSERT..SELECT:** أي إدراج نص في عمود enum عبر SELECT يحتاج تحويلًا صريحًا مثل `'important'::public.notification_severity`.
4. **تسرب أعلام الحماية:** عند استخدام `set_config('app.report_status_transition','on',true)` صفّر العلم الآخر `app.report_assignment` بـ `off`، والعكس — وإلا يتسرّب العلم بين العمليات داخل الجلسة ويُرفض تحديث لاحق.
5. **Edge Functions بمشاركة `_shared`:** لا يمكن نشرها من لوحة Supabase/محرر SQL بشكل موثوق؛ تتطلب نشرًا لمرة واحدة عبر Actions/CLI.
6. **GitHub Pages:** مجلد النشر يجب أن يكون `/docs` (وليس `/ (root)`) وإلا شاشة بيضاء؛ و`config.js` يُحمَّل قبل وحدة التطبيق، ويفضّل `VITE_BASE_PATH=/<repo>/` و`VITE_ROUTER_MODE=hash`.

---

## 7) معايير الجودة والاختبار (المستوى الاحترافي المطلوب)

- **Migrations مرقّمة** كمصدر حقيقة + سكربت يدمجها في ملف واحد لتنفيذ SQL Editor + فحص تزامن تلقائي.
- **اختبارات قاعدة البيانات** (pgTAP) تغطي: Luhn، آلة الحالات (مسموح/مرفوض)، RLS مفعّل على الجداول الحرجة، عدم إمكانية الحذف/التعديل المباشر، وسيناريو دورة حياة كاملة (محل→بيع→صيانة→فرمتة→بلاغ→إحالة→متابعة→استرداد→إغلاق→تدقيق).
- **تحقق من قاعدة بيانات حقيقية في CI**: إمّا `supabase test db`، وإمّا PostgreSQL مُضمَّن (مثل PGlite) مع بدائل (stubs) للمخططات `auth`/`storage`/الأدوار — بحيث يفشل البناء إن لم يعمل المخطط كاملًا.
- **فحص أسرار آلي** يرفض أي `service_role` JWT/تعيين في المستودع، مع السماح بمفتاح `anon` العام.
- **فحص توازن أقواس SQL** ثابت كخط دفاع إضافي.
- **واجهة:** `tsc --noEmit` + build + فحوصات PWA/manifest/service worker + 100% حالات خطأ/تحميل/فارغ.
- **أمر بوابة واحد** مثل `npm run verify` يشغّل كل ما سبق ويفشل عند أي خلل.
- **توثيق عربي** كامل: الإعداد من المتصفح فقط، النشر، تشغيل SQL، نشر الخلفية لمرة واحدة، أول مدير، واستكشاف الأعطال.

---

## 8) تعريف الجاهزية (Definition of Done)

- [ ] الموقع يفتح من `https://<owner>.github.io/<repo>/` دون شاشة بيضاء، ويعمل على الجوال والحاسوب.
- [ ] تسجيل دخول + MFA يعملان، والعمليات الحساسة تُرفض عند جلسة AAL1 وتنجح عند AAL2.
- [ ] إنشاء أول مدير عبر سكربت bootstrap (بلا UUID/بريد ثابت) ثم إسناد الأدوار يعمل.
- [ ] دورة الحياة الكاملة (تسجيل→بيع→صيانة→فرمتة→بلاغ→استرداد) تعمل وتُسجَّل في سجل التدقيق المتسلسل.
- [ ] أي IMEI بخانة تحقق خاطئة يُرفض خادميًا وفي الواجهة.
- [ ] لا تظهر أي بيانات شخصية حساسة كنص صريح في الجداول أو الواجهة لغير المخوّل.
- [ ] `npm run verify` (فحوصات + اختبارات + بناء + فحص أسرار + تحقق SQL) يمر بالكامل.
- [ ] مستندات التشغيل العربية كاملة ودقيقة.

---

## 9) خطوات التسليم المطلوبة من المساعد

1. أنشئ هيكل المشروع والواجهة والـ PWA بالكامل.
2. أنشئ migrations مرقّمة + ملف المخطط المدمج + سكربت أول مدير + **سكربت تصفير** `reset_all_objects.sql`.
3. أنشئ Edge Functions كاملة مع `_shared` و`deno.json`.
4. أنشئ فحوصات واختبارات الجودة في النقطة 7 واربطها بأمر `verify`.
5. جهّز توثيق `docs-source/` العربي + قالب عمل GitHub للنشر الخلفي لمرة واحدة.
6. ابنِ الموقع في `docs/` بالمسار الصحيح (`VITE_BASE_PATH` و`VITE_ROUTER_MODE=hash`) وضع `config.js` بالقيمتين العامتين أعلاه.
7. ادفع كل شيء لفرع العمل، وافتح PR نحو `main`، واترك للمستخدم خطوات: تفعيل Pages من `/docs`، تشغيل SQL، نشر الخلفية، إنشاء أول مدير.
