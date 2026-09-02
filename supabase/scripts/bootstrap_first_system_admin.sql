-- ============================================================================
-- حماية | إنشاء أول مدير نظام بأمان (Bootstrap) — لا يعمل داخل migrations
-- ============================================================================
-- هذا السكربت يُنفَّذ يدويًا مرة واحدة في Supabase SQL Editor بعد:
--   1) تطبيق جميع ملفات supabase/migrations بنجاح (supabase db push أو supabase migration list).
--   2) إنشاء حساب Auth وتسجيل الدخول/تأكيد البريد الإلكتروني.
--
-- السكربت آمن ومتوقف ذاتيًا عند أي نقص، ولا يحتوي على أي UUID أو بريد أو بيانات
-- شخصية ثابتة. استبدل القيمة الوحيدة أدناه بمعرّف حساب Auth المراد ترقيته:
--
--   v_target := 'REPLACE_WITH_AUTH_USER_UUID';
--
-- لا تُشغّل هذا السكربت في production عبر نسخ/لصق غير مدقق؛ استخدم جلسة إدارة
-- مقيدة، وتحقّق من الناتج، ثم فعّل TOTP (MFA) فورًا من «أمان الحساب».
-- ============================================================================

begin;

do $bootstrap$
declare
  v_target text := 'REPLACE_WITH_AUTH_USER_UUID';  -- <-- استبدل هذه القيمة فقط
  v_uuid uuid;
  v_display_name text;
begin
  -- (0) التأكد من استبدال المعرّف
  if v_target !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'Bootstrap: استبدل REPLACE_WITH_AUTH_USER_UUID بمعرّف حساب Auth قبل التنفيذ.'
      using errcode = '22023';
  end if;
  v_uuid := v_target::uuid;

  -- (1) التأكد من تطبيق migrations (الجداول والدوال الأساسية موجودة).
  if to_regclass('public.users') is null
     or to_regclass('public.roles') is null
     or to_regclass('public.user_roles') is null
     or to_regclass('auth.users') is null
     or to_regprocedure('private.append_audit(text,text,uuid,jsonb,jsonb,text,jsonb,inet,text,uuid)') is null then
    raise exception 'MIGRATIONS_NOT_APPLIED: لم يتم تطبيق migrations بالكامل. نفّذ supabase db push وتحقق من supabase migration list قبل تكرار هذه الخطوة.'
      using errcode = '42P01';
  end if;

  -- (2) التأكد من وجود حساب Auth لهذا المعرّف.
  if not exists (select 1 from auth.users where id = v_uuid) then
    raise exception 'لم يُعثر على حساب Auth لهذا UUID. تأكد أنك تستخدم مشروع Supabase الصحيح وأن الحساب أُنشئ عبر Auth.'
      using errcode = 'P0001';
  end if;

  -- (3) التأكد من تأكيد البريد الإلكتروني.
  if not exists (
    select 1 from auth.users
    where id = v_uuid
      and (confirmed_at is not null or email_confirmed_at is not null)
  ) then
    raise exception 'حساب Auth غير مؤكد البريد بعد. أكد البريد الإلكتروني (من Inbucket محليًا أو من رابط التأكيد) ثم أعد التنفيذ.'
      using errcode = 'P0001';
  end if;

  -- (4) ضمان وجود ملف المستخدم public.users (يُنشأ عادة عبر trigger؛ هذا ضمان إضافي
  --     للحالات التي أُنشئ فيها الحساب قبل تطبيق migrations).
  select coalesce(nullif(left(au.raw_user_meta_data ->> 'display_name', 160), ''), 'مستخدم')
    into v_display_name
  from auth.users au where au.id = v_uuid;

  insert into public.users (id, display_name, account_status)
  values (v_uuid, v_display_name, 'active')
  on conflict (id) do nothing;

  -- (5) تفعيل الحساب.
  update public.users
     set account_status = 'active',
         updated_at = clock_timestamp()
   where id = v_uuid
     and account_status <> 'active';

  -- (6) منح دور system_admin مرة واحدة فقط.
  insert into public.user_roles (user_id, role_id)
  select v_uuid, r.id from public.roles r where r.key = 'system_admin'
  on conflict (user_id, role_id) do nothing;

  -- (7) توثيق العملية في سجل التدقيق غير القابل للتعديل.
  perform private.append_audit(
    'bootstrap_system_admin', 'user', v_uuid,
    null,
    jsonb_build_object('role', 'system_admin', 'account_status', 'active'),
    'success',
    jsonb_build_object('bootstrap', true),
    null, null, v_uuid
  );

  -- يُستخدم في استعلام التحقق النهائي أدناه (قيمة جلسة، لا تُخزَّن).
  perform set_config('app.bootstrap_target', v_uuid::text, false);
end;
$bootstrap$;

commit;

-- ===== تحقق نهائي (يجب أن يعيد صفًا واحدًا يتضمن دور system_admin) =====
select u.id,
       u.display_name,
       u.account_status,
       u.mfa_required,
       coalesce(array_agg(r.key order by r.key), '{}'::text[]) as roles
from public.users u
left join public.user_roles ur on ur.user_id = u.id
left join public.roles r on r.id = ur.role_id
where u.id = current_setting('app.bootstrap_target', true)::uuid
group by u.id, u.display_name, u.account_status, u.mfa_required;
