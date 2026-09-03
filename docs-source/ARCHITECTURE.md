# حماية | المعمارية الأمنية

## قرار الواجهة

هذا المستودع بدأ بملف `README` فقط ولم يكن يحتوي على Flutter أو Dart أو FlutterFlow، كما أن بيئة التنفيذ لا تحتوي على Flutter SDK. لذلك نُفذت **واجهة ويب Responsive حقيقية بـ React + TypeScript** كبديل تقني قابل للاختبار والتشغيل في هذه البيئة، مع تصميم RTL وموبايل أولًا وواجهة PWA خفيفة. لا يوجد وضع عرض أو بيانات ثابتة في الإنتاج.

الحد الفاصل مع الخلفية هو Edge Functions/HTTP، وليس مكونات React؛ لذلك يمكن إضافة عميل Flutter للتطبيق الميداني لاحقًا دون تغيير قاعدة البيانات أو منطق الصلاحيات. كل دالة واجهة مطلوبة لها عقد خادمي واضح في `supabase/functions`.

## الطبقات

```text
متصفح المستخدم (واجهة RTL، لا مفاتيح سرية ولا تخزين بيانات عمل)
             │ JWT قصير العمر + HTTPS
             ▼
Supabase Edge Functions
  ├─ تحقق مدخلات، CORS بقائمة Origins، معدل طلبات ذري
  ├─ تفويض من JWT + RPC خاضع لـ RLS
  ├─ تشفير/فك تشفير PII في ذاكرة الوظيفة فقط
  └─ service_role داخل الوظيفة فقط عند إنشاء Signed URL أو Auth Admin
             ▼
PostgreSQL / Supabase Auth / Private Storage
  ├─ RBAC قابل للتوسعة + RLS
  ├─ API RPCs بــ SECURITY DEFINER ومسار بحث ثابت
  ├─ state machines + triggers لمنع التعديل والحذف
  ├─ audit hash chain و sensitive-access log
  └─ private buckets، بلا public URLs
```

## حدود الثقة

| المكوّن | ما يثق به | ما لا يثق به |
|---|---|---|
| الواجهة | نتيجة Edge Function الآمنة فقط | الدور المحفوظ محليًا، الحقول، IDs، الملف، حالة الزر |
| Edge Function | JWT تم التحقق منه ونتيجة RPC | أي Body أو اسم ملف أو IMEI وارد من العميل |
| PostgreSQL | `auth.uid()` من JWT وعمليات RPC المحددة | طلب PostgREST مباشر من المستخدم |
| التخزين | Signed upload/view قصير العمر صادر بعد تفويض | طلب تحميل أو قراءة مباشر من العميل |

## نموذج البيانات

- `devices` + `device_imeis`: هوية الجهاز المركزية، رقم IMEI فريد عالميًا، وIMEI 1/2 بــ Luhn constraint.
- `sales`, `sale_items`, `repair_records`, `format_records`: سجلات تشغيل append-only ذات أرقام مستندات فريدة.
- `stolen_reports`, `report_status_history`, `report_follow_ups`: دورة البلاغ والحالة والتعيين والمتابعة.
- `customers`: مرجع غير حساس فقط؛ `customer_sensitive_data` يحتوي AES-GCM ciphertext + HMAC blind indexes فقط.
- `evidence`, `device_media`: metadata فقط، بينما الملف في bucket خاص.
- `device_events`: خط زمن الجهاز قابل للترقيم pagination.
- `audit_logs`: hash chain متسلسل مع trigger يمنع UPDATE/DELETE.
- `sensitive_data_access_logs`, `evidence_access_logs`, `security_events`, `notifications`: مراقبة مستقلة للعمليات الحساسة والتنبيهات.

## تدفق العمليات الحرجة

### فحص IMEI

1. الواجهة تتحقق شكليًا من 15 رقمًا، ثم ترسل الرقم إلى `check-imei`.
2. الدالة تتحقق من JWT وCORS ومعدل الطلبات.
3. `api_check_imei` يعيد أقل قدر ممكن من البيانات ويكتب audit entry.
4. إن وجد بلاغ نشط، تعود رسالة أمنية عامة. رقم البلاغ والحالة والأولوية يظهران فقط عند `can_access_report`.
5. لا تصل هوية المبلّغ أو هاتفه أو الأدلة للمتصفح غير المخوّل أصلًا.

### بيع / بلاغ مع بيانات شخصية

1. النص الشخصي موجود في RAM للطلب فقط.
2. Edge Function تستخدم مفتاحي أسرار مختلفين: AES-256-GCM للتشفير وHMAC-SHA-256 للـ blind index.
3. wrapper RPC ينشئ العميل والسجل التشغيلي في transaction واحدة.
4. لا تحوي audit entries plaintext PII أو IMEI كامل (يستخدم آخر 4 أرقام عند الحاجة).

### رفع/عرض دليل

1. `create-evidence-upload` يسجل intent بعد تحقق صلاحية `upload_evidence`.
2. Edge Function، وليس المتصفح، ينشئ upload token قصيرًا لمسار محدد.
3. بعد التحميل تتحقق الوظيفة من الحجم والنوع وتحسب SHA-256 من الملف الخاص قبل اعتماده.
4. العرض يطلب سببًا، يكتب `evidence_access_logs`، ثم يصدر Signed URL أقصى مدته 300 ثانية (الإعداد الافتراضي 60).

## دورة الحالة

`device_status_transitions` و`report_status_transitions` هما المصدر المصرح به للانتقالات. الدالة `private.transition_device` تقفل الصف، تتحقق من الحافة، تحدّث الحالة من خلال guard، وتكتب حدث timeline. لا تستطيع الواجهة جعل جهاز مسروق `available` أو بيعه بتعديل طلب HTTP.

## الأداء وقابلية التوسع

- فهارس فريدة على IMEI/Serial/Report Number/Operation Number.
- فهارس مركبة للأجهزة والحالات والتواريخ والبلاغات والتسلسل الزمني.
- الحدود القصوى للصفحات 100 (أو 200 للتدقيق) وcursor زمني للـ timeline.
- لا يجلب dashboard أو البحث أي PII أو ملف binary.
- يمكن لاحقًا فصل واجهة المحل، تطبيق الفني، والبوابة الحكومية مع الاحتفاظ بعقود Edge Functions نفسها.

## خارج النطاق المتعمد

رقم IMEI لا يحدد موقع الجهاز الحالي. لا توجد أي وظيفة تدّعي تعقب جهاز أو استدعاء بيانات اتصالات. أي تكامل شركات اتصالات يحتاج عقدًا منفصلًا وصلاحية قانونية وواجهة تكامل معزولة.
