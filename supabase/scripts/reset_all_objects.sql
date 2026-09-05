-- ============================================================================
-- حماية | حذف جميع كائنات البناء السابق (جداول + سياسات + دوال + أنواع + مشغلات)
-- ============================================================================
-- الغرض: تصفير قاعدة بيانات Supabase من كل ما أنشأه البناء السابق، لتتمكن من
-- بناء التطبيق من الصفر (بمستودع جديد) على **نفس مشروع Supabase**.
--
-- آمن للتكرار (Idempotent): يمكن تشغيله أكثر من مرة دون أخطاء، ويترك مشروع
-- Supabase نظيفًا بمعنى "مشروع جديد بلا كائنات تطبيق".
--
-- ملاحظة عن التخزين: Supabase يمنع الحذف المباشر من جداول storage عبر ترجر
-- storage.protect_delete(). هذا السكربت يعطّل مؤقتًا كل المشغلات غير الداخلية
-- على storage.objects و storage.buckets، يحذف دلاء التطبيق فقط، ثم يعيد الحالة
-- الأصلية لكل مشغّل. لا يمس هذا السكربت دلاء أخرى أو كائناتها.
--
-- ما لا يلمسه هذا السكربت (مهم):
--   * مخططات Supabase المُدارة: auth, storage, extensions, realtime, graphql, vault
--   * مستخدمو المصادقة auth.users وأي بيانات Auth موجودة
--   * امتداد pgcrypto في extensions (قياسي وغير ضار)
--   * سجل الترحيلات: تنفيذ SQL Editor لا يسجل في supabase_migrations.schema_migrations
--
-- الاستخدام: افتح Supabase Dashboard → SQL Editor → الصق الكل ثم Run.
-- ============================================================================

begin;

-- 1) إزالة المشغّل الذي أُنشئ على جدول Supabase المُدار auth.users
drop trigger if exists on_auth_user_created on auth.users;

-- 2) إزالة سياسات التخزين المنكرة التي أُنشئت على storage.objects
drop policy if exists "deny browser access to evidence-private" on storage.objects;
drop policy if exists "deny browser access to device-media-private" on storage.objects;
drop policy if exists "deny browser access to identity-private" on storage.objects;

-- 3) حذف محتويات الدلاء الخاصة ثم الدلاء نفسها، مع تعطيل مشغّلات حماية
--    التخزين مؤقتًا ثم إعادة حالتها الأصلية كما كانت.
do $$
declare
  rels   regclass[] := '{}';
  names  text[]    := '{}';
  states text[]    := '{}';
  r record;
begin
  for r in
    select tgrelid::regclass as rel, tgname, tgenabled::text as state
    from pg_trigger
    where not tgisinternal
      and tgrelid in ('storage.objects'::regclass, 'storage.buckets'::regclass)
  loop
    rels  := rels  || r.rel;
    names := names || r.tgname;
    states := states || r.state;
    execute format('alter table %s disable trigger %I', r.rel, r.tgname);
  end loop;

  delete from storage.objects
   where bucket_id in ('evidence-private', 'device-media-private', 'identity-private');
  delete from storage.buckets
   where id in ('evidence-private', 'device-media-private', 'identity-private');

  for i in 1..coalesce(array_length(names, 1), 0) loop
    execute format('alter table %s %s trigger %I',
      rels[i],
      case when states[i] = 'D' then 'disable' else 'enable' end,
      names[i]);
  end loop;
end $$;

-- 4) إسقاط مخططي التطبيق كاملين: يكفي لإزالة كل الجداول والدوال والأنواع (enums)
--    والسياسات والمشغلات والتسلسلات التي بنيناها داخل public و private.
drop schema if exists private cascade;
drop schema if exists public cascade;

-- 5) إعادة إنشاء مخطط public وامتيازات Supabase الافتراضية
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
-- تحقق سريع (شغّله بعد التنفيذ): يجب أن تعود كل النتائج صفرًا/فارغة
--   select count(*) from pg_tables   where schemaname in ('public','private');
--   select count(*) from pg_policies where schemaname in ('public','storage');
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname in ('public','private');
--   select count(*) from storage.buckets where id like '%-private';
-- ============================================================================
