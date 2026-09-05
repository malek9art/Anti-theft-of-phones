-- ============================================================================
-- حماية | حذف جميع كائنات البناء السابق (جداول + سياسات + دوال + أنواع + مشغلات)
-- ============================================================================
-- الغرض: تصفير قاعدة بيانات Supabase من كل ما أنشأه البناء السابق، لتتمكن من
-- بناء التطبيق من الصفر (بمستودع جديد) على **نفس مشروع Supabase**.
--
-- آمن للتكرار (Idempotent): يمكن تشغيله أكثر من مرة دون أخطاء، ويترك مشروع
-- Supabase نظيفًا بمعنى "مشروع جديد بلا كائنات تطبيق".
--
-- ⚠️ ملاحظة مهمة عن التخزين (storage):
--   لا يمكن حذف صفوف storage.objects أو storage.buckets من SQL Editor إطلاقًا،
--   لأن جداول التخزين مملوكة لدور supabase_storage_admin (وليس postgres) ومحمية
--   بترجر storage.protect_delete() الذي يمنع الحذف المباشر. أي محاولة لذلك تفشل
--   بالخطأ "must be owner of table" أو "Direct deletion from storage tables".
--   دلاء التطبيق الثلاثة (evidence-private, device-media-private, identity-private)
--   فارغة وغير مؤذية؛ البناء الجديد سيعيد استخدامها تلقائيًا (insert ... on conflict).
--   إن أردت حذفها نهائيًا: Supabase Dashboard → Storage → احذف كل دلو يدويًا.
--
-- ما لا يلمسه هذا السكربت (مهم):
--   * مخططات Supabase المُدارة: auth, storage, extensions, realtime, graphql, vault
--   * مستخدمو المصادقة auth.users وأي بيانات Auth موجودة
--   * دلاء التخزين ومحتوياتها (انظر الملاحظة أعلاه)
--   * سجل الترحيلات: تنفيذ SQL Editor لا يسجل في supabase_migrations.schema_migrations
--
-- الاستخدام: افتح Supabase Dashboard → SQL Editor → الصق الكل ثم Run.
-- ============================================================================

begin;

-- 1) إزالة المشغّل الذي أنشأه البناء السابق على جدول Supabase المُدار auth.users
drop trigger if exists on_auth_user_created on auth.users;

-- 2) إزالة سياسات التخزين المنكرة التي أنشأناها على storage.objects
--    (هذه السياسات مملوكة لدورنا لذا يُسمح بإسقاطها)
drop policy if exists "deny browser access to evidence-private" on storage.objects;
drop policy if exists "deny browser access to device-media-private" on storage.objects;
drop policy if exists "deny browser access to identity-private" on storage.objects;

-- 3) إسقاط مخططي التطبيق كاملين: يكفي لإزالة كل الجداول والدوال والأنواع (enums)
--    والسياسات والمشغلات والتسلسلات التي بنيناها داخل public و private.
drop schema if exists private cascade;
drop schema if exists public cascade;

-- 4) إعادة إنشاء مخطط public وامتيازات Supabase الافتراضية
create schema public;

grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on all tables    in schema public to postgres, anon, authenticated, service_role;
grant all on all sequences in schema public to postgres, anon, authenticated, service_role;
grant all on all functions in schema public to postgres, anon, authenticated, service_role;

alter default privileges in schema public grant all on tables    to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;

commit;

-- ============================================================================
-- تحقق سريع (شغّله بعد التنفيذ): يجب أن تعود نتائج الكائنات صفرًا
--   select count(*) as "جداول متبقية"  from pg_tables   where schemaname in ('public','private');
--   select count(*) as "سياسات متبقية" from pg_policies where schemaname = 'public';
--   select count(*) as "دوال متبقية" from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname in ('public','private');
--
-- التحقق من الدلاء (متوقع 3 — تُحذف يدويًا من لوحة Storage إن أردت):
--   select id, name from storage.buckets where id like '%-private';
-- ============================================================================
