-- ============================================================================
-- حماية | المخطط الكامل (كل migrations مدموجة بالترتيب) — لطريقة المتصفح فقط
-- ============================================================================
-- هذا الملف مُولَّد تلقائيًا من supabase/migrations/*.sql بالترتيب. المصدر المرجعي
-- هو مجلد migrations؛ لا تعدّل هذا الملف يدويًا. لإعادة توليده:
--   node scripts/build-schema-combined.mjs
--
-- الاستخدام (من المتصفح فقط، بدون تيرمينال):
--   1) افتح Supabase Dashboard → مشروعك → SQL Editor.
--   2) الصق محتوى هذا الملف كاملًا ثم Run.
--   3) يُنفَّذ الكل داخل معاملة واحدة (إما نجح كل شيء أو لم يُطبَّق شيء).
--   4) ملاحظة: هذه الطريقة لا تسجّل الملفات في supabase_migrations.schema_migrations.
--      عند استخدام CLI لاحقًا راجع قسم migration repair في docs-source/RUNBOOK_AR.md.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 20260901000000_foundation.sql
-- ----------------------------------------------------------------------------
-- حماية | قاعدة بيانات منصة دورة حياة الأجهزة
-- هذا المخطط يفصل بيانات الهوية عن سجلات الأعمال، ويجعل السجلات الحرجة append-only.
-- جميع الكتابات الحساسة تتم فقط عبر دوال api_* ذات SECURITY DEFINER أو Edge Functions.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public;

-- ===== Enums =====
create type public.account_status as enum ('pending', 'active', 'suspended', 'inactive');
create type public.shop_status as enum ('pending', 'approved', 'suspended', 'rejected', 'inactive');
create type public.verification_status as enum ('pending', 'verified', 'rejected');
create type public.device_status as enum (
  'registered', 'available', 'sold', 'in_repair', 'formatted',
  'flagged', 'stolen', 'recovered', 'blocked', 'archived'
);
create type public.report_status as enum (
  'draft', 'submitted', 'under_review', 'verified', 'active',
  'assigned', 'recovered', 'closed', 'rejected', 'cancelled'
);
create type public.report_priority as enum ('low', 'normal', 'high', 'critical');
create type public.evidence_access_level as enum ('restricted', 'investigation', 'sealed');
create type public.evidence_status as enum ('pending_upload', 'uploaded', 'quarantined', 'removed');
create type public.notification_severity as enum ('info', 'warning', 'important', 'critical');
create type public.media_kind as enum ('device', 'before_repair', 'after_repair', 'sale', 'other');
create type public.media_status as enum ('pending_upload', 'uploaded', 'quarantined', 'removed');

-- ===== Utility validation =====
create or replace function public.is_valid_imei(p_imei text)
returns boolean
language plpgsql
immutable
strict
set search_path = pg_catalog
as $$
declare
  v_imei text := btrim(p_imei);
  v_sum integer := 0;
  v_digit integer;
  v_index integer;
  v_double boolean := false;
begin
  if v_imei !~ '^[0-9]{15}$' then
    return false;
  end if;

  -- Luhn: the right-most check digit is not doubled.
  for v_index in reverse 15..1 loop
    v_digit := substr(v_imei, v_index, 1)::integer;
    if v_double then
      v_digit := v_digit * 2;
      if v_digit > 9 then
        v_digit := v_digit - 9;
      end if;
    end if;
    v_sum := v_sum + v_digit;
    v_double := not v_double;
  end loop;

  return (v_sum % 10) = 0;
end;
$$;

create or replace function public.normalize_imei(p_imei text)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select btrim(p_imei)
$$;

-- ===== Identity, tenancy, and RBAC =====
create table public.agencies (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 180),
  code text not null unique check (code ~ '^[A-Z0-9_-]{2,40}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default extensions.gen_random_uuid(),
  key text not null unique check (key ~ '^[a-z][a-z0-9_]{1,62}$'),
  name_ar text not null,
  description_ar text,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z][a-z0-9_]{1,62}$'),
  name_ar text not null,
  description_ar text,
  is_sensitive boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.users (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null default 'مستخدم' check (char_length(display_name) between 1 and 160),
  account_status public.account_status not null default 'pending',
  mfa_required boolean not null default false,
  agency_id uuid references public.agencies(id) on delete restrict,
  last_seen_at timestamptz,
  suspended_at timestamptz,
  suspension_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((account_status <> 'suspended') or suspended_at is not null)
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete restrict,
  permission_id uuid not null references public.permissions(id) on delete restrict,
  granted_at timestamptz not null default now(),
  granted_by uuid references public.users(id) on delete restrict,
  primary key (role_id, permission_id)
);

create table public.user_roles (
  user_id uuid not null references public.users(id) on delete restrict,
  role_id uuid not null references public.roles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  assigned_by uuid references public.users(id) on delete restrict,
  primary key (user_id, role_id)
);

create table public.locations (
  id uuid primary key default extensions.gen_random_uuid(),
  label text,
  address_text text,
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  created_by uuid references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (
    (latitude is null and longitude is null)
    or (latitude between -90 and 90 and longitude between -180 and 180)
  )
);

create table public.shops (
  id uuid primary key default extensions.gen_random_uuid(),
  shop_name text not null check (char_length(shop_name) between 2 and 180),
  commercial_name text,
  owner_user_id uuid references public.users(id) on delete restrict,
  business_phone text,
  address_text text,
  location_id uuid references public.locations(id) on delete restrict,
  status public.shop_status not null default 'pending',
  verification_status public.verification_status not null default 'pending',
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references public.users(id) on delete restrict,
  suspended_at timestamptz,
  suspended_by uuid references public.users(id) on delete restrict,
  suspension_reason text,
  updated_at timestamptz not null default now(),
  check ((status <> 'approved') or (approved_at is not null and approved_by is not null)),
  check ((status <> 'suspended') or (suspended_at is not null and suspension_reason is not null))
);

create table public.shop_users (
  shop_id uuid not null references public.shops(id) on delete restrict,
  user_id uuid not null references public.users(id) on delete restrict,
  title text,
  is_active boolean not null default true,
  joined_at timestamptz not null default now(),
  removed_at timestamptz,
  added_by uuid references public.users(id) on delete restrict,
  primary key (shop_id, user_id),
  check ((is_active and removed_at is null) or (not is_active and removed_at is not null))
);

create table public.technicians (
  user_id uuid primary key references public.users(id) on delete restrict,
  professional_reference text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.delegates (
  user_id uuid primary key references public.users(id) on delete restrict,
  agency_id uuid references public.agencies(id) on delete restrict,
  professional_reference text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ===== Device identity and customer data =====
create table public.device_status_transitions (
  from_status public.device_status not null,
  to_status public.device_status not null,
  requires_permission text,
  primary key (from_status, to_status),
  check (from_status <> to_status)
);

create table public.devices (
  id uuid primary key default extensions.gen_random_uuid(),
  brand text not null check (char_length(brand) between 1 and 100),
  model text not null check (char_length(model) between 1 and 160),
  color text,
  serial_number text,
  status public.device_status not null default 'registered',
  registered_shop_id uuid references public.shops(id) on delete restrict,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  check ((status <> 'archived') or archived_at is not null)
);

create unique index devices_serial_number_unique
  on public.devices (lower(serial_number)) where serial_number is not null;
create index devices_status_idx on public.devices(status, created_at desc);
create index devices_registered_shop_idx on public.devices(registered_shop_id, created_at desc);

create table public.device_imeis (
  id uuid primary key default extensions.gen_random_uuid(),
  device_id uuid not null references public.devices(id) on delete restrict,
  slot smallint not null check (slot in (1, 2)),
  imei text not null check (public.is_valid_imei(imei)),
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (device_id, slot),
  unique (imei)
);
create index device_imeis_device_idx on public.device_imeis(device_id);

create table public.device_media (
  id uuid primary key default extensions.gen_random_uuid(),
  device_id uuid not null references public.devices(id) on delete restrict,
  repair_record_id uuid,
  kind public.media_kind not null,
  storage_path text not null unique check (storage_path !~ '^/' and storage_path !~ '\.\.'),
  original_name text not null check (char_length(original_name) between 1 and 255),
  content_type text not null check (content_type in ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes integer not null check (size_bytes > 0 and size_bytes <= 10485760),
  sha256 text,
  status public.media_status not null default 'pending_upload',
  uploaded_by uuid not null references public.users(id) on delete restrict,
  uploaded_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default extensions.gen_random_uuid(),
  reference_code text not null unique,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Ciphertexts are AES-GCM envelopes created only by trusted Edge Functions.
-- Blind indexes are keyed HMACs; plaintext name, phone, ID, and address are never stored here.
create table public.customer_sensitive_data (
  customer_id uuid primary key references public.customers(id) on delete restrict,
  full_name_ciphertext text,
  phone_ciphertext text,
  national_id_ciphertext text,
  address_ciphertext text,
  full_name_lookup_hash text,
  phone_lookup_hash text,
  national_id_lookup_hash text,
  encryption_version smallint not null default 1,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (full_name_ciphertext is not null or phone_ciphertext is not null or national_id_ciphertext is not null),
  -- Versioned AES-GCM envelope shape; the encryption key remains outside PostgreSQL.
  check (full_name_ciphertext is null or full_name_ciphertext ~ '^v1\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}$'),
  check (phone_ciphertext is null or phone_ciphertext ~ '^v1\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}$'),
  check (national_id_ciphertext is null or national_id_ciphertext ~ '^v1\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}$'),
  check (address_ciphertext is null or address_ciphertext ~ '^v1\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}$'),
  check (full_name_lookup_hash is null or full_name_lookup_hash ~ '^[a-f0-9]{64}$'),
  check (phone_lookup_hash is null or phone_lookup_hash ~ '^[a-f0-9]{64}$'),
  check (national_id_lookup_hash is null or national_id_lookup_hash ~ '^[a-f0-9]{64}$')
);
create index customer_sensitive_phone_lookup_idx on public.customer_sensitive_data(phone_lookup_hash) where phone_lookup_hash is not null;
create index customer_sensitive_name_lookup_idx on public.customer_sensitive_data(full_name_lookup_hash) where full_name_lookup_hash is not null;

create sequence public.document_number_seq as bigint;

-- ===== Operational records (append-only) =====
create table public.sales (
  id uuid primary key default extensions.gen_random_uuid(),
  sale_number text not null unique,
  shop_id uuid not null references public.shops(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  sale_date timestamptz not null default now(),
  notes text check (char_length(notes) <= 2000),
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index sales_shop_date_idx on public.sales(shop_id, sale_date desc);
create index sales_customer_idx on public.sales(customer_id, sale_date desc);

create table public.sale_items (
  id uuid primary key default extensions.gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete restrict,
  device_id uuid not null references public.devices(id) on delete restrict,
  imei_snapshot text not null check (public.is_valid_imei(imei_snapshot)),
  unit_price numeric(14, 2) check (unit_price is null or unit_price >= 0),
  created_at timestamptz not null default now(),
  unique (sale_id, device_id)
);
create index sale_items_device_idx on public.sale_items(device_id, created_at desc);

create table public.repair_records (
  id uuid primary key default extensions.gen_random_uuid(),
  operation_number text not null unique,
  shop_id uuid not null references public.shops(id) on delete restrict,
  technician_id uuid not null references public.users(id) on delete restrict,
  device_id uuid not null references public.devices(id) on delete restrict,
  imei_snapshot text not null check (public.is_valid_imei(imei_snapshot)),
  operation_type text not null check (char_length(operation_type) between 2 and 160),
  notes text check (char_length(notes) <= 3000),
  before_images jsonb not null default '[]'::jsonb,
  after_images jsonb not null default '[]'::jsonb,
  result text not null default 'received' check (char_length(result) between 2 and 500),
  operation_location_id uuid references public.locations(id) on delete restrict,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index repair_records_device_idx on public.repair_records(device_id, created_at desc);
create index repair_records_shop_idx on public.repair_records(shop_id, created_at desc);

alter table public.device_media
  add constraint device_media_repair_fk
  foreign key (repair_record_id) references public.repair_records(id) on delete restrict;
create index device_media_device_idx on public.device_media(device_id, created_at desc);
create index device_media_repair_idx on public.device_media(repair_record_id) where repair_record_id is not null;

create table public.format_records (
  id uuid primary key default extensions.gen_random_uuid(),
  operation_number text not null unique,
  repair_record_id uuid references public.repair_records(id) on delete restrict,
  shop_id uuid not null references public.shops(id) on delete restrict,
  technician_id uuid not null references public.users(id) on delete restrict,
  device_id uuid not null references public.devices(id) on delete restrict,
  imei_snapshot text not null check (public.is_valid_imei(imei_snapshot)),
  format_type text not null check (char_length(format_type) between 2 and 160),
  notes text check (char_length(notes) <= 3000),
  result text not null default 'completed' check (char_length(result) between 2 and 500),
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index format_records_device_idx on public.format_records(device_id, created_at desc);
create index format_records_shop_idx on public.format_records(shop_id, created_at desc);

-- ===== Stolen reports, evidence, and case workflow =====
create table public.stolen_reports (
  id uuid primary key default extensions.gen_random_uuid(),
  report_number text not null unique,
  device_id uuid not null references public.devices(id) on delete restrict,
  imei_snapshot text not null check (public.is_valid_imei(imei_snapshot)),
  imei2_snapshot text check (imei2_snapshot is null or public.is_valid_imei(imei2_snapshot)),
  reporter_customer_id uuid not null references public.customers(id) on delete restrict,
  report_type text not null check (char_length(report_type) between 2 and 100),
  incident_at timestamptz not null,
  incident_location_id uuid references public.locations(id) on delete restrict,
  description text not null check (char_length(description) between 5 and 6000),
  status public.report_status not null default 'draft',
  priority public.report_priority not null default 'normal',
  agency_id uuid references public.agencies(id) on delete restrict,
  assigned_officer_id uuid references public.users(id) on delete restrict,
  assigned_delegate_id uuid references public.users(id) on delete restrict,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);
create index stolen_reports_device_idx on public.stolen_reports(device_id, status, created_at desc);
create index stolen_reports_status_idx on public.stolen_reports(status, priority desc, created_at desc);
create index stolen_reports_number_idx on public.stolen_reports(report_number);
create index stolen_reports_assignee_idx on public.stolen_reports(assigned_officer_id, assigned_delegate_id) where status not in ('closed', 'rejected', 'cancelled');

create table public.report_status_history (
  id uuid primary key default extensions.gen_random_uuid(),
  report_id uuid not null references public.stolen_reports(id) on delete restrict,
  from_status public.report_status,
  to_status public.report_status not null,
  note text check (char_length(note) <= 3000),
  changed_by uuid not null references public.users(id) on delete restrict,
  changed_at timestamptz not null default now()
);
create index report_status_history_report_idx on public.report_status_history(report_id, changed_at desc);

create table public.report_follow_ups (
  id uuid primary key default extensions.gen_random_uuid(),
  report_id uuid not null references public.stolen_reports(id) on delete restrict,
  note text not null check (char_length(note) between 5 and 3000),
  location_id uuid references public.locations(id) on delete restrict,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index report_follow_ups_report_idx on public.report_follow_ups(report_id, created_at desc);

create table public.evidence (
  id uuid primary key default extensions.gen_random_uuid(),
  report_id uuid not null references public.stolen_reports(id) on delete restrict,
  evidence_type text not null check (char_length(evidence_type) between 2 and 100),
  storage_path text not null unique check (storage_path !~ '^/' and storage_path !~ '\.\.'),
  original_name text not null check (char_length(original_name) between 1 and 255),
  content_type text not null check (content_type in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  size_bytes integer not null check (size_bytes > 0 and size_bytes <= 15728640),
  sha256 text,
  description text check (char_length(description) <= 3000),
  access_level public.evidence_access_level not null default 'restricted',
  status public.evidence_status not null default 'pending_upload',
  uploaded_by uuid not null references public.users(id) on delete restrict,
  uploaded_at timestamptz,
  created_at timestamptz not null default now()
);
create index evidence_report_idx on public.evidence(report_id, created_at desc);

create table public.evidence_access_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  evidence_id uuid not null references public.evidence(id) on delete restrict,
  actor_id uuid not null references public.users(id) on delete restrict,
  purpose text not null check (char_length(purpose) between 5 and 500),
  permission_used text not null,
  accessed_at timestamptz not null default now()
);
create index evidence_access_logs_evidence_idx on public.evidence_access_logs(evidence_id, accessed_at desc);

-- ===== Tamper-evident audit and security telemetry =====
create table public.audit_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  sequence_number bigint generated always as identity unique,
  actor_id uuid references public.users(id) on delete restrict,
  actor_roles text[] not null default '{}',
  action text not null check (char_length(action) between 2 and 100),
  entity_type text not null check (char_length(entity_type) between 2 and 100),
  entity_id uuid,
  old_value jsonb,
  new_value jsonb,
  ip_address inet,
  device_information text,
  result text not null default 'success' check (result in ('success', 'failure', 'denied')),
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  previous_hash text,
  entry_hash text not null unique
);
create index audit_logs_actor_time_idx on public.audit_logs(actor_id, occurred_at desc);
create index audit_logs_entity_time_idx on public.audit_logs(entity_type, entity_id, occurred_at desc);
create index audit_logs_action_time_idx on public.audit_logs(action, occurred_at desc);

create table public.sensitive_data_access_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid not null references public.users(id) on delete restrict,
  data_type text not null,
  record_id uuid not null,
  purpose text not null check (char_length(purpose) between 5 and 500),
  permission_used text not null,
  accessed_at timestamptz not null default now()
);
create index sensitive_access_actor_time_idx on public.sensitive_data_access_logs(actor_id, accessed_at desc);

create table public.security_events (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid references public.users(id) on delete restrict,
  event_type text not null check (char_length(event_type) between 2 and 120),
  severity public.notification_severity not null,
  ip_address inet,
  device_information text,
  metadata jsonb not null default '{}'::jsonb,
  resolved_at timestamptz,
  resolved_by uuid references public.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index security_events_active_idx on public.security_events(severity, created_at desc) where resolved_at is null;

create table public.notifications (
  id uuid primary key default extensions.gen_random_uuid(),
  recipient_id uuid not null references public.users(id) on delete restrict,
  severity public.notification_severity not null default 'info',
  notification_type text not null check (char_length(notification_type) between 2 and 100),
  title text not null check (char_length(title) between 2 and 200),
  body text not null check (char_length(body) between 2 and 1000),
  entity_type text,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz
);
create index notifications_recipient_idx on public.notifications(recipient_id, read_at, created_at desc);

create table public.device_events (
  id uuid primary key default extensions.gen_random_uuid(),
  device_id uuid not null references public.devices(id) on delete restrict,
  event_type text not null check (char_length(event_type) between 2 and 100),
  entity_type text not null check (char_length(entity_type) between 2 and 100),
  entity_id uuid,
  operation_number text,
  actor_id uuid references public.users(id) on delete restrict,
  shop_id uuid references public.shops(id) on delete restrict,
  agency_id uuid references public.agencies(id) on delete restrict,
  notes text check (char_length(notes) <= 3000),
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index device_events_timeline_idx on public.device_events(device_id, occurred_at desc, id desc);

create table public.record_corrections (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  old_value jsonb not null,
  new_value jsonb not null,
  reason text not null check (char_length(reason) between 5 and 1000),
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index record_corrections_entity_idx on public.record_corrections(entity_type, entity_id, created_at desc);

create table public.system_settings (
  key text primary key check (key ~ '^[a-z][a-z0-9_.]{1,100}$'),
  value jsonb not null,
  is_sensitive boolean not null default false,
  updated_by uuid references public.users(id) on delete restrict,
  updated_at timestamptz not null default now()
);

-- ===== Seeded policy data (no application user is made an administrator here) =====
insert into public.roles (key, name_ar, description_ar, is_system) values
  ('system_admin', 'مدير النظام', 'إدارة النظام والسياسات', true),
  ('authorized_officer', 'موظف جهة مختصة', 'موظف معتمد للبلاغات والحالات', true),
  ('investigation_officer', 'ضابط بحث جنائي', 'إدارة التحقيقات والأدلة', true),
  ('delegate', 'مندوب', 'متابعة الحالات المحولة إليه', true),
  ('shop_manager', 'مالك أو مدير محل', 'إدارة محل معتمد وموظفيه', true),
  ('technician', 'فني', 'استلام وصيانة الأجهزة ضمن محل معتمد', true),
  ('auditor', 'مدقق أو مراجع', 'الوصول المقيد للتدقيق والتقارير', true);

insert into public.permissions (code, name_ar, description_ar, is_sensitive) values
  ('view_device', 'عرض الجهاز', 'عرض سجل جهاز ضمن نطاق العمل', false),
  ('view_all_devices', 'عرض جميع الأجهزة', 'تجاوز نطاق المحل للأجهزة المصرح بها', true),
  ('search_imei', 'فحص IMEI', 'فحص رقم IMEI عبر الخادم', false),
  ('create_device', 'تسجيل جهاز', 'إضافة جهاز جديد لمحل معتمد', false),
  ('create_sale', 'تسجيل بيع', 'تسجيل عملية بيع', false),
  ('view_sales', 'عرض المبيعات', 'عرض مبيعات ضمن النطاق', false),
  ('create_repair', 'تسجيل صيانة', 'تسجيل عملية صيانة', false),
  ('create_format_record', 'تسجيل فرمتة', 'تسجيل عملية فرمتة', false),
  ('view_customer', 'عرض مرجع العميل', 'عرض مراجع العملاء غير الحساسة', false),
  ('view_identity', 'عرض الهوية', 'عرض بيانات الهوية شديدة الحساسية', true),
  ('view_sensitive_data', 'عرض بيانات حساسة', 'فك تشفير بيانات شخصية وفق الحاجة', true),
  ('create_stolen_report', 'إنشاء بلاغ', 'إنشاء بلاغ سرقة رسمي', true),
  ('review_report', 'مراجعة بلاغ', 'مراجعة البلاغات وتدقيقها', true),
  ('view_all_reports', 'عرض جميع البلاغات', 'عرض البلاغات ضمن الجهة المختصة', true),
  ('assign_case', 'تعيين قضية', 'تعيين موظف أو مندوب لقضية', true),
  ('change_report_status', 'تغيير حالة بلاغ', 'تغيير حالة البلاغ ضمن دورة الحالة', true),
  ('update_follow_up', 'تحديث متابعة', 'إضافة متابعة للقضية المعينة', true),
  ('upload_evidence', 'رفع دليل', 'رفع دليل إلى تخزين خاص', true),
  ('view_evidence', 'عرض دليل', 'إصدار رابط مؤقت لدليل مصرح', true),
  ('view_audit_logs', 'عرض سجل التدقيق', 'عرض سجل تدقيق غير قابل للتعديل', true),
  ('manage_shops', 'إدارة المحلات', 'اعتماد وإدارة المحلات', true),
  ('manage_shop_staff', 'إدارة موظفي المحل', 'إضافة وتعطيل موظفي وفنيي المحل ضمن النطاق', true),
  ('approve_shop', 'اعتماد محل', 'اعتماد محل جديد', true),
  ('suspend_shop', 'إيقاف محل', 'إيقاف محل مع سجل سبب', true),
  ('manage_users', 'إدارة المستخدمين', 'إدارة حالات المستخدمين', true),
  ('manage_permissions', 'إدارة الصلاحيات', 'إدارة الأدوار والصلاحيات', true),
  ('view_dashboard', 'عرض لوحة التحكم', 'عرض الإحصاءات ضمن النطاق', false),
  ('generate_reports', 'توليد تقارير', 'تصدير تقارير مصرح بها', true),
  ('view_security_events', 'عرض الأحداث الأمنية', 'عرض التنبيهات الأمنية', true),
  ('manage_system_settings', 'إدارة الإعدادات', 'إدارة إعدادات النظام', true),
  ('correct_record', 'تصحيح سجل', 'إضافة حدث تصحيح موثق', true)
on conflict (code) do nothing;

-- Expandable role-permission mapping. New roles can be inserted without schema changes.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = any (
  case r.key
    when 'system_admin' then array[
      'view_device','view_all_devices','search_imei','create_device','create_sale','view_sales','create_repair','create_format_record',
      'view_customer','view_identity','view_sensitive_data','create_stolen_report','review_report','view_all_reports','assign_case',
      'change_report_status','update_follow_up','upload_evidence','view_evidence','view_audit_logs','manage_shops','manage_shop_staff','approve_shop',
      'suspend_shop','manage_users','manage_permissions','view_dashboard','generate_reports','view_security_events','manage_system_settings','correct_record'
    ]
    when 'authorized_officer' then array[
      'view_device','view_all_devices','search_imei','view_customer','view_sensitive_data','create_stolen_report','review_report',
      'view_all_reports','assign_case','change_report_status','upload_evidence','view_evidence','view_dashboard','generate_reports'
    ]
    when 'investigation_officer' then array[
      'view_device','view_all_devices','search_imei','view_customer','view_identity','view_sensitive_data','create_stolen_report',
      'review_report','view_all_reports','assign_case','change_report_status','update_follow_up','upload_evidence','view_evidence',
      'view_dashboard','generate_reports','view_audit_logs','view_security_events'
    ]
    when 'delegate' then array[
      'view_device','search_imei','view_customer','update_follow_up','upload_evidence','view_evidence','view_dashboard'
    ]
    when 'shop_manager' then array[
      'view_device','search_imei','create_device','create_sale','view_sales','create_repair','create_format_record','view_customer','manage_shop_staff','view_dashboard'
    ]
    when 'technician' then array[
      'view_device','search_imei','create_repair','create_format_record','view_dashboard'
    ]
    when 'auditor' then array[
      'view_device','view_all_devices','search_imei','view_all_reports','view_evidence','view_audit_logs','view_dashboard','generate_reports','view_security_events'
    ]
  end
)
on conflict do nothing;

insert into public.device_status_transitions (from_status, to_status, requires_permission) values
  ('registered', 'available', 'create_device'),
  ('registered', 'sold', 'create_sale'),
  ('registered', 'in_repair', 'create_repair'),
  ('registered', 'flagged', 'create_stolen_report'),
  ('registered', 'archived', 'correct_record'),
  ('available', 'sold', 'create_sale'),
  ('available', 'in_repair', 'create_repair'),
  ('available', 'flagged', 'create_stolen_report'),
  ('available', 'blocked', 'change_report_status'),
  ('available', 'archived', 'correct_record'),
  ('sold', 'in_repair', 'create_repair'),
  ('sold', 'formatted', 'create_format_record'),
  ('sold', 'flagged', 'create_stolen_report'),
  ('sold', 'blocked', 'change_report_status'),
  ('in_repair', 'formatted', 'create_format_record'),
  ('in_repair', 'sold', 'correct_record'),
  ('in_repair', 'flagged', 'create_stolen_report'),
  ('in_repair', 'blocked', 'change_report_status'),
  ('formatted', 'sold', 'correct_record'),
  ('formatted', 'in_repair', 'create_repair'),
  ('formatted', 'flagged', 'create_stolen_report'),
  ('formatted', 'blocked', 'change_report_status'),
  ('flagged', 'stolen', 'change_report_status'),
  ('flagged', 'recovered', 'change_report_status'),
  ('flagged', 'available', 'change_report_status'),
  ('flagged', 'blocked', 'change_report_status'),
  ('stolen', 'recovered', 'change_report_status'),
  ('stolen', 'blocked', 'change_report_status'),
  ('recovered', 'available', 'change_report_status'),
  ('recovered', 'in_repair', 'create_repair'),
  ('recovered', 'archived', 'correct_record'),
  ('blocked', 'recovered', 'change_report_status'),
  ('blocked', 'archived', 'correct_record')
on conflict do nothing;

insert into public.system_settings (key, value, is_sensitive) values
  ('security.imei_checks_per_10m', '30'::jsonb, false),
  ('security.signed_url_ttl_seconds', '60'::jsonb, false),
  ('retention.audit_log_years', '10'::jsonb, false)
on conflict (key) do nothing;

-- Create a minimal profile whenever Supabase Auth creates an account. It has no role and is pending.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.users (id, display_name, account_status)
  values (
    new.id,
    coalesce(nullif(left(new.raw_user_meta_data ->> 'display_name', 160), ''), 'مستخدم'),
    'pending'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_auth_user();

-- ----------------------------------------------------------------------------
-- 20260901000100_security_helpers.sql
-- ----------------------------------------------------------------------------
-- Authorization helpers, audit hash chain, immutable-record guards, and state helpers.

create or replace function public.has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = auth.uid()
      and p.code = p_permission
  )
$$;

create or replace function public.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid() and r.key = 'system_admin'
  )
$$;

create or replace function public.is_active_account()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.account_status = 'active'
  )
$$;

create or replace function public.has_mfa_assurance()
returns boolean
language sql
stable
set search_path = pg_catalog, public
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;

create or replace function public.can_access_shop(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null and (
    public.has_permission('manage_shops')
    or exists (
      select 1 from public.shop_users su
      where su.shop_id = p_shop_id
        and su.user_id = auth.uid()
        and su.is_active
    )
  )
$$;

create or replace function public.can_operate_for_shop(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_active_account()
    and exists (
      select 1
      from public.shops s
      join public.shop_users su on su.shop_id = s.id
      where s.id = p_shop_id
        and su.user_id = auth.uid()
        and su.is_active
        and s.status = 'approved'
        and s.verification_status = 'verified'
    )
$$;

create or replace function public.can_access_device(p_device_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null and (
    public.has_permission('view_all_devices')
    or exists (
      select 1
      from public.devices d
      join public.shop_users su on su.shop_id = d.registered_shop_id
      where d.id = p_device_id and su.user_id = auth.uid() and su.is_active
    )
    or exists (
      select 1
      from public.repair_records rr
      join public.shop_users su on su.shop_id = rr.shop_id
      where rr.device_id = p_device_id and su.user_id = auth.uid() and su.is_active
    )
    or exists (
      select 1
      from public.sales s
      join public.sale_items si on si.sale_id = s.id
      join public.shop_users su on su.shop_id = s.shop_id
      where si.device_id = p_device_id and su.user_id = auth.uid() and su.is_active
    )
  )
$$;

create or replace function public.can_access_report(p_report_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null and (
    public.is_system_admin()
    or exists (
      select 1
      from public.stolen_reports sr
      join public.users u on u.id = auth.uid()
      where sr.id = p_report_id
        and public.has_permission('view_all_reports')
        and sr.agency_id = u.agency_id
    )
    or exists (
      select 1 from public.stolen_reports sr
      where sr.id = p_report_id
        and (sr.assigned_delegate_id = auth.uid() or sr.assigned_officer_id = auth.uid())
    )
  )
$$;

create or replace function public.can_access_customer(p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null and (
    public.has_permission('manage_users')
    or exists (
      select 1
      from public.sales s
      join public.shop_users su on su.shop_id = s.shop_id
      where s.customer_id = p_customer_id and su.user_id = auth.uid() and su.is_active
    )
    or exists (
      select 1 from public.stolen_reports sr
      where sr.reporter_customer_id = p_customer_id and public.can_access_report(sr.id)
    )
  )
$$;

create or replace function private.require_active_account()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.is_active_account() then
    raise exception 'ACCOUNT_NOT_ACTIVE' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.require_permission(p_permission text, p_mfa_for_sensitive boolean default false)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_active_account();

  if not public.has_permission(p_permission) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- Sensitive functions always require an AAL2 session. This is intentionally server-enforced;
  -- UI state and the optional user preference must never weaken the assurance requirement.
  if p_mfa_for_sensitive and not public.has_mfa_assurance() then
    raise exception 'MFA_REQUIRED' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.require_operational_shop(p_shop_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.can_operate_for_shop(p_shop_id) then
    raise exception 'SHOP_NOT_OPERATIONAL_OR_OUT_OF_SCOPE' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.document_number(p_prefix text)
returns text
language sql
volatile
security definer
set search_path = public, pg_temp
as $$
  select upper(p_prefix) || '-' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' || lpad(nextval('public.document_number_seq')::text, 8, '0')
$$;

create or replace function private.safe_imei_last4(p_imei text)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select right(p_imei, 4)
$$;

create or replace function private.setting_integer(p_key text, p_default integer)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_value integer;
begin
  select (value #>> '{}')::integer into v_value
  from public.system_settings
  where key = p_key and not is_sensitive;
  return coalesce(v_value, p_default);
exception when others then
  return p_default;
end;
$$;

-- Serializes writes with a transaction advisory lock and chains SHA-256 hashes.
-- Database owners still require operational controls; normal application roles cannot mutate this chain.
create or replace function private.append_audit(
  p_action text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_old_value jsonb default null,
  p_new_value jsonb default null,
  p_result text default 'success',
  p_metadata jsonb default '{}'::jsonb,
  p_ip_address inet default null,
  p_device_information text default null,
  p_actor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid := extensions.gen_random_uuid();
  v_actor uuid := coalesce(p_actor_id, auth.uid());
  v_roles text[] := '{}'::text[];
  v_previous_hash text;
  v_timestamp timestamptz := clock_timestamp();
  v_payload text;
  v_entry_hash text;
begin
  if p_result not in ('success', 'failure', 'denied') then
    raise exception 'INVALID_AUDIT_RESULT';
  end if;

  perform pg_advisory_xact_lock(hashtext('himaya_audit_chain_v1'));

  select coalesce(array_agg(r.key order by r.key), '{}'::text[])
    into v_roles
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_actor;

  select al.entry_hash into v_previous_hash
  from public.audit_logs al
  order by al.sequence_number desc
  limit 1;

  v_payload := concat_ws('|',
    coalesce(v_previous_hash, 'GENESIS'),
    coalesce(v_actor::text, ''),
    array_to_string(v_roles, ','),
    p_action,
    p_entity_type,
    coalesce(p_entity_id::text, ''),
    coalesce(p_old_value::text, ''),
    coalesce(p_new_value::text, ''),
    p_result,
    coalesce(p_metadata::text, ''),
    v_timestamp::text
  );
  v_entry_hash := encode(extensions.digest(convert_to(v_payload, 'UTF8'), 'sha256'), 'hex');

  insert into public.audit_logs (
    id, actor_id, actor_roles, action, entity_type, entity_id,
    old_value, new_value, ip_address, device_information, result,
    metadata, occurred_at, previous_hash, entry_hash
  ) values (
    v_id, v_actor, v_roles, p_action, p_entity_type, p_entity_id,
    p_old_value, p_new_value, p_ip_address, left(p_device_information, 500), p_result,
    coalesce(p_metadata, '{}'::jsonb), v_timestamp, v_previous_hash, v_entry_hash
  );

  return v_id;
end;
$$;

create or replace function private.append_device_event(
  p_device_id uuid,
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_operation_number text default null,
  p_shop_id uuid default null,
  p_agency_id uuid default null,
  p_notes text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_actor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid := extensions.gen_random_uuid();
begin
  insert into public.device_events (
    id, device_id, event_type, entity_type, entity_id, operation_number,
    actor_id, shop_id, agency_id, notes, metadata
  ) values (
    v_id, p_device_id, p_event_type, p_entity_type, p_entity_id, p_operation_number,
    coalesce(p_actor_id, auth.uid()), p_shop_id, p_agency_id, left(p_notes, 3000), coalesce(p_metadata, '{}'::jsonb)
  );
  return v_id;
end;
$$;

create or replace function private.raise_security_event(
  p_event_type text,
  p_severity public.notification_severity,
  p_metadata jsonb default '{}'::jsonb,
  p_actor_id uuid default null,
  p_ip_address inet default null,
  p_device_information text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid := extensions.gen_random_uuid();
begin
  insert into public.security_events (
    id, actor_id, event_type, severity, ip_address, device_information, metadata
  ) values (
    v_id, coalesce(p_actor_id, auth.uid()), p_event_type, p_severity,
    p_ip_address, left(p_device_information, 500), coalesce(p_metadata, '{}'::jsonb)
  );

  insert into public.notifications (recipient_id, severity, notification_type, title, body, entity_type, entity_id)
  select distinct ur.user_id, p_severity, 'security_event', 'تنبيه أمني',
         'تم تسجيل حدث أمني يحتاج إلى مراجعة.', 'security_event', v_id
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where r.key in ('system_admin', 'investigation_officer');

  return v_id;
end;
$$;

create or replace function private.log_sensitive_access(
  p_data_type text,
  p_record_id uuid,
  p_purpose text,
  p_permission text,
  p_actor_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := coalesce(p_actor_id, auth.uid());
begin
  insert into public.sensitive_data_access_logs (actor_id, data_type, record_id, purpose, permission_used)
  values (v_actor, p_data_type, p_record_id, p_purpose, p_permission);

  perform private.append_audit(
    'view_sensitive_data', p_data_type, p_record_id, null, null, 'success',
    jsonb_build_object('purpose', p_purpose, 'permission_used', p_permission), null, null, v_actor
  );
end;
$$;

-- Generic guard for append-only tables.
create or replace function private.reject_mutation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'IMMUTABLE_RECORD' using errcode = '42501';
end;
$$;

create or replace function private.guard_device_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'IMMUTABLE_DEVICE_IDENTITY' using errcode = '42501';
  end if;

  if current_setting('app.device_transition', true) <> 'on' then
    raise exception 'DIRECT_DEVICE_UPDATE_FORBIDDEN' using errcode = '42501';
  end if;

  if new.id is distinct from old.id
    or new.brand is distinct from old.brand
    or new.model is distinct from old.model
    or new.color is distinct from old.color
    or new.serial_number is distinct from old.serial_number
    or new.registered_shop_id is distinct from old.registered_shop_id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'DEVICE_IDENTITY_IMMUTABLE' using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function private.guard_report_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'IMMUTABLE_REPORT' using errcode = '42501';
  end if;

  -- Assignment is checked first because api_assign_report may first perform an allowed
  -- status transition inside the same transaction, leaving that transaction-local flag set.
  if current_setting('app.report_assignment', true) = 'on' then
    if new.id is distinct from old.id
      or new.report_number is distinct from old.report_number
      or new.device_id is distinct from old.device_id
      or new.imei_snapshot is distinct from old.imei_snapshot
      or new.imei2_snapshot is distinct from old.imei2_snapshot
      or new.reporter_customer_id is distinct from old.reporter_customer_id
      or new.report_type is distinct from old.report_type
      or new.incident_at is distinct from old.incident_at
      or new.incident_location_id is distinct from old.incident_location_id
      or new.description is distinct from old.description
      or new.status is distinct from old.status
      or new.priority is distinct from old.priority
      or new.agency_id is distinct from old.agency_id
      or new.closed_at is distinct from old.closed_at
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at then
      raise exception 'REPORT_CORE_FIELDS_IMMUTABLE' using errcode = '42501';
    end if;
    return new;
  end if;

  if current_setting('app.report_status_transition', true) = 'on' then
    if new.id is distinct from old.id
      or new.report_number is distinct from old.report_number
      or new.device_id is distinct from old.device_id
      or new.imei_snapshot is distinct from old.imei_snapshot
      or new.imei2_snapshot is distinct from old.imei2_snapshot
      or new.reporter_customer_id is distinct from old.reporter_customer_id
      or new.report_type is distinct from old.report_type
      or new.incident_at is distinct from old.incident_at
      or new.incident_location_id is distinct from old.incident_location_id
      or new.description is distinct from old.description
      or new.priority is distinct from old.priority
      or new.agency_id is distinct from old.agency_id
      or new.assigned_officer_id is distinct from old.assigned_officer_id
      or new.assigned_delegate_id is distinct from old.assigned_delegate_id
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at then
      raise exception 'REPORT_CORE_FIELDS_IMMUTABLE' using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'DIRECT_REPORT_UPDATE_FORBIDDEN' using errcode = '42501';
end;
$$;

create or replace function private.guard_evidence_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'IMMUTABLE_EVIDENCE' using errcode = '42501';
  end if;
  if current_setting('app.evidence_upload_completion', true) <> 'on' then
    raise exception 'DIRECT_EVIDENCE_UPDATE_FORBIDDEN' using errcode = '42501';
  end if;
  if new.id is distinct from old.id
    or new.report_id is distinct from old.report_id
    or new.evidence_type is distinct from old.evidence_type
    or new.storage_path is distinct from old.storage_path
    or new.original_name is distinct from old.original_name
    or new.content_type is distinct from old.content_type
    or new.size_bytes is distinct from old.size_bytes
    or new.description is distinct from old.description
    or new.access_level is distinct from old.access_level
    or new.uploaded_by is distinct from old.uploaded_by
    or new.created_at is distinct from old.created_at then
    raise exception 'EVIDENCE_CORE_FIELDS_IMMUTABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function private.guard_media_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'IMMUTABLE_MEDIA' using errcode = '42501';
  end if;
  if current_setting('app.media_upload_completion', true) <> 'on' then
    raise exception 'DIRECT_MEDIA_UPDATE_FORBIDDEN' using errcode = '42501';
  end if;
  if new.id is distinct from old.id
    or new.device_id is distinct from old.device_id
    or new.repair_record_id is distinct from old.repair_record_id
    or new.kind is distinct from old.kind
    or new.storage_path is distinct from old.storage_path
    or new.original_name is distinct from old.original_name
    or new.content_type is distinct from old.content_type
    or new.size_bytes is distinct from old.size_bytes
    or new.uploaded_by is distinct from old.uploaded_by
    or new.created_at is distinct from old.created_at then
    raise exception 'MEDIA_CORE_FIELDS_IMMUTABLE' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function private.guard_security_event_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'IMMUTABLE_SECURITY_EVENT' using errcode = '42501';
  end if;
  if current_setting('app.security_event_resolution', true) <> 'on'
    or new.id is distinct from old.id
    or new.actor_id is distinct from old.actor_id
    or new.event_type is distinct from old.event_type
    or new.severity is distinct from old.severity
    or new.ip_address is distinct from old.ip_address
    or new.device_information is distinct from old.device_information
    or new.metadata is distinct from old.metadata
    or old.resolved_at is not null
    or new.resolved_at is null
    or new.resolved_by is null then
    raise exception 'DIRECT_SECURITY_EVENT_UPDATE_FORBIDDEN' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function private.guard_notification_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'NOTIFICATION_DELETE_FORBIDDEN' using errcode = '42501';
  end if;
  if current_setting('app.notification_read', true) <> 'on'
    or new.id is distinct from old.id
    or new.recipient_id is distinct from old.recipient_id
    or new.severity is distinct from old.severity
    or new.notification_type is distinct from old.notification_type
    or new.title is distinct from old.title
    or new.body is distinct from old.body
    or new.entity_type is distinct from old.entity_type
    or new.entity_id is distinct from old.entity_id
    or new.created_at is distinct from old.created_at
    or new.expires_at is distinct from old.expires_at then
    raise exception 'DIRECT_NOTIFICATION_UPDATE_FORBIDDEN' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger devices_guard_update
before update or delete on public.devices
for each row execute procedure private.guard_device_update();

create trigger reports_guard_update
before update or delete on public.stolen_reports
for each row execute procedure private.guard_report_update();

create trigger evidence_guard_update
before update or delete on public.evidence
for each row execute procedure private.guard_evidence_update();

create trigger device_media_guard_update
before update or delete on public.device_media
for each row execute procedure private.guard_media_update();

create trigger notifications_guard_update
before update or delete on public.notifications
for each row execute procedure private.guard_notification_update();

create trigger immutable_device_imeis
before update or delete on public.device_imeis
for each row execute procedure private.reject_mutation();
create trigger immutable_sales
before update or delete on public.sales
for each row execute procedure private.reject_mutation();
create trigger immutable_sale_items
before update or delete on public.sale_items
for each row execute procedure private.reject_mutation();
create trigger immutable_repairs
before update or delete on public.repair_records
for each row execute procedure private.reject_mutation();
create trigger immutable_formats
before update or delete on public.format_records
for each row execute procedure private.reject_mutation();
create trigger immutable_report_history
before update or delete on public.report_status_history
for each row execute procedure private.reject_mutation();
create trigger immutable_evidence_access
before update or delete on public.evidence_access_logs
for each row execute procedure private.reject_mutation();
create trigger immutable_report_follow_ups
before update or delete on public.report_follow_ups
for each row execute procedure private.reject_mutation();
create trigger immutable_audit_logs
before update or delete on public.audit_logs
for each row execute procedure private.reject_mutation();
create trigger immutable_sensitive_access
before update or delete on public.sensitive_data_access_logs
for each row execute procedure private.reject_mutation();
create trigger security_events_guard_update
before update or delete on public.security_events
for each row execute procedure private.guard_security_event_update();
create trigger immutable_device_events
before update or delete on public.device_events
for each row execute procedure private.reject_mutation();
create trigger immutable_corrections
before update or delete on public.record_corrections
for each row execute procedure private.reject_mutation();

create or replace function private.transition_device(
  p_device_id uuid,
  p_to_status public.device_status,
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_operation_number text default null,
  p_notes text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_from_status public.device_status;
  v_shop_id uuid;
  v_agency_id uuid;
begin
  select d.status, d.registered_shop_id into v_from_status, v_shop_id
  from public.devices d
  where d.id = p_device_id
  for update;

  if not found then
    raise exception 'DEVICE_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_from_status = p_to_status then
    return;
  end if;

  if not exists (
    select 1 from public.device_status_transitions st
    where st.from_status = v_from_status and st.to_status = p_to_status
  ) then
    raise exception 'INVALID_DEVICE_STATE_TRANSITION' using errcode = '22023';
  end if;

  perform set_config('app.device_transition', 'on', true);
  update public.devices
     set status = p_to_status,
         updated_at = clock_timestamp(),
         archived_at = case when p_to_status = 'archived' then clock_timestamp() else archived_at end
   where id = p_device_id;

  perform private.append_device_event(
    p_device_id,
    p_event_type,
    p_entity_type,
    p_entity_id,
    p_operation_number,
    v_shop_id,
    v_agency_id,
    p_notes,
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('from_status', v_from_status, 'to_status', p_to_status)
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 20260901000200_business_api.sql
-- ----------------------------------------------------------------------------
-- Trusted API surface. All functions below enforce authorization on the server/database,
-- validate input, write an immutable audit entry, and never return personal identity data by default.

create table public.report_status_transitions (
  from_status public.report_status not null,
  to_status public.report_status not null,
  primary key (from_status, to_status),
  check (from_status <> to_status)
);

insert into public.report_status_transitions (from_status, to_status) values
  ('draft', 'submitted'), ('draft', 'cancelled'),
  ('submitted', 'under_review'), ('submitted', 'rejected'), ('submitted', 'cancelled'),
  ('under_review', 'verified'), ('under_review', 'rejected'), ('under_review', 'cancelled'),
  ('verified', 'active'), ('verified', 'assigned'), ('verified', 'rejected'),
  ('active', 'assigned'), ('active', 'recovered'), ('active', 'closed'),
  ('assigned', 'active'), ('assigned', 'recovered'), ('assigned', 'closed'),
  ('recovered', 'closed')
on conflict do nothing;

-- Covers re-reporting a recovered device as well as a device blocked by an earlier case.
insert into public.device_status_transitions (from_status, to_status, requires_permission) values
  ('recovered', 'flagged', 'create_stolen_report'),
  ('blocked', 'flagged', 'create_stolen_report')
on conflict do nothing;

create or replace function public.api_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user public.users%rowtype;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select * into v_user from public.users where id = auth.uid();
  if not found then
    raise exception 'PROFILE_NOT_FOUND' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'user', jsonb_build_object(
      'id', v_user.id,
      'display_name', v_user.display_name,
      'account_status', v_user.account_status,
      'mfa_required', v_user.mfa_required,
      'agency_id', v_user.agency_id
    ),
    'roles', coalesce((
      select jsonb_agg(r.key order by r.key)
      from public.user_roles ur join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid()
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(distinct p.code order by p.code)
      from public.user_roles ur
      join public.role_permissions rp on rp.role_id = ur.role_id
      join public.permissions p on p.id = rp.permission_id
      where ur.user_id = auth.uid()
    ), '[]'::jsonb),
    'shops', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.shop_name, 'status', s.status, 'verification_status', s.verification_status,
        'title', su.title
      ) order by s.shop_name)
      from public.shop_users su join public.shops s on s.id = su.shop_id
      where su.user_id = auth.uid() and su.is_active
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.api_create_device(
  p_shop_id uuid,
  p_brand text,
  p_model text,
  p_color text,
  p_serial_number text,
  p_imei1 text,
  p_imei2 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device_id uuid := extensions.gen_random_uuid();
  v_imei1 text := public.normalize_imei(p_imei1);
  v_imei2 text := nullif(public.normalize_imei(p_imei2), '');
  v_brand text := nullif(btrim(p_brand), '');
  v_model text := nullif(btrim(p_model), '');
  v_serial text := nullif(btrim(p_serial_number), '');
begin
  perform private.require_permission('create_device');
  perform private.require_operational_shop(p_shop_id);

  if v_brand is null or v_model is null then
    raise exception 'DEVICE_BRAND_AND_MODEL_REQUIRED' using errcode = '22023';
  end if;
  if not public.is_valid_imei(v_imei1)
     or (v_imei2 is not null and not public.is_valid_imei(v_imei2))
     or v_imei1 = v_imei2 then
    raise exception 'INVALID_IMEI' using errcode = '22023';
  end if;
  if exists (select 1 from public.device_imeis di where di.imei in (v_imei1, v_imei2)) then
    raise exception 'DUPLICATE_IMEI' using errcode = '23505';
  end if;

  insert into public.devices (
    id, brand, model, color, serial_number, status, registered_shop_id, created_by
  ) values (
    v_device_id, left(v_brand, 100), left(v_model, 160), nullif(left(btrim(p_color), 100), ''),
    v_serial, 'registered', p_shop_id, auth.uid()
  );

  insert into public.device_imeis (device_id, slot, imei, created_by)
  values (v_device_id, 1, v_imei1, auth.uid());
  if v_imei2 is not null then
    insert into public.device_imeis (device_id, slot, imei, created_by)
    values (v_device_id, 2, v_imei2, auth.uid());
  end if;

  perform private.append_device_event(
    v_device_id, 'device_registered', 'device', v_device_id, null, p_shop_id, null,
    'تم تسجيل هوية الجهاز.', jsonb_build_object('imei_last4', private.safe_imei_last4(v_imei1))
  );
  perform private.append_audit(
    'create_device', 'device', v_device_id, null,
    jsonb_build_object('brand', v_brand, 'model', v_model, 'imei_last4', private.safe_imei_last4(v_imei1)),
    'success', jsonb_build_object('shop_id', p_shop_id)
  );

  return jsonb_build_object(
    'device_id', v_device_id, 'status', 'registered', 'imei1', v_imei1, 'imei2', v_imei2
  );
end;
$$;

-- Only encrypted envelopes and HMAC blind indexes are accepted. Plain PII is rejected by convention
-- and is never returned by this RPC; the Edge Function is the only encryption/decryption boundary.
create or replace function public.api_create_customer(
  p_full_name_ciphertext text,
  p_phone_ciphertext text,
  p_national_id_ciphertext text,
  p_address_ciphertext text,
  p_full_name_lookup_hash text,
  p_phone_lookup_hash text,
  p_national_id_lookup_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_customer_id uuid := extensions.gen_random_uuid();
  v_reference text := private.document_number('CUS');
begin
  perform private.require_active_account();
  if not (public.has_permission('create_sale') or public.has_permission('create_stolen_report')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if coalesce(length(p_full_name_ciphertext), 0) > 16384
    or coalesce(length(p_phone_ciphertext), 0) > 16384
    or coalesce(length(p_national_id_ciphertext), 0) > 16384
    or coalesce(length(p_address_ciphertext), 0) > 16384
    or (p_full_name_ciphertext is null and p_phone_ciphertext is null and p_national_id_ciphertext is null) then
    raise exception 'INVALID_ENCRYPTED_CUSTOMER_PAYLOAD' using errcode = '22023';
  end if;

  insert into public.customers (id, reference_code, created_by)
  values (v_customer_id, v_reference, auth.uid());

  insert into public.customer_sensitive_data (
    customer_id, full_name_ciphertext, phone_ciphertext, national_id_ciphertext, address_ciphertext,
    full_name_lookup_hash, phone_lookup_hash, national_id_lookup_hash, created_by
  ) values (
    v_customer_id, p_full_name_ciphertext, p_phone_ciphertext, p_national_id_ciphertext, p_address_ciphertext,
    p_full_name_lookup_hash, p_phone_lookup_hash, p_national_id_lookup_hash, auth.uid()
  );

  perform private.append_audit(
    'create_customer', 'customer', v_customer_id, null,
    jsonb_build_object('reference_code', v_reference), 'success', jsonb_build_object('encrypted', true)
  );
  return jsonb_build_object('customer_id', v_customer_id, 'reference_code', v_reference);
end;
$$;

create or replace function public.api_register_sale(
  p_shop_id uuid,
  p_imei text,
  p_customer_id uuid,
  p_unit_price numeric default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_imei text := public.normalize_imei(p_imei);
  v_device_id uuid;
  v_status public.device_status;
  v_registered_shop uuid;
  v_sale_id uuid := extensions.gen_random_uuid();
  v_sale_number text := private.document_number('SAL');
begin
  perform private.require_permission('create_sale');
  perform private.require_operational_shop(p_shop_id);

  if not public.is_valid_imei(v_imei) then
    raise exception 'INVALID_IMEI' using errcode = '22023';
  end if;
  if p_unit_price is not null and (p_unit_price < 0 or p_unit_price > 999999999999.99) then
    raise exception 'INVALID_SALE_VALUE' using errcode = '22023';
  end if;

  select d.id, d.status, d.registered_shop_id
    into v_device_id, v_status, v_registered_shop
  from public.device_imeis di join public.devices d on d.id = di.device_id
  where di.imei = v_imei
  for update of d;

  if not found then
    raise exception 'DEVICE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_registered_shop is distinct from p_shop_id then
    raise exception 'DEVICE_OUT_OF_SHOP_SCOPE' using errcode = '42501';
  end if;
  if v_status in ('flagged', 'stolen', 'blocked') or exists (
    select 1 from public.stolen_reports sr
    where sr.device_id = v_device_id
      and sr.status not in ('closed', 'rejected', 'cancelled')
  ) then
    raise exception 'DEVICE_SECURITY_ALERT' using errcode = '22023';
  end if;
  if not exists (select 1 from public.customers c where c.id = p_customer_id) then
    raise exception 'CUSTOMER_NOT_FOUND' using errcode = 'P0002';
  end if;

  insert into public.sales (id, sale_number, shop_id, customer_id, notes, created_by)
  values (v_sale_id, v_sale_number, p_shop_id, p_customer_id, nullif(left(p_notes, 2000), ''), auth.uid());
  insert into public.sale_items (sale_id, device_id, imei_snapshot, unit_price)
  values (v_sale_id, v_device_id, v_imei, p_unit_price);

  perform private.transition_device(
    v_device_id, 'sold', 'device_sold', 'sale', v_sale_id, v_sale_number,
    'تم تسجيل بيع الجهاز.', jsonb_build_object('sale_number', v_sale_number)
  );
  perform private.append_audit(
    'create_sale', 'sale', v_sale_id, null,
    jsonb_build_object('sale_number', v_sale_number, 'device_id', v_device_id, 'imei_last4', private.safe_imei_last4(v_imei)),
    'success', jsonb_build_object('shop_id', p_shop_id)
  );

  return jsonb_build_object('sale_id', v_sale_id, 'sale_number', v_sale_number, 'device_id', v_device_id);
end;
$$;

create or replace function public.api_create_repair(
  p_shop_id uuid,
  p_imei text,
  p_technician_id uuid default null,
  p_operation_type text default null,
  p_notes text default null,
  p_result text default 'received',
  p_before_images jsonb default '[]'::jsonb,
  p_after_images jsonb default '[]'::jsonb,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_imei text := public.normalize_imei(p_imei);
  v_device_id uuid;
  v_status public.device_status;
  v_technician uuid := coalesce(p_technician_id, auth.uid());
  v_repair_id uuid := extensions.gen_random_uuid();
  v_operation_number text := private.document_number('REP');
begin
  perform private.require_permission('create_repair');
  perform private.require_operational_shop(p_shop_id);

  if not public.is_valid_imei(v_imei)
    or nullif(btrim(p_operation_type), '') is null
    or jsonb_typeof(coalesce(p_before_images, '[]'::jsonb)) <> 'array'
    or jsonb_typeof(coalesce(p_after_images, '[]'::jsonb)) <> 'array' then
    raise exception 'INVALID_REPAIR_PAYLOAD' using errcode = '22023';
  end if;

  if v_technician <> auth.uid() and not public.has_permission('manage_shops') then
    raise exception 'TECHNICIAN_SPOOFING_FORBIDDEN' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.technicians t
    join public.shop_users su on su.user_id = t.user_id and su.shop_id = p_shop_id and su.is_active
    where t.user_id = v_technician and t.is_active
  ) then
    raise exception 'TECHNICIAN_NOT_APPROVED_FOR_SHOP' using errcode = '42501';
  end if;

  select d.id, d.status into v_device_id, v_status
  from public.device_imeis di join public.devices d on d.id = di.device_id
  where di.imei = v_imei
  for update of d;

  if not found then
    raise exception 'DEVICE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status in ('flagged', 'stolen', 'blocked') or exists (
    select 1 from public.stolen_reports sr
    where sr.device_id = v_device_id and sr.status not in ('closed', 'rejected', 'cancelled')
  ) then
    perform private.raise_security_event(
      'attempted_repair_of_reported_device', 'critical',
      jsonb_build_object('device_id', v_device_id, 'imei_last4', private.safe_imei_last4(v_imei), 'shop_id', p_shop_id)
    );
    raise exception 'DEVICE_SECURITY_ALERT' using errcode = '22023';
  end if;

  insert into public.repair_records (
    id, operation_number, shop_id, technician_id, device_id, imei_snapshot, operation_type,
    notes, before_images, after_images, result, operation_location_id, created_by, completed_at
  ) values (
    v_repair_id, v_operation_number, p_shop_id, v_technician, v_device_id, v_imei,
    left(btrim(p_operation_type), 160), nullif(left(p_notes, 3000), ''),
    coalesce(p_before_images, '[]'::jsonb), coalesce(p_after_images, '[]'::jsonb),
    left(coalesce(nullif(btrim(p_result), ''), 'received'), 500), p_location_id, auth.uid(), clock_timestamp()
  );

  perform private.transition_device(
    v_device_id, 'in_repair', 'device_in_repair', 'repair', v_repair_id, v_operation_number,
    'تم تسجيل عملية صيانة.', jsonb_build_object('operation_type', left(btrim(p_operation_type), 160))
  );
  perform private.append_device_event(
    v_device_id, 'repair_registered', 'repair', v_repair_id, v_operation_number, p_shop_id, null,
    'تم استلام الجهاز للصيانة.', jsonb_build_object('technician_id', v_technician)
  );
  perform private.append_audit(
    'create_repair', 'repair', v_repair_id, null,
    jsonb_build_object('operation_number', v_operation_number, 'device_id', v_device_id, 'operation_type', left(btrim(p_operation_type), 160)),
    'success', jsonb_build_object('shop_id', p_shop_id, 'imei_last4', private.safe_imei_last4(v_imei))
  );

  return jsonb_build_object(
    'repair_id', v_repair_id, 'operation_number', v_operation_number, 'device_id', v_device_id,
    'technician_id', v_technician, 'created_at', clock_timestamp()
  );
end;
$$;

create or replace function public.api_create_format_record(
  p_shop_id uuid,
  p_imei text,
  p_technician_id uuid default null,
  p_format_type text default null,
  p_notes text default null,
  p_repair_record_id uuid default null,
  p_result text default 'completed'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_imei text := public.normalize_imei(p_imei);
  v_device_id uuid;
  v_status public.device_status;
  v_technician uuid := coalesce(p_technician_id, auth.uid());
  v_format_id uuid := extensions.gen_random_uuid();
  v_operation_number text := private.document_number('FMT');
begin
  perform private.require_permission('create_format_record');
  perform private.require_operational_shop(p_shop_id);

  if not public.is_valid_imei(v_imei) or nullif(btrim(p_format_type), '') is null then
    raise exception 'INVALID_FORMAT_PAYLOAD' using errcode = '22023';
  end if;
  if v_technician <> auth.uid() and not public.has_permission('manage_shops') then
    raise exception 'TECHNICIAN_SPOOFING_FORBIDDEN' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.technicians t
    join public.shop_users su on su.user_id = t.user_id and su.shop_id = p_shop_id and su.is_active
    where t.user_id = v_technician and t.is_active
  ) then
    raise exception 'TECHNICIAN_NOT_APPROVED_FOR_SHOP' using errcode = '42501';
  end if;

  select d.id, d.status into v_device_id, v_status
  from public.device_imeis di join public.devices d on d.id = di.device_id
  where di.imei = v_imei
  for update of d;
  if not found then
    raise exception 'DEVICE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status in ('flagged', 'stolen', 'blocked') or exists (
    select 1 from public.stolen_reports sr
    where sr.device_id = v_device_id and sr.status not in ('closed', 'rejected', 'cancelled')
  ) then
    perform private.raise_security_event(
      'attempted_format_of_reported_device', 'critical',
      jsonb_build_object('device_id', v_device_id, 'imei_last4', private.safe_imei_last4(v_imei), 'shop_id', p_shop_id)
    );
    raise exception 'DEVICE_SECURITY_ALERT' using errcode = '22023';
  end if;
  if p_repair_record_id is not null and not exists (
    select 1 from public.repair_records rr
    where rr.id = p_repair_record_id and rr.device_id = v_device_id and rr.shop_id = p_shop_id
  ) then
    raise exception 'REPAIR_SCOPE_MISMATCH' using errcode = '22023';
  end if;

  insert into public.format_records (
    id, operation_number, repair_record_id, shop_id, technician_id, device_id,
    imei_snapshot, format_type, notes, result, created_by
  ) values (
    v_format_id, v_operation_number, p_repair_record_id, p_shop_id, v_technician, v_device_id,
    v_imei, left(btrim(p_format_type), 160), nullif(left(p_notes, 3000), ''),
    left(coalesce(nullif(btrim(p_result), ''), 'completed'), 500), auth.uid()
  );

  perform private.transition_device(
    v_device_id, 'formatted', 'device_formatted', 'format_record', v_format_id, v_operation_number,
    'تم تسجيل عملية فرمتة.', jsonb_build_object('format_type', left(btrim(p_format_type), 160))
  );
  perform private.append_audit(
    'create_format_record', 'format_record', v_format_id, null,
    jsonb_build_object('operation_number', v_operation_number, 'device_id', v_device_id, 'format_type', left(btrim(p_format_type), 160)),
    'success', jsonb_build_object('shop_id', p_shop_id, 'imei_last4', private.safe_imei_last4(v_imei))
  );

  return jsonb_build_object('format_id', v_format_id, 'operation_number', v_operation_number, 'device_id', v_device_id);
end;
$$;

create or replace function public.api_create_stolen_report(
  p_imei text,
  p_reporter_customer_id uuid,
  p_report_type text,
  p_incident_at timestamptz,
  p_description text,
  p_priority public.report_priority default 'normal',
  p_agency_id uuid default null,
  p_incident_location_id uuid default null,
  p_imei2 text default null,
  p_brand text default null,
  p_model text default null,
  p_color text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_imei text := public.normalize_imei(p_imei);
  v_imei2 text := nullif(public.normalize_imei(p_imei2), '');
  v_device_id uuid;
  v_device_status public.device_status;
  v_agency_id uuid;
  v_report_id uuid := extensions.gen_random_uuid();
  v_report_number text := private.document_number('RPT');
begin
  perform private.require_permission('create_stolen_report', true);
  select coalesce(p_agency_id, u.agency_id) into v_agency_id
  from public.users u where u.id = auth.uid();

  if not public.is_valid_imei(v_imei)
    or (v_imei2 is not null and (not public.is_valid_imei(v_imei2) or v_imei2 = v_imei))
    or nullif(btrim(p_report_type), '') is null
    or p_incident_at > clock_timestamp() + interval '5 minutes'
    or char_length(coalesce(p_description, '')) < 5 then
    raise exception 'INVALID_REPORT_PAYLOAD' using errcode = '22023';
  end if;
  -- An official can file into their own agency. Only a system administrator can explicitly choose another agency.
  if v_agency_id is null
    or not exists (select 1 from public.agencies a where a.id = v_agency_id and a.is_active)
    or (p_agency_id is not null and not public.is_system_admin()
        and p_agency_id is distinct from (select u.agency_id from public.users u where u.id = auth.uid())) then
    raise exception 'INVALID_OR_OUT_OF_SCOPE_AGENCY' using errcode = '42501';
  end if;
  if not exists (select 1 from public.customers c where c.id = p_reporter_customer_id) then
    raise exception 'REPORTER_NOT_FOUND' using errcode = 'P0002';
  end if;

  select d.id, d.status into v_device_id, v_device_status
  from public.device_imeis di join public.devices d on d.id = di.device_id
  where di.imei = v_imei
  for update of d;

  if not found then
    v_device_id := extensions.gen_random_uuid();
    insert into public.devices (id, brand, model, color, status, registered_shop_id, created_by)
    values (
      v_device_id,
      coalesce(nullif(left(btrim(p_brand), 100), ''), 'غير محدد'),
      coalesce(nullif(left(btrim(p_model), 160), ''), 'غير محدد'),
      nullif(left(btrim(p_color), 100), ''),
      'registered', null, auth.uid()
    );
    insert into public.device_imeis (device_id, slot, imei, created_by)
    values (v_device_id, 1, v_imei, auth.uid());
    if v_imei2 is not null then
      if exists (select 1 from public.device_imeis where imei = v_imei2) then
        raise exception 'DUPLICATE_IMEI' using errcode = '23505';
      end if;
      insert into public.device_imeis (device_id, slot, imei, created_by)
      values (v_device_id, 2, v_imei2, auth.uid());
    end if;
    v_device_status := 'registered';
    perform private.append_device_event(
      v_device_id, 'device_registered_from_report', 'device', v_device_id, null, null, v_agency_id,
      'تم تسجيل هوية جهاز ضمن بلاغ.', jsonb_build_object('imei_last4', private.safe_imei_last4(v_imei))
    );
  end if;

  if exists (
    select 1 from public.stolen_reports sr
    where sr.device_id = v_device_id and sr.status not in ('closed', 'rejected', 'cancelled')
  ) then
    raise exception 'ACTIVE_REPORT_ALREADY_EXISTS' using errcode = '23505';
  end if;

  insert into public.stolen_reports (
    id, report_number, device_id, imei_snapshot, imei2_snapshot, reporter_customer_id,
    report_type, incident_at, incident_location_id, description, status, priority, agency_id, created_by
  ) values (
    v_report_id, v_report_number, v_device_id, v_imei, v_imei2, p_reporter_customer_id,
    left(btrim(p_report_type), 100), p_incident_at, p_incident_location_id, left(btrim(p_description), 6000),
    'submitted', p_priority, v_agency_id, auth.uid()
  );
  insert into public.report_status_history (report_id, from_status, to_status, note, changed_by)
  values (v_report_id, null, 'submitted', 'تم تقديم البلاغ.', auth.uid());

  if v_device_status not in ('flagged', 'stolen') then
    perform private.transition_device(
      v_device_id, 'flagged', 'device_reported', 'stolen_report', v_report_id, v_report_number,
      'تم فتح بلاغ على الجهاز.', jsonb_build_object('report_number', v_report_number)
    );
  end if;
  perform private.append_device_event(
    v_device_id, 'report_submitted', 'stolen_report', v_report_id, v_report_number, null, v_agency_id,
    'تم تقديم بلاغ سرقة.', jsonb_build_object('priority', p_priority)
  );
  perform private.append_audit(
    'create_report', 'stolen_report', v_report_id, null,
    jsonb_build_object('report_number', v_report_number, 'device_id', v_device_id, 'priority', p_priority),
    'success', jsonb_build_object('imei_last4', private.safe_imei_last4(v_imei))
  );
  perform private.raise_security_event(
    'stolen_report_submitted', 'important',
    jsonb_build_object('report_id', v_report_id, 'report_number', v_report_number, 'device_id', v_device_id)
  );

  return jsonb_build_object('report_id', v_report_id, 'report_number', v_report_number, 'device_id', v_device_id, 'status', 'submitted');
end;
$$;

create or replace function public.api_update_report_status(
  p_report_id uuid,
  p_to_status public.report_status,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_report public.stolen_reports%rowtype;
  v_device_status public.device_status;
begin
  perform private.require_permission('change_report_status', true);
  if not public.can_access_report(p_report_id) then
    raise exception 'REPORT_OUT_OF_SCOPE' using errcode = '42501';
  end if;

  select * into v_report from public.stolen_reports where id = p_report_id for update;
  if not found then
    raise exception 'REPORT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_report.status = p_to_status or not exists (
    select 1 from public.report_status_transitions
    where from_status = v_report.status and to_status = p_to_status
  ) then
    raise exception 'INVALID_REPORT_STATUS_TRANSITION' using errcode = '22023';
  end if;

  perform set_config('app.report_status_transition', 'on', true);
  perform set_config('app.report_assignment', 'off', true);
  update public.stolen_reports
     set status = p_to_status,
         updated_at = clock_timestamp(),
         closed_at = case when p_to_status = 'closed' then clock_timestamp() else null end
   where id = p_report_id;

  insert into public.report_status_history (report_id, from_status, to_status, note, changed_by)
  values (p_report_id, v_report.status, p_to_status, nullif(left(p_note, 3000), ''), auth.uid());

  select status into v_device_status from public.devices where id = v_report.device_id;
  if p_to_status in ('verified', 'active', 'assigned') and v_device_status <> 'stolen'
    and exists (select 1 from public.device_status_transitions where from_status = v_device_status and to_status = 'stolen') then
    perform private.transition_device(
      v_report.device_id, 'stolen', 'report_verified_or_active', 'stolen_report', p_report_id, v_report.report_number,
      'تم تأكيد أو تفعيل البلاغ.', jsonb_build_object('report_status', p_to_status)
    );
  elsif p_to_status = 'recovered' and v_device_status <> 'recovered'
    and exists (select 1 from public.device_status_transitions where from_status = v_device_status and to_status = 'recovered') then
    perform private.transition_device(
      v_report.device_id, 'recovered', 'device_recovered', 'stolen_report', p_report_id, v_report.report_number,
      'تم تسجيل استرداد الجهاز.', jsonb_build_object('report_status', p_to_status)
    );
  elsif p_to_status in ('rejected', 'cancelled')
    and v_device_status = 'flagged'
    and not exists (
      select 1 from public.stolen_reports sr
      where sr.device_id = v_report.device_id
        and sr.id <> p_report_id
        and sr.status not in ('closed', 'rejected', 'cancelled')
    ) then
    perform private.transition_device(
      v_report.device_id, 'available', 'report_closed_without_activation', 'stolen_report', p_report_id, v_report.report_number,
      'أغلق البلاغ دون استمرار التنبيه.', jsonb_build_object('report_status', p_to_status)
    );
  end if;

  perform private.append_device_event(
    v_report.device_id, 'report_status_changed', 'stolen_report', p_report_id, v_report.report_number,
    null, v_report.agency_id, nullif(left(p_note, 3000), ''),
    jsonb_build_object('from_status', v_report.status, 'to_status', p_to_status)
  );
  perform private.append_audit(
    'change_report_status', 'stolen_report', p_report_id,
    jsonb_build_object('status', v_report.status), jsonb_build_object('status', p_to_status), 'success',
    jsonb_build_object('report_number', v_report.report_number)
  );

  return jsonb_build_object('report_id', p_report_id, 'report_number', v_report.report_number, 'status', p_to_status);
end;
$$;

create or replace function public.api_assign_report(
  p_report_id uuid,
  p_assigned_officer_id uuid default null,
  p_assigned_delegate_id uuid default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_report public.stolen_reports%rowtype;
begin
  perform private.require_permission('assign_case', true);
  if not public.can_access_report(p_report_id) then
    raise exception 'REPORT_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  select * into v_report from public.stolen_reports where id = p_report_id for update;
  if not found then
    raise exception 'REPORT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if p_assigned_officer_id is null and p_assigned_delegate_id is null then
    raise exception 'ASSIGNEE_REQUIRED' using errcode = '22023';
  end if;
  -- A case is only delegated inside its owning agency; a system administrator is the sole global exception.
  if p_assigned_officer_id is not null and not exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    join public.users u on u.id = ur.user_id
    where ur.user_id = p_assigned_officer_id
      and u.account_status = 'active'
      and r.key in ('authorized_officer', 'investigation_officer', 'system_admin')
      and (r.key = 'system_admin' or u.agency_id = v_report.agency_id)
  ) then
    raise exception 'INVALID_ASSIGNED_OFFICER' using errcode = '22023';
  end if;
  if p_assigned_delegate_id is not null and not exists (
    select 1 from public.delegates d join public.users u on u.id = d.user_id
    where d.user_id = p_assigned_delegate_id and d.is_active and u.account_status = 'active'
      and d.agency_id = v_report.agency_id
  ) then
    raise exception 'INVALID_ASSIGNED_DELEGATE' using errcode = '22023';
  end if;
  if v_report.status in ('verified', 'active') then
    perform public.api_update_report_status(p_report_id, 'assigned', 'تم تعيين الحالة.');
    select * into v_report from public.stolen_reports where id = p_report_id;
  elsif v_report.status <> 'assigned' then
    raise exception 'REPORT_NOT_ASSIGNABLE' using errcode = '22023';
  end if;

  perform set_config('app.report_assignment', 'on', true);
  perform set_config('app.report_status_transition', 'off', true);
  update public.stolen_reports
     set assigned_officer_id = p_assigned_officer_id,
         assigned_delegate_id = p_assigned_delegate_id,
         updated_at = clock_timestamp()
   where id = p_report_id;

  perform private.append_device_event(
    v_report.device_id, 'report_assigned', 'stolen_report', p_report_id, v_report.report_number,
    null, v_report.agency_id, nullif(left(p_note, 3000), ''),
    jsonb_strip_nulls(jsonb_build_object('officer_id', p_assigned_officer_id, 'delegate_id', p_assigned_delegate_id))
  );
  perform private.append_audit(
    'assign_case', 'stolen_report', p_report_id,
    jsonb_strip_nulls(jsonb_build_object('assigned_officer_id', v_report.assigned_officer_id, 'assigned_delegate_id', v_report.assigned_delegate_id)),
    jsonb_strip_nulls(jsonb_build_object('assigned_officer_id', p_assigned_officer_id, 'assigned_delegate_id', p_assigned_delegate_id)),
    'success', jsonb_build_object('report_number', v_report.report_number)
  );

  insert into public.notifications (recipient_id, severity, notification_type, title, body, entity_type, entity_id)
  select assigned_id, 'important'::public.notification_severity, 'case_assigned', 'تم تعيين حالة لك', 'تم تحويل حالة تحتاج إلى متابعة.', 'stolen_report', p_report_id
  from unnest(array[p_assigned_officer_id, p_assigned_delegate_id]) as assigned_id
  where assigned_id is not null;

  return jsonb_build_object('report_id', p_report_id, 'status', 'assigned');
end;
$$;

create or replace function public.api_check_imei(p_imei text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_imei text := public.normalize_imei(p_imei);
  v_device_id uuid;
  v_status public.device_status;
  v_brand text;
  v_model text;
  v_report public.stolen_reports%rowtype;
  v_device_found boolean := false;
  v_is_reported boolean := false;
  v_can_view_device boolean := false;
  v_can_view_report boolean := false;
  v_searches integer;
  v_reported_searches integer;
begin
  perform private.require_permission('search_imei');
  if not public.is_valid_imei(v_imei) then
    raise exception 'INVALID_IMEI' using errcode = '22023';
  end if;

  select d.id, d.status, d.brand, d.model into v_device_id, v_status, v_brand, v_model
  from public.device_imeis di join public.devices d on d.id = di.device_id
  where di.imei = v_imei;
  v_device_found := found;

  if v_device_found then
    select * into v_report
    from public.stolen_reports sr
    where sr.device_id = v_device_id
      and sr.status not in ('closed', 'rejected', 'cancelled')
    order by sr.created_at desc
    limit 1;
    v_is_reported := found;
    v_can_view_device := public.has_permission('view_device') and public.can_access_device(v_device_id);
    v_can_view_report := v_is_reported and public.can_access_report(v_report.id);
  end if;

  perform private.append_audit(
    'search_imei', 'device', v_device_id, null, null, 'success',
    jsonb_build_object('imei_last4', private.safe_imei_last4(v_imei), 'found', v_device_id is not null, 'reported', v_is_reported)
  );

  select count(*) into v_searches
  from public.audit_logs al
  where al.actor_id = auth.uid() and al.action = 'search_imei'
    and al.occurred_at >= clock_timestamp() - interval '10 minutes';
  if v_searches = private.setting_integer('security.imei_checks_per_10m', 30) then
    perform private.raise_security_event(
      'high_volume_imei_search', 'warning',
      jsonb_build_object('count_10m', v_searches), auth.uid()
    );
  end if;

  if v_is_reported then
    select count(*) into v_reported_searches
    from public.audit_logs al
    where al.actor_id = auth.uid()
      and al.action = 'search_imei'
      and al.entity_id = v_device_id
      and al.occurred_at >= clock_timestamp() - interval '10 minutes';
    if v_reported_searches = 5 then
      perform private.raise_security_event(
        'repeated_reported_device_search', 'important',
        jsonb_build_object('device_id', v_device_id, 'count_10m', v_reported_searches), auth.uid()
      );
    end if;
  end if;

  if not v_device_found then
    return jsonb_build_object(
      'imei', v_imei, 'found', false, 'security_alert', false,
      'message_code', 'not_registered', 'message_ar', 'لم يُعثر على الجهاز في السجل المركزي.'
    );
  elsif v_is_reported then
    return jsonb_strip_nulls(jsonb_build_object(
      'imei', v_imei, 'found', true, 'security_alert', true,
      'message_code', 'reported_device',
      'message_ar', 'هذا الجهاز مسجل ضمن الأجهزة المبلغ عنها. يرجى عدم اتخاذ أي إجراء خارج الصلاحيات المعتمدة والتواصل مع الجهة المختصة.',
      'device', case when v_can_view_device then jsonb_build_object('id', v_device_id, 'brand', v_brand, 'model', v_model, 'status', v_status) else null end,
      'report', case when v_can_view_report then jsonb_build_object(
        'id', v_report.id, 'report_number', v_report.report_number, 'status', v_report.status,
        'priority', v_report.priority, 'created_at', v_report.created_at, 'agency_id', v_report.agency_id
      ) else null end
    ));
  else
    return jsonb_build_object(
      'imei', v_imei, 'found', true, 'security_alert', false,
      'message_code', 'no_active_report', 'message_ar', 'الجهاز غير مسجل عليه بلاغ نشط.',
      'device', case when v_can_view_device then jsonb_build_object('id', v_device_id, 'brand', v_brand, 'model', v_model, 'status', v_status) else null end
    );
  end if;
end;
$$;

create or replace function public.api_get_device_timeline(
  p_device_id uuid,
  p_limit integer default 40,
  p_before timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device public.devices%rowtype;
  v_limit integer := greatest(1, least(coalesce(p_limit, 40), 100));
begin
  perform private.require_permission('view_device');
  if not public.can_access_device(p_device_id) then
    raise exception 'DEVICE_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  select * into v_device from public.devices where id = p_device_id;
  if not found then
    raise exception 'DEVICE_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.append_audit('view_device', 'device', p_device_id, null, null, 'success');

  return jsonb_build_object(
    'device', jsonb_build_object(
      'id', v_device.id, 'brand', v_device.brand, 'model', v_device.model, 'color', v_device.color,
      'serial_number', v_device.serial_number, 'status', v_device.status, 'created_at', v_device.created_at,
      'imeis', coalesce((select jsonb_agg(jsonb_build_object('slot', di.slot, 'imei', di.imei) order by di.slot)
                          from public.device_imeis di where di.device_id = p_device_id), '[]'::jsonb)
    ),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'event_type', e.event_type, 'entity_type', e.entity_type, 'entity_id', e.entity_id,
        'operation_number', e.operation_number, 'actor_id', e.actor_id, 'shop_id', e.shop_id,
        'agency_id', e.agency_id, 'notes', e.notes, 'metadata', e.metadata, 'occurred_at', e.occurred_at
      ) order by e.occurred_at desc, e.id desc)
      from (
        select * from public.device_events e
        where e.device_id = p_device_id
          and (p_before is null or e.occurred_at < p_before)
        order by e.occurred_at desc, e.id desc
        limit v_limit
      ) e
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.api_get_reports(
  p_status public.report_status default null,
  p_limit integer default 30,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  perform private.require_active_account();
  if not (public.has_permission('view_all_reports') or public.has_permission('update_follow_up')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', q.id, 'report_number', q.report_number, 'device_id', q.device_id, 'imei_last4', private.safe_imei_last4(q.imei_snapshot),
      'report_type', q.report_type, 'incident_at', q.incident_at, 'status', q.status, 'priority', q.priority,
      'agency_id', q.agency_id, 'assigned_officer_id', q.assigned_officer_id, 'assigned_delegate_id', q.assigned_delegate_id,
      'created_at', q.created_at
    ) order by q.created_at desc)
    from (
      select sr.* from public.stolen_reports sr
      where public.can_access_report(sr.id)
        and (p_status is null or sr.status = p_status)
      order by sr.created_at desc
      limit v_limit offset v_offset
    ) q
  ), '[]'::jsonb);
end;
$$;

create or replace function public.api_get_report_detail(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_report public.stolen_reports%rowtype;
begin
  perform private.require_active_account();
  if not public.can_access_report(p_report_id) then
    raise exception 'REPORT_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  select * into v_report from public.stolen_reports where id = p_report_id;
  if not found then
    raise exception 'REPORT_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.append_audit('view_report', 'stolen_report', p_report_id, null, null, 'success');
  return jsonb_build_object(
    'report', jsonb_build_object(
      'id', v_report.id, 'report_number', v_report.report_number, 'device_id', v_report.device_id,
      'imei_snapshot', v_report.imei_snapshot, 'imei2_snapshot', v_report.imei2_snapshot,
      'report_type', v_report.report_type, 'incident_at', v_report.incident_at,
      'incident_location_id', v_report.incident_location_id, 'description', v_report.description,
      'status', v_report.status, 'priority', v_report.priority, 'agency_id', v_report.agency_id,
      'assigned_officer_id', v_report.assigned_officer_id, 'assigned_delegate_id', v_report.assigned_delegate_id,
      'created_at', v_report.created_at, 'updated_at', v_report.updated_at, 'closed_at', v_report.closed_at
    ),
    'status_history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', h.id, 'from_status', h.from_status, 'to_status', h.to_status, 'note', h.note,
        'changed_by', h.changed_by, 'changed_at', h.changed_at
      ) order by h.changed_at desc)
      from public.report_status_history h where h.report_id = p_report_id
    ), '[]'::jsonb),
    'follow_ups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'note', f.note, 'location_id', f.location_id, 'created_by', f.created_by, 'created_at', f.created_at
      ) order by f.created_at desc)
      from public.report_follow_ups f where f.report_id = p_report_id
    ), '[]'::jsonb),
    'evidence', case when public.has_permission('view_evidence') then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'evidence_type', e.evidence_type, 'original_name', e.original_name,
        'content_type', e.content_type, 'size_bytes', e.size_bytes, 'description', e.description,
        'access_level', e.access_level, 'status', e.status, 'uploaded_at', e.uploaded_at
      ) order by e.created_at desc)
      from public.evidence e where e.report_id = p_report_id and e.status = 'uploaded'
    ), '[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;

create or replace function public.api_create_evidence_upload_intent(
  p_report_id uuid,
  p_evidence_type text,
  p_original_name text,
  p_content_type text,
  p_size_bytes integer,
  p_description text default null,
  p_access_level public.evidence_access_level default 'restricted'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_evidence_id uuid := extensions.gen_random_uuid();
  v_safe_name text;
  v_path text;
begin
  perform private.require_permission('upload_evidence', true);
  if not public.can_access_report(p_report_id) then
    raise exception 'REPORT_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  if nullif(btrim(p_evidence_type), '') is null
    or p_content_type not in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')
    or p_size_bytes is null or p_size_bytes < 1 or p_size_bytes > 15728640 then
    raise exception 'INVALID_EVIDENCE_METADATA' using errcode = '22023';
  end if;

  v_safe_name := nullif(regexp_replace(left(coalesce(p_original_name, ''), 255), '[^A-Za-z0-9._-]', '_', 'g'), '');
  v_safe_name := coalesce(v_safe_name, 'evidence.bin');
  v_path := 'reports/' || p_report_id::text || '/' || v_evidence_id::text || '-' || v_safe_name;

  insert into public.evidence (
    id, report_id, evidence_type, storage_path, original_name, content_type, size_bytes,
    description, access_level, status, uploaded_by
  ) values (
    v_evidence_id, p_report_id, left(btrim(p_evidence_type), 100), v_path, v_safe_name,
    p_content_type, p_size_bytes, nullif(left(p_description, 3000), ''), p_access_level, 'pending_upload', auth.uid()
  );
  perform private.append_audit(
    'create_evidence_upload', 'evidence', v_evidence_id, null,
    jsonb_build_object('report_id', p_report_id, 'type', p_evidence_type, 'access_level', p_access_level), 'success'
  );
  return jsonb_build_object('evidence_id', v_evidence_id, 'bucket', 'evidence-private', 'storage_path', v_path);
end;
$$;

create or replace function public.api_complete_evidence_upload(
  p_evidence_id uuid,
  p_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_evidence public.evidence%rowtype;
begin
  perform private.require_permission('upload_evidence', true);
  select * into v_evidence from public.evidence where id = p_evidence_id for update;
  if not found then
    raise exception 'EVIDENCE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.can_access_report(v_evidence.report_id) or v_evidence.uploaded_by <> auth.uid() then
    raise exception 'EVIDENCE_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  if v_evidence.status <> 'pending_upload' then
    raise exception 'EVIDENCE_NOT_PENDING' using errcode = '22023';
  end if;
  if p_sha256 is not null and p_sha256 !~ '^[a-fA-F0-9]{64}$' then
    raise exception 'INVALID_FILE_HASH' using errcode = '22023';
  end if;

  perform set_config('app.evidence_upload_completion', 'on', true);
  update public.evidence
     set status = 'uploaded', sha256 = lower(p_sha256), uploaded_at = clock_timestamp()
   where id = p_evidence_id;
  perform private.append_audit(
    'upload_evidence', 'evidence', p_evidence_id, jsonb_build_object('status', 'pending_upload'),
    jsonb_build_object('status', 'uploaded'), 'success', jsonb_build_object('report_id', v_evidence.report_id)
  );
  return jsonb_build_object('evidence_id', p_evidence_id, 'status', 'uploaded');
end;
$$;

create or replace function public.api_authorize_evidence_view(
  p_evidence_id uuid,
  p_purpose text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_evidence public.evidence%rowtype;
  v_ttl integer;
begin
  perform private.require_permission('view_evidence', true);
  if char_length(coalesce(btrim(p_purpose), '')) < 5 then
    raise exception 'ACCESS_PURPOSE_REQUIRED' using errcode = '22023';
  end if;
  select * into v_evidence from public.evidence where id = p_evidence_id;
  if not found or v_evidence.status <> 'uploaded' then
    raise exception 'EVIDENCE_NOT_AVAILABLE' using errcode = 'P0002';
  end if;
  if not public.can_access_report(v_evidence.report_id) then
    raise exception 'EVIDENCE_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  if v_evidence.access_level = 'sealed' and not public.has_permission('view_identity') then
    raise exception 'SEALED_EVIDENCE_FORBIDDEN' using errcode = '42501';
  end if;

  insert into public.evidence_access_logs (evidence_id, actor_id, purpose, permission_used)
  values (p_evidence_id, auth.uid(), left(btrim(p_purpose), 500), 'view_evidence');
  perform private.append_audit(
    'view_evidence', 'evidence', p_evidence_id, null, null, 'success',
    jsonb_build_object('report_id', v_evidence.report_id, 'purpose', left(btrim(p_purpose), 500))
  );
  v_ttl := least(greatest(private.setting_integer('security.signed_url_ttl_seconds', 60), 30), 300);
  return jsonb_build_object('bucket', 'evidence-private', 'storage_path', v_evidence.storage_path, 'ttl_seconds', v_ttl);
end;
$$;

create or replace function public.api_create_device_media_upload_intent(
  p_device_id uuid,
  p_repair_record_id uuid,
  p_kind public.media_kind,
  p_original_name text,
  p_content_type text,
  p_size_bytes integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_media_id uuid := extensions.gen_random_uuid();
  v_safe_name text;
  v_path text;
begin
  perform private.require_active_account();
  if not (public.has_permission('create_device') or public.has_permission('create_repair')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not public.can_access_device(p_device_id) then
    raise exception 'DEVICE_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  if p_repair_record_id is not null and not exists (
    select 1 from public.repair_records rr
    where rr.id = p_repair_record_id and rr.device_id = p_device_id
      and exists (select 1 from public.shop_users su where su.shop_id = rr.shop_id and su.user_id = auth.uid() and su.is_active)
  ) then
    raise exception 'REPAIR_SCOPE_MISMATCH' using errcode = '42501';
  end if;
  if p_content_type not in ('image/jpeg', 'image/png', 'image/webp') or p_size_bytes not between 1 and 10485760 then
    raise exception 'INVALID_MEDIA_METADATA' using errcode = '22023';
  end if;

  v_safe_name := nullif(regexp_replace(left(coalesce(p_original_name, ''), 255), '[^A-Za-z0-9._-]', '_', 'g'), '');
  v_safe_name := coalesce(v_safe_name, 'device-image.jpg');
  v_path := 'devices/' || p_device_id::text || '/' || v_media_id::text || '-' || v_safe_name;
  insert into public.device_media (
    id, device_id, repair_record_id, kind, storage_path, original_name, content_type, size_bytes, status, uploaded_by
  ) values (
    v_media_id, p_device_id, p_repair_record_id, p_kind, v_path, v_safe_name, p_content_type, p_size_bytes, 'pending_upload', auth.uid()
  );
  perform private.append_audit('create_media_upload', 'device_media', v_media_id, null, null, 'success', jsonb_build_object('device_id', p_device_id));
  return jsonb_build_object('media_id', v_media_id, 'bucket', 'device-media-private', 'storage_path', v_path);
end;
$$;

create or replace function public.api_complete_device_media_upload(
  p_media_id uuid,
  p_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_media public.device_media%rowtype;
begin
  perform private.require_active_account();
  select * into v_media from public.device_media where id = p_media_id for update;
  if not found then
    raise exception 'MEDIA_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_media.uploaded_by <> auth.uid() or not public.can_access_device(v_media.device_id) then
    raise exception 'MEDIA_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  if v_media.status <> 'pending_upload' then
    raise exception 'MEDIA_NOT_PENDING' using errcode = '22023';
  end if;
  if p_sha256 is not null and p_sha256 !~ '^[a-fA-F0-9]{64}$' then
    raise exception 'INVALID_FILE_HASH' using errcode = '22023';
  end if;

  perform set_config('app.media_upload_completion', 'on', true);
  update public.device_media
     set status = 'uploaded', sha256 = lower(p_sha256), uploaded_at = clock_timestamp()
   where id = p_media_id;
  perform private.append_device_event(
    v_media.device_id, 'device_photo_uploaded', 'device_media', p_media_id, null, null, null,
    'تم رفع صورة للجهاز.', jsonb_build_object('kind', v_media.kind)
  );
  perform private.append_audit('upload_device_media', 'device_media', p_media_id, null, null, 'success', jsonb_build_object('device_id', v_media.device_id));
  return jsonb_build_object('media_id', p_media_id, 'status', 'uploaded');
end;
$$;

create or replace function public.api_authorize_device_media_view(
  p_media_id uuid,
  p_purpose text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_media public.device_media%rowtype;
  v_ttl integer;
begin
  perform private.require_permission('view_device');
  if char_length(coalesce(btrim(p_purpose), '')) < 5 then
    raise exception 'ACCESS_PURPOSE_REQUIRED' using errcode = '22023';
  end if;
  select * into v_media from public.device_media where id = p_media_id;
  if not found or v_media.status <> 'uploaded' then
    raise exception 'MEDIA_NOT_AVAILABLE' using errcode = 'P0002';
  end if;
  if not public.can_access_device(v_media.device_id) then
    raise exception 'MEDIA_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  perform private.append_audit(
    'view_device_media', 'device_media', p_media_id, null, null, 'success',
    jsonb_build_object('device_id', v_media.device_id, 'purpose', left(btrim(p_purpose), 500))
  );
  v_ttl := least(greatest(private.setting_integer('security.signed_url_ttl_seconds', 60), 30), 300);
  return jsonb_build_object('bucket', 'device-media-private', 'storage_path', v_media.storage_path, 'ttl_seconds', v_ttl);
end;
$$;

-- Authorization and logging happen inside PostgreSQL. Decryption is intentionally performed only in Edge Function memory.
create or replace function public.api_authorize_sensitive_customer_access(
  p_customer_id uuid,
  p_purpose text,
  p_include_identity boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_permission('view_sensitive_data', true);
  if p_include_identity then
    perform private.require_permission('view_identity', true);
  end if;
  if char_length(coalesce(btrim(p_purpose), '')) < 5 then
    raise exception 'ACCESS_PURPOSE_REQUIRED' using errcode = '22023';
  end if;
  if not exists (select 1 from public.customers where id = p_customer_id) then
    raise exception 'CUSTOMER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not public.can_access_customer(p_customer_id) then
    raise exception 'CUSTOMER_OUT_OF_SCOPE' using errcode = '42501';
  end if;

  perform private.log_sensitive_access(
    case when p_include_identity then 'customer_identity' else 'customer_personal_data' end,
    p_customer_id, left(btrim(p_purpose), 500),
    case when p_include_identity then 'view_identity' else 'view_sensitive_data' end
  );
  return jsonb_build_object('customer_id', p_customer_id, 'authorized', true, 'include_identity', p_include_identity);
end;
$$;

create or replace function public.api_get_notifications(p_limit integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_limit integer := greatest(1, least(coalesce(p_limit, 30), 100));
begin
  perform private.require_active_account();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', n.id, 'severity', n.severity, 'notification_type', n.notification_type,
      'title', n.title, 'body', n.body, 'entity_type', n.entity_type, 'entity_id', n.entity_id,
      'read_at', n.read_at, 'created_at', n.created_at
    ) order by n.created_at desc)
    from (
      select * from public.notifications n
      where n.recipient_id = auth.uid() and (n.expires_at is null or n.expires_at > clock_timestamp())
      order by n.created_at desc limit v_limit
    ) n
  ), '[]'::jsonb);
end;
$$;

create or replace function public.api_mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_active_account();
  if not exists (select 1 from public.notifications where id = p_notification_id and recipient_id = auth.uid()) then
    raise exception 'NOTIFICATION_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform set_config('app.notification_read', 'on', true);
  update public.notifications set read_at = coalesce(read_at, clock_timestamp()) where id = p_notification_id;
end;
$$;

create or replace function public.api_get_dashboard(
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_from timestamptz := coalesce(p_from, date_trunc('month', clock_timestamp()));
  v_to timestamptz := coalesce(p_to, clock_timestamp());
  v_global boolean;
  v_shop_ids uuid[];
begin
  perform private.require_permission('view_dashboard');
  if v_from > v_to or v_from < clock_timestamp() - interval '10 years' then
    raise exception 'INVALID_DATE_RANGE' using errcode = '22023';
  end if;

  v_global := public.has_permission('view_all_devices');
  select coalesce(array_agg(su.shop_id), '{}'::uuid[]) into v_shop_ids
  from public.shop_users su where su.user_id = auth.uid() and su.is_active;

  return jsonb_build_object(
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'devices_registered', (
      select count(*) from public.devices d
      where d.created_at between v_from and v_to
        and (v_global or d.registered_shop_id = any(v_shop_ids))
    ),
    'devices_sold', (
      select count(*) from public.sale_items si
      join public.sales s on s.id = si.sale_id
      where s.sale_date between v_from and v_to and (v_global or s.shop_id = any(v_shop_ids))
    ),
    'repair_operations', (
      select count(*) from public.repair_records rr
      where rr.created_at between v_from and v_to and (v_global or rr.shop_id = any(v_shop_ids))
    ),
    'format_operations', (
      select count(*) from public.format_records fr
      where fr.created_at between v_from and v_to and (v_global or fr.shop_id = any(v_shop_ids))
    ),
    'active_reports', case when public.has_permission('view_all_reports') or public.has_permission('update_follow_up') then (
      select count(*) from public.stolen_reports sr
      where sr.status not in ('closed', 'rejected', 'cancelled') and public.can_access_report(sr.id)
    ) else 0 end,
    'new_reports', case when public.has_permission('view_all_reports') or public.has_permission('update_follow_up') then (
      select count(*) from public.stolen_reports sr
      where sr.created_at between v_from and v_to and public.can_access_report(sr.id)
    ) else 0 end,
    'recovered_devices', case when v_global then (
      select count(*) from public.devices d where d.status = 'recovered' and d.updated_at between v_from and v_to
    ) else 0 end,
    'active_shops', case when public.has_permission('manage_shops') then (select count(*) from public.shops where status = 'approved') else 0 end,
    'suspended_shops', case when public.has_permission('manage_shops') then (select count(*) from public.shops where status = 'suspended') else 0 end,
    'suspicious_operations', case when public.has_permission('view_security_events') then (
      select count(*) from public.security_events se where se.created_at between v_from and v_to and se.severity in ('warning', 'important', 'critical')
    ) else 0 end,
    'unauthorized_attempts', case when public.has_permission('view_security_events') then (
      select count(*) from public.security_events se where se.created_at between v_from and v_to and se.event_type like '%unauthorized%'
    ) else 0 end
  );
end;
$$;

create or replace function public.api_add_record_correction(
  p_entity_type text,
  p_entity_id uuid,
  p_old_value jsonb,
  p_new_value jsonb,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_correction_id uuid := extensions.gen_random_uuid();
  v_entity_type text := lower(btrim(p_entity_type));
  v_entity_exists boolean := false;
begin
  perform private.require_permission('correct_record', true);
  if char_length(coalesce(btrim(p_reason), '')) < 5 or p_old_value is null or p_new_value is null
    or p_entity_id is null or v_entity_type not in ('device', 'stolen_report', 'sale', 'repair_record', 'format_record', 'evidence', 'customer') then
    raise exception 'INVALID_CORRECTION' using errcode = '22023';
  end if;

  v_entity_exists := case v_entity_type
    when 'device' then public.can_access_device(p_entity_id)
    when 'stolen_report' then public.can_access_report(p_entity_id)
    when 'sale' then exists (select 1 from public.sales s where s.id = p_entity_id and (public.is_system_admin() or public.can_access_shop(s.shop_id)))
    when 'repair_record' then exists (select 1 from public.repair_records rr where rr.id = p_entity_id and (public.is_system_admin() or public.can_access_shop(rr.shop_id)))
    when 'format_record' then exists (select 1 from public.format_records fr where fr.id = p_entity_id and (public.is_system_admin() or public.can_access_shop(fr.shop_id)))
    when 'evidence' then exists (select 1 from public.evidence e where e.id = p_entity_id and public.can_access_report(e.report_id))
    when 'customer' then public.can_access_customer(p_entity_id)
  end;
  if not coalesce(v_entity_exists, false) then
    raise exception 'CORRECTION_ENTITY_OUT_OF_SCOPE' using errcode = '42501';
  end if;

  insert into public.record_corrections (id, entity_type, entity_id, old_value, new_value, reason, created_by)
  values (v_correction_id, v_entity_type, p_entity_id, p_old_value, p_new_value, left(btrim(p_reason), 1000), auth.uid());
  perform private.append_audit('correct_record', v_entity_type, p_entity_id, p_old_value, p_new_value, 'success', jsonb_build_object('correction_id', v_correction_id, 'reason', left(btrim(p_reason), 1000)));
  return jsonb_build_object('correction_id', v_correction_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- 20260901000300_rls_storage.sql
-- ----------------------------------------------------------------------------
-- Row Level Security is a second enforcement layer. The browser has no write policy for
-- critical records; it must use the audited api_* functions through Edge Functions.

alter table public.agencies enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.users enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.locations enable row level security;
alter table public.shops enable row level security;
alter table public.shop_users enable row level security;
alter table public.technicians enable row level security;
alter table public.delegates enable row level security;
alter table public.device_status_transitions enable row level security;
alter table public.devices enable row level security;
alter table public.device_imeis enable row level security;
alter table public.device_media enable row level security;
alter table public.customers enable row level security;
alter table public.customer_sensitive_data enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.repair_records enable row level security;
alter table public.format_records enable row level security;
alter table public.stolen_reports enable row level security;
alter table public.report_status_history enable row level security;
alter table public.report_follow_ups enable row level security;
alter table public.report_status_transitions enable row level security;
alter table public.evidence enable row level security;
alter table public.evidence_access_logs enable row level security;
alter table public.audit_logs enable row level security;
alter table public.sensitive_data_access_logs enable row level security;
alter table public.security_events enable row level security;
alter table public.notifications enable row level security;
alter table public.device_events enable row level security;
alter table public.record_corrections enable row level security;
alter table public.system_settings enable row level security;

-- Directory/RBAC reads are deliberately narrow.
create policy agencies_read_authorized on public.agencies
for select to authenticated using (public.is_active_account());
create policy roles_read_active on public.roles
for select to authenticated using (public.is_active_account());
create policy permissions_read_active on public.permissions
for select to authenticated using (public.is_active_account());
create policy users_read_self_or_admin on public.users
for select to authenticated using (id = auth.uid() or public.has_permission('manage_users'));
create policy role_permissions_read_admin on public.role_permissions
for select to authenticated using (public.has_permission('manage_permissions'));
create policy user_roles_read_self_or_admin on public.user_roles
for select to authenticated using (user_id = auth.uid() or public.has_permission('manage_users'));

create policy locations_read_scoped on public.locations
for select to authenticated using (
  public.has_permission('view_all_reports') or public.has_permission('manage_shops')
);
create policy shops_read_scoped on public.shops
for select to authenticated using (public.can_access_shop(id) or public.has_permission('manage_shops'));
create policy shop_users_read_scoped on public.shop_users
for select to authenticated using (
  user_id = auth.uid() or public.has_permission('manage_shops') or public.can_access_shop(shop_id)
);
create policy technicians_read_scoped on public.technicians
for select to authenticated using (user_id = auth.uid() or public.has_permission('manage_shops'));
create policy delegates_read_self_or_admin on public.delegates
for select to authenticated using (user_id = auth.uid() or public.has_permission('manage_users'));
create policy device_transitions_read_admin on public.device_status_transitions
for select to authenticated using (public.has_permission('manage_system_settings'));
create policy report_transitions_read_admin on public.report_status_transitions
for select to authenticated using (public.has_permission('manage_system_settings'));

create policy devices_read_scoped on public.devices
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(id));
create policy device_imeis_read_scoped on public.device_imeis
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));
create policy device_media_read_scoped on public.device_media
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));

create policy customers_read_reference_scoped on public.customers
for select to authenticated using (public.has_permission('view_customer') and public.can_access_customer(id));
-- Intentionally no policy for customer_sensitive_data: ciphertext is only read by a service-role
-- Edge Function after api_authorize_sensitive_customer_access() has logged the purpose.

create policy sales_read_scoped on public.sales
for select to authenticated using (
  public.has_permission('view_sales') and (
    public.has_permission('view_all_devices') or exists (
      select 1 from public.shop_users su
      where su.shop_id = sales.shop_id and su.user_id = auth.uid() and su.is_active
    )
  )
);
create policy sale_items_read_scoped on public.sale_items
for select to authenticated using (public.has_permission('view_sales') and public.can_access_device(device_id));
create policy repairs_read_scoped on public.repair_records
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));
create policy formats_read_scoped on public.format_records
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));

create policy reports_read_scoped on public.stolen_reports
for select to authenticated using (public.can_access_report(id));
create policy report_history_read_scoped on public.report_status_history
for select to authenticated using (public.can_access_report(report_id));
create policy report_follow_ups_read_scoped on public.report_follow_ups
for select to authenticated using (public.can_access_report(report_id));
create policy evidence_read_scoped on public.evidence
for select to authenticated using (public.has_permission('view_evidence') and public.can_access_report(report_id));
create policy evidence_access_logs_read_audit on public.evidence_access_logs
for select to authenticated using (public.has_permission('view_audit_logs'));

create policy audit_logs_read_audit on public.audit_logs
for select to authenticated using (public.has_permission('view_audit_logs'));
create policy sensitive_access_logs_read_audit on public.sensitive_data_access_logs
for select to authenticated using (public.has_permission('view_audit_logs'));
create policy security_events_read_authorized on public.security_events
for select to authenticated using (public.has_permission('view_security_events'));
create policy notifications_read_own on public.notifications
for select to authenticated using (recipient_id = auth.uid());
create policy device_events_read_scoped on public.device_events
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));
create policy corrections_read_audit on public.record_corrections
for select to authenticated using (public.has_permission('view_audit_logs'));
create policy settings_read_non_sensitive_admin on public.system_settings
for select to authenticated using (public.has_permission('manage_system_settings') and not is_sensitive);

-- No direct INSERT/UPDATE/DELETE policy has been added to critical entities.
-- Explicit SELECT grants keep PostgREST from exposing unapproved write paths.
revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.agencies, public.roles, public.permissions, public.users, public.role_permissions,
  public.user_roles, public.locations, public.shops, public.shop_users, public.technicians, public.delegates,
  public.device_status_transitions, public.report_status_transitions, public.devices, public.device_imeis,
  public.device_media, public.customers, public.sales, public.sale_items, public.repair_records,
  public.format_records, public.stolen_reports, public.report_status_history, public.report_follow_ups, public.evidence,
  public.evidence_access_logs, public.audit_logs, public.sensitive_data_access_logs, public.security_events,
  public.notifications, public.device_events, public.record_corrections, public.system_settings
  to authenticated;

revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;

-- Private storage only. The browser receives scoped signed URLs from an Edge Function after a
-- database authorization + access-log operation. There is no public object URL and no direct policy.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('evidence-private', 'evidence-private', false, 15728640, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('device-media-private', 'device-media-private', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('identity-private', 'identity-private', false, 10485760, array['image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- These explicit deny policies document the invariant. service_role used inside Edge Functions
-- bypasses RLS; authenticated browser users do not.
create policy "deny browser access to evidence-private"
on storage.objects for all to authenticated
using (bucket_id <> 'evidence-private' and false)
with check (false);
create policy "deny browser access to device-media-private"
on storage.objects for all to authenticated
using (bucket_id <> 'device-media-private' and false)
with check (false);
create policy "deny browser access to identity-private"
on storage.objects for all to authenticated
using (bucket_id <> 'identity-private' and false)
with check (false);

-- ----------------------------------------------------------------------------
-- 20260901000400_management_reporting.sql
-- ----------------------------------------------------------------------------
-- Administration, onboarding, central search, export, and trusted Auth-event ingestion.

create or replace function public.api_submit_shop(
  p_shop_name text,
  p_commercial_name text default null,
  p_business_phone text default null,
  p_address_text text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_shop_id uuid := extensions.gen_random_uuid();
  v_status public.account_status;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  select account_status into v_status from public.users where id = auth.uid();
  if not found or v_status in ('suspended', 'inactive') then
    raise exception 'ACCOUNT_NOT_ELIGIBLE' using errcode = '42501';
  end if;
  if nullif(btrim(p_shop_name), '') is null then
    raise exception 'SHOP_NAME_REQUIRED' using errcode = '22023';
  end if;

  insert into public.shops (id, shop_name, commercial_name, owner_user_id, business_phone, address_text, status, verification_status)
  values (
    v_shop_id, left(btrim(p_shop_name), 180), nullif(left(btrim(p_commercial_name), 180), ''), auth.uid(),
    nullif(left(btrim(p_business_phone), 40), ''), nullif(left(btrim(p_address_text), 1000), ''), 'pending', 'pending'
  );
  insert into public.shop_users (shop_id, user_id, title, is_active, added_by)
  values (v_shop_id, auth.uid(), 'مالك المحل', true, auth.uid());
  perform private.append_audit('submit_shop', 'shop', v_shop_id, null, jsonb_build_object('shop_name', left(btrim(p_shop_name), 180)), 'success');

  insert into public.notifications (recipient_id, severity, notification_type, title, body, entity_type, entity_id)
  select distinct ur.user_id, 'important'::public.notification_severity, 'shop_submitted', 'طلب اعتماد محل جديد', 'هناك طلب محل جديد بانتظار المراجعة.', 'shop', v_shop_id
  from public.user_roles ur join public.roles r on r.id = ur.role_id
  where r.key = 'system_admin';

  return jsonb_build_object('shop_id', v_shop_id, 'status', 'pending');
end;
$$;

create or replace function public.api_approve_shop(p_shop_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_shop public.shops%rowtype;
begin
  perform private.require_permission('approve_shop', true);
  select * into v_shop from public.shops where id = p_shop_id for update;
  if not found or v_shop.status <> 'pending' then
    raise exception 'SHOP_NOT_PENDING' using errcode = '22023';
  end if;
  update public.shops
     set status = 'approved', verification_status = 'verified', approved_at = clock_timestamp(), approved_by = auth.uid(), updated_at = clock_timestamp()
   where id = p_shop_id;
  perform private.append_audit('approve_shop', 'shop', p_shop_id, jsonb_build_object('status', v_shop.status), jsonb_build_object('status', 'approved'), 'success');
  insert into public.notifications (recipient_id, severity, notification_type, title, body, entity_type, entity_id)
  values (v_shop.owner_user_id, 'important', 'shop_approved', 'تم اعتماد المحل', 'تم اعتماد المحل ويمكن للإدارة إكمال تفعيل الحساب والصلاحيات.', 'shop', p_shop_id);
  return jsonb_build_object('shop_id', p_shop_id, 'status', 'approved');
end;
$$;

create or replace function public.api_suspend_shop(p_shop_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_shop public.shops%rowtype;
begin
  perform private.require_permission('suspend_shop', true);
  if char_length(coalesce(btrim(p_reason), '')) < 5 then
    raise exception 'SUSPENSION_REASON_REQUIRED' using errcode = '22023';
  end if;
  select * into v_shop from public.shops where id = p_shop_id for update;
  if not found or v_shop.status not in ('approved', 'inactive') then
    raise exception 'SHOP_NOT_SUSPENDABLE' using errcode = '22023';
  end if;
  update public.shops
     set status = 'suspended', suspended_at = clock_timestamp(), suspended_by = auth.uid(),
         suspension_reason = left(btrim(p_reason), 1000), updated_at = clock_timestamp()
   where id = p_shop_id;
  perform private.append_audit('suspend_shop', 'shop', p_shop_id, jsonb_build_object('status', v_shop.status), jsonb_build_object('status', 'suspended'), 'success', jsonb_build_object('reason', left(btrim(p_reason), 1000)));
  insert into public.notifications (recipient_id, severity, notification_type, title, body, entity_type, entity_id)
  select su.user_id, 'critical'::public.notification_severity, 'shop_suspended', 'تم إيقاف المحل', 'أوقف المحل ولا يمكن تسجيل عمليات جديدة حتى إشعار آخر.', 'shop', p_shop_id
  from public.shop_users su where su.shop_id = p_shop_id and su.is_active;
  return jsonb_build_object('shop_id', p_shop_id, 'status', 'suspended');
end;
$$;

create or replace function public.api_link_shop_user(
  p_shop_id uuid,
  p_user_id uuid,
  p_title text default null,
  p_as_technician boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_active_account();
  if not (public.has_permission('manage_shops') or public.has_permission('manage_shop_staff')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not public.has_permission('manage_shops') and not public.can_operate_for_shop(p_shop_id) then
    raise exception 'SHOP_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  if not exists (select 1 from public.shops where id = p_shop_id and status = 'approved') then
    raise exception 'SHOP_NOT_OPERATIONAL' using errcode = '22023';
  end if;
  if not exists (select 1 from public.users where id = p_user_id and account_status = 'active') then
    raise exception 'USER_NOT_ACTIVE' using errcode = '22023';
  end if;

  insert into public.shop_users (shop_id, user_id, title, is_active, added_by)
  values (p_shop_id, p_user_id, nullif(left(btrim(p_title), 160), ''), true, auth.uid())
  on conflict (shop_id, user_id) do update
    set is_active = true, removed_at = null, title = excluded.title, added_by = auth.uid(), joined_at = clock_timestamp();

  if p_as_technician then
    insert into public.technicians (user_id, is_active) values (p_user_id, true)
    on conflict (user_id) do update set is_active = true;
  end if;
  perform private.append_audit('link_shop_user', 'shop', p_shop_id, null, jsonb_build_object('user_id', p_user_id, 'as_technician', p_as_technician), 'success');
  return jsonb_build_object('shop_id', p_shop_id, 'user_id', p_user_id, 'linked', true);
end;
$$;

create or replace function public.api_set_user_roles(p_user_id uuid, p_role_keys text[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old_roles text[];
  v_unknown integer;
begin
  perform private.require_permission('manage_permissions', true);
  if p_user_id = auth.uid() then
    raise exception 'SELF_ROLE_CHANGE_FORBIDDEN' using errcode = '42501';
  end if;
  if not exists (select 1 from public.users where id = p_user_id) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if cardinality(coalesce(p_role_keys, '{}'::text[])) > 8 then
    raise exception 'TOO_MANY_ROLES' using errcode = '22023';
  end if;
  select count(*) into v_unknown from unnest(coalesce(p_role_keys, '{}'::text[])) k
  where not exists (select 1 from public.roles r where r.key = k);
  if v_unknown > 0 then
    raise exception 'UNKNOWN_ROLE' using errcode = '22023';
  end if;

  select coalesce(array_agg(r.key order by r.key), '{}'::text[]) into v_old_roles
  from public.user_roles ur join public.roles r on r.id = ur.role_id
  where ur.user_id = p_user_id;

  delete from public.user_roles where user_id = p_user_id;
  insert into public.user_roles (user_id, role_id, assigned_by)
  select p_user_id, r.id, auth.uid() from public.roles r where r.key = any(coalesce(p_role_keys, '{}'::text[]));

  perform private.append_audit(
    'change_permission', 'user', p_user_id,
    jsonb_build_object('roles', v_old_roles), jsonb_build_object('roles', coalesce(p_role_keys, '{}'::text[])),
    'success'
  );
  insert into public.notifications (recipient_id, severity, notification_type, title, body, entity_type, entity_id)
  values (p_user_id, 'important', 'roles_changed', 'تم تغيير صلاحيات الحساب', 'تم تعديل الأدوار الممنوحة لحسابك.', 'user', p_user_id);
  return jsonb_build_object('user_id', p_user_id, 'roles', coalesce(p_role_keys, '{}'::text[]));
end;
$$;

create or replace function public.api_update_user_status(
  p_user_id uuid,
  p_status public.account_status,
  p_reason text default null,
  p_mfa_required boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_user public.users%rowtype;
begin
  perform private.require_permission('manage_users', true);
  if p_user_id = auth.uid() and p_status <> 'active' then
    raise exception 'SELF_SUSPENSION_FORBIDDEN' using errcode = '42501';
  end if;
  if p_status = 'suspended' and char_length(coalesce(btrim(p_reason), '')) < 5 then
    raise exception 'SUSPENSION_REASON_REQUIRED' using errcode = '22023';
  end if;
  select * into v_user from public.users where id = p_user_id for update;
  if not found then raise exception 'USER_NOT_FOUND' using errcode = 'P0002'; end if;
  update public.users set
    account_status = p_status,
    suspended_at = case when p_status = 'suspended' then clock_timestamp() else null end,
    suspension_reason = case when p_status = 'suspended' then left(btrim(p_reason), 1000) else null end,
    mfa_required = coalesce(p_mfa_required, mfa_required),
    updated_at = clock_timestamp()
  where id = p_user_id;
  perform private.append_audit(
    case when p_status = 'suspended' then 'suspend_user' else 'update_user_status' end,
    'user', p_user_id, jsonb_build_object('status', v_user.account_status), jsonb_build_object('status', p_status), 'success'
  );
  return jsonb_build_object('user_id', p_user_id, 'status', p_status);
end;
$$;

create or replace function public.api_get_shops(p_status public.shop_status default null, p_limit integer default 50, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
begin
  perform private.require_active_account();
  if not (public.has_permission('manage_shops') or public.has_permission('manage_shop_staff')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id, 'shop_name', s.shop_name, 'commercial_name', s.commercial_name,
      'status', s.status, 'verification_status', s.verification_status,
      'created_at', s.created_at, 'approved_at', s.approved_at, 'suspension_reason', s.suspension_reason
    ) order by s.created_at desc)
    from (
      select * from public.shops s
      where (p_status is null or s.status = p_status)
        and (public.has_permission('manage_shops') or public.can_access_shop(s.id))
      order by s.created_at desc limit v_limit offset greatest(0, coalesce(p_offset, 0))
    ) s
  ), '[]'::jsonb);
end;
$$;

-- Central search intentionally excludes plaintext customer identity. Name/phone search is a separate
-- Edge Function that converts the input to a keyed blind-index hash and logs a sensitive-data access reason.
create or replace function public.api_search_records(
  p_mode text,
  p_query text,
  p_limit integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_mode text := lower(btrim(p_mode));
  v_query text := btrim(p_query);
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 100));
begin
  perform private.require_active_account();
  if char_length(v_query) < 2 then
    raise exception 'SEARCH_QUERY_TOO_SHORT' using errcode = '22023';
  end if;

  if v_mode = 'imei' then
    return public.api_check_imei(v_query);
  elsif v_mode = 'report' then
    if not (public.has_permission('view_all_reports') or public.has_permission('update_follow_up')) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
    return coalesce((
      select jsonb_agg(jsonb_build_object('id', sr.id, 'report_number', sr.report_number, 'status', sr.status, 'priority', sr.priority, 'created_at', sr.created_at))
      from (
        select * from public.stolen_reports
        where report_number ilike '%' || left(v_query, 80) || '%' and public.can_access_report(id)
        order by created_at desc limit v_limit
      ) sr
    ), '[]'::jsonb);
  elsif v_mode = 'operation' then
    if not public.has_permission('view_device') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
    return jsonb_build_object(
      'repairs', coalesce((
        select jsonb_agg(jsonb_build_object('id', rr.id, 'operation_number', rr.operation_number, 'device_id', rr.device_id, 'created_at', rr.created_at))
        from (select * from public.repair_records where operation_number ilike '%' || left(v_query, 80) || '%' and public.can_access_device(device_id) order by created_at desc limit v_limit) rr
      ), '[]'::jsonb),
      'formats', coalesce((
        select jsonb_agg(jsonb_build_object('id', fr.id, 'operation_number', fr.operation_number, 'device_id', fr.device_id, 'created_at', fr.created_at))
        from (select * from public.format_records where operation_number ilike '%' || left(v_query, 80) || '%' and public.can_access_device(device_id) order by created_at desc limit v_limit) fr
      ), '[]'::jsonb)
    );
  elsif v_mode = 'shop' then
    if not (public.has_permission('manage_shops') or public.has_permission('manage_shop_staff')) then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
    return coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'shop_name', s.shop_name, 'status', s.status))
      from (select * from public.shops where shop_name ilike '%' || left(v_query, 80) || '%' and public.can_access_shop(id) order by shop_name limit v_limit) s
    ), '[]'::jsonb);
  else
    raise exception 'UNSUPPORTED_SEARCH_MODE' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.api_export_report(
  p_kind text,
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_kind text := lower(btrim(p_kind));
  v_from timestamptz := coalesce(p_from, date_trunc('month', clock_timestamp()));
  v_to timestamptz := coalesce(p_to, clock_timestamp());
  v_rows jsonb;
begin
  perform private.require_permission('generate_reports', true);
  if v_from > v_to then raise exception 'INVALID_DATE_RANGE' using errcode = '22023'; end if;

  if v_kind = 'repairs' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'operation_number', rr.operation_number, 'imei_last4', private.safe_imei_last4(rr.imei_snapshot),
      'operation_type', rr.operation_type, 'result', rr.result, 'created_at', rr.created_at
    ) order by rr.created_at desc), '[]'::jsonb) into v_rows
    from public.repair_records rr
    where rr.created_at between v_from and v_to and public.can_access_device(rr.device_id);
  elsif v_kind = 'formats' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'operation_number', fr.operation_number, 'imei_last4', private.safe_imei_last4(fr.imei_snapshot),
      'format_type', fr.format_type, 'result', fr.result, 'created_at', fr.created_at
    ) order by fr.created_at desc), '[]'::jsonb) into v_rows
    from public.format_records fr
    where fr.created_at between v_from and v_to and public.can_access_device(fr.device_id);
  elsif v_kind = 'reports' then
    if not public.has_permission('view_all_reports') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'report_number', sr.report_number, 'imei_last4', private.safe_imei_last4(sr.imei_snapshot),
      'status', sr.status, 'priority', sr.priority, 'created_at', sr.created_at
    ) order by sr.created_at desc), '[]'::jsonb) into v_rows
    from public.stolen_reports sr
    where sr.created_at between v_from and v_to and public.can_access_report(sr.id);
  elsif v_kind = 'sales' then
    if not public.has_permission('view_sales') then raise exception 'FORBIDDEN' using errcode = '42501'; end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'sale_number', s.sale_number, 'shop_id', s.shop_id, 'sale_date', s.sale_date,
      'imei_last4', private.safe_imei_last4(si.imei_snapshot), 'unit_price', si.unit_price
    ) order by s.sale_date desc), '[]'::jsonb) into v_rows
    from public.sales s join public.sale_items si on si.sale_id = s.id
    where s.sale_date between v_from and v_to
      and (public.has_permission('view_all_devices') or exists (select 1 from public.shop_users su where su.shop_id = s.shop_id and su.user_id = auth.uid() and su.is_active));
  else
    raise exception 'UNSUPPORTED_REPORT_KIND' using errcode = '22023';
  end if;

  perform private.append_audit('export_report', 'report_export', null, null, null, 'success', jsonb_build_object('kind', v_kind, 'from', v_from, 'to', v_to));
  return jsonb_build_object('kind', v_kind, 'from', v_from, 'to', v_to, 'rows', v_rows);
end;
$$;

-- Only a server-held service_role JWT can use this function. The Edge Function validates its separate
-- hook secret and maps Supabase Auth events to this narrow, auditable allow-list.
create or replace function public.api_ingest_auth_event(
  p_actor_id uuid,
  p_action text,
  p_result text,
  p_metadata jsonb default '{}'::jsonb,
  p_ip_address inet default null,
  p_device_information text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_action text := lower(btrim(p_action));
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if v_action not in ('login', 'logout', 'failed_login', 'mfa_event', 'password_reset', 'suspicious_login')
    or p_result not in ('success', 'failure', 'denied') then
    raise exception 'INVALID_AUTH_EVENT' using errcode = '22023';
  end if;
  if p_result = 'failure' or v_action = 'suspicious_login' then
    perform private.raise_security_event(v_action, case when p_result = 'failure' then 'warning'::public.notification_severity else 'important'::public.notification_severity end, p_metadata, p_actor_id, p_ip_address, p_device_information);
  end if;
  return private.append_audit(v_action, 'auth_session', p_actor_id, null, null, p_result, p_metadata, p_ip_address, p_device_information, p_actor_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- 20260901000500_query_and_follow_up_api.sql
-- ----------------------------------------------------------------------------
-- Read models and the constrained follow-up/sensitive-search APIs used by the application.

create or replace function public.api_add_report_follow_up(
  p_report_id uuid,
  p_note text,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid := extensions.gen_random_uuid();
  v_report public.stolen_reports%rowtype;
begin
  perform private.require_permission('update_follow_up', true);
  if not public.can_access_report(p_report_id) then
    raise exception 'REPORT_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  if char_length(coalesce(btrim(p_note), '')) < 5 then
    raise exception 'FOLLOW_UP_NOTE_REQUIRED' using errcode = '22023';
  end if;
  select * into v_report from public.stolen_reports where id = p_report_id;
  if not found or v_report.status in ('closed', 'rejected', 'cancelled') then
    raise exception 'REPORT_NOT_OPEN' using errcode = '22023';
  end if;
  if p_location_id is not null and not exists (select 1 from public.locations where id = p_location_id) then
    raise exception 'LOCATION_NOT_FOUND' using errcode = 'P0002';
  end if;

  insert into public.report_follow_ups (id, report_id, note, location_id, created_by)
  values (v_id, p_report_id, left(btrim(p_note), 3000), p_location_id, auth.uid());
  perform private.append_device_event(
    v_report.device_id, 'report_follow_up_added', 'report_follow_up', v_id, v_report.report_number,
    null, v_report.agency_id, left(btrim(p_note), 3000), '{}'::jsonb
  );
  perform private.append_audit('add_follow_up', 'stolen_report', p_report_id, null, null, 'success', jsonb_build_object('follow_up_id', v_id));
  return jsonb_build_object('follow_up_id', v_id, 'report_id', p_report_id);
end;
$$;

create or replace function public.api_create_location(
  p_label text,
  p_address_text text default null,
  p_latitude numeric default null,
  p_longitude numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid := extensions.gen_random_uuid();
begin
  perform private.require_active_account();
  if not (public.has_permission('create_stolen_report') or public.has_permission('update_follow_up') or public.has_permission('manage_shops')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if nullif(btrim(p_label), '') is null
    or ((p_latitude is null) <> (p_longitude is null))
    or (p_latitude is not null and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180)) then
    raise exception 'INVALID_LOCATION' using errcode = '22023';
  end if;
  insert into public.locations (id, label, address_text, latitude, longitude, created_by)
  values (v_id, left(btrim(p_label), 180), nullif(left(btrim(p_address_text), 1000), ''), p_latitude, p_longitude, auth.uid());
  return v_id;
end;
$$;

create or replace function public.api_get_devices(
  p_status public.device_status default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit, 40), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  perform private.require_permission('view_device');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id, 'brand', d.brand, 'model', d.model, 'color', d.color, 'status', d.status,
      'serial_number', d.serial_number, 'created_at', d.created_at,
      'imeis', (select jsonb_agg(jsonb_build_object('slot', di.slot, 'imei', di.imei) order by di.slot) from public.device_imeis di where di.device_id = d.id)
    ) order by d.created_at desc)
    from (
      select * from public.devices d
      where public.can_access_device(d.id)
        and (p_status is null or d.status = p_status)
        and (p_from is null or d.created_at >= p_from)
        and (p_to is null or d.created_at <= p_to)
      order by d.created_at desc
      limit v_limit offset v_offset
    ) d
  ), '[]'::jsonb);
end;
$$;

-- The incoming hash is a 64-character keyed HMAC generated inside an Edge Function. This function
-- never accepts plaintext search terms and returns references only, not the matching personal value.
create or replace function public.api_search_customer_by_lookup_hash(
  p_lookup_type text,
  p_lookup_hash text,
  p_purpose text,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type text := lower(btrim(p_lookup_type));
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  v_record record;
  v_result jsonb := '[]'::jsonb;
begin
  perform private.require_permission('view_sensitive_data', true);
  if v_type not in ('phone', 'full_name', 'national_id')
    or p_lookup_hash !~ '^[a-f0-9]{64}$'
    or char_length(coalesce(btrim(p_purpose), '')) < 5 then
    raise exception 'INVALID_SENSITIVE_SEARCH' using errcode = '22023';
  end if;

  for v_record in
    select c.id, c.reference_code
    from public.customers c
    join public.customer_sensitive_data csd on csd.customer_id = c.id
    where public.can_access_customer(c.id)
      and case v_type
        when 'phone' then csd.phone_lookup_hash = p_lookup_hash
        when 'full_name' then csd.full_name_lookup_hash = p_lookup_hash
        when 'national_id' then csd.national_id_lookup_hash = p_lookup_hash
      end
    order by c.created_at desc
    limit v_limit
  loop
    perform private.log_sensitive_access('customer_lookup', v_record.id, left(btrim(p_purpose), 500), 'view_sensitive_data');
    v_result := v_result || jsonb_build_array(jsonb_build_object('customer_id', v_record.id, 'reference_code', v_record.reference_code));
  end loop;

  perform private.append_audit('search_sensitive_data', 'customer', null, null, null, 'success', jsonb_build_object('lookup_type', v_type, 'result_count', jsonb_array_length(v_result)));
  return v_result;
end;
$$;

create or replace function public.api_get_users(p_limit integer default 50, p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
begin
  perform private.require_permission('manage_users', true);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', q.id, 'display_name', q.display_name, 'account_status', q.account_status,
      'mfa_required', q.mfa_required, 'agency_id', q.agency_id, 'created_at', q.created_at,
      'roles', q.roles
    ) order by q.created_at desc)
    from (
      select u.*, coalesce((
        select jsonb_agg(r.key order by r.key)
        from public.user_roles ur join public.roles r on r.id = ur.role_id where ur.user_id = u.id
      ), '[]'::jsonb) as roles
      from public.users u
      order by u.created_at desc limit v_limit offset greatest(0, coalesce(p_offset, 0))
    ) q
  ), '[]'::jsonb);
end;
$$;

create or replace function public.api_get_audit_logs(
  p_limit integer default 50,
  p_before timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
  perform private.require_permission('view_audit_logs', true);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', q.id, 'sequence_number', q.sequence_number, 'actor_id', q.actor_id, 'actor_roles', q.actor_roles,
      'action', q.action, 'entity_type', q.entity_type, 'entity_id', q.entity_id, 'result', q.result,
      'metadata', q.metadata, 'occurred_at', q.occurred_at, 'entry_hash', q.entry_hash, 'previous_hash', q.previous_hash
    ) order by q.sequence_number desc)
    from (
      select * from public.audit_logs al
      where p_before is null or al.occurred_at < p_before
      order by al.sequence_number desc limit v_limit
    ) q
  ), '[]'::jsonb);
end;
$$;

create or replace function public.api_get_security_events(
  p_limit integer default 50,
  p_unresolved_only boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
  perform private.require_permission('view_security_events', true);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', q.id, 'event_type', q.event_type, 'severity', q.severity, 'metadata', q.metadata,
      'created_at', q.created_at, 'resolved_at', q.resolved_at, 'resolved_by', q.resolved_by
    ) order by q.created_at desc)
    from (
      select * from public.security_events se
      where not p_unresolved_only or se.resolved_at is null
      order by se.created_at desc limit v_limit
    ) q
  ), '[]'::jsonb);
end;
$$;

create or replace function public.api_resolve_security_event(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_permission('view_security_events', true);
  perform set_config('app.security_event_resolution', 'on', true);
  update public.security_events
     set resolved_at = coalesce(resolved_at, clock_timestamp()), resolved_by = coalesce(resolved_by, auth.uid())
   where id = p_event_id and resolved_at is null;
  if not found then raise exception 'SECURITY_EVENT_NOT_FOUND_OR_RESOLVED' using errcode = 'P0002'; end if;
  perform private.append_audit('resolve_security_event', 'security_event', p_event_id, null, null, 'success');
end;
$$;

create or replace function public.api_update_system_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_permission('manage_system_settings', true);
  if p_key not in ('security.imei_checks_per_10m', 'security.signed_url_ttl_seconds', 'retention.audit_log_years')
    or jsonb_typeof(p_value) <> 'number' then
    raise exception 'SETTING_NOT_ALLOWED' using errcode = '22023';
  end if;
  if (p_key = 'security.imei_checks_per_10m' and (p_value #>> '{}')::integer not between 1 and 1000)
    or (p_key = 'security.signed_url_ttl_seconds' and (p_value #>> '{}')::integer not between 30 and 300)
    or (p_key = 'retention.audit_log_years' and (p_value #>> '{}')::integer not between 1 and 50) then
    raise exception 'SETTING_VALUE_OUT_OF_RANGE' using errcode = '22023';
  end if;
  update public.system_settings set value = p_value, updated_by = auth.uid(), updated_at = clock_timestamp()
  where key = p_key and not is_sensitive;
  if not found then raise exception 'SETTING_NOT_FOUND' using errcode = 'P0002'; end if;
  perform private.append_audit('update_system_setting', 'system_setting', null, null, null, 'success', jsonb_build_object('key', p_key));
end;
$$;

-- ----------------------------------------------------------------------------
-- 20260901000600_final_privileges.sql
-- ----------------------------------------------------------------------------
-- Final privilege reset runs after every API migration. Do not expose functions to anon/public.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to authenticated;

-- Auth-event ingestion is server-to-server only. It is called by an Edge Function whose hook secret
-- is configured outside source control.
revoke execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) from public, anon, authenticated;
grant execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) to service_role;

revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 20260901000700_atomic_encrypted_workflows.sql
-- ----------------------------------------------------------------------------
-- Atomic wrappers keep encrypted customer creation and its sale/report in one database transaction.

create or replace function public.api_register_sale_with_customer(
  p_shop_id uuid,
  p_imei text,
  p_unit_price numeric,
  p_notes text,
  p_full_name_ciphertext text,
  p_phone_ciphertext text,
  p_national_id_ciphertext text,
  p_address_ciphertext text,
  p_full_name_lookup_hash text,
  p_phone_lookup_hash text,
  p_national_id_lookup_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_customer jsonb;
  v_customer_id uuid;
  v_sale jsonb;
begin
  v_customer := public.api_create_customer(
    p_full_name_ciphertext, p_phone_ciphertext, p_national_id_ciphertext, p_address_ciphertext,
    p_full_name_lookup_hash, p_phone_lookup_hash, p_national_id_lookup_hash
  );
  v_customer_id := (v_customer ->> 'customer_id')::uuid;
  v_sale := public.api_register_sale(p_shop_id, p_imei, v_customer_id, p_unit_price, p_notes);
  return v_sale || jsonb_build_object('customer_id', v_customer_id, 'customer_reference_code', v_customer ->> 'reference_code');
end;
$$;

create or replace function public.api_create_stolen_report_with_reporter(
  p_imei text,
  p_report_type text,
  p_incident_at timestamptz,
  p_description text,
  p_priority public.report_priority,
  p_agency_id uuid,
  p_incident_location_id uuid,
  p_imei2 text,
  p_brand text,
  p_model text,
  p_color text,
  p_full_name_ciphertext text,
  p_phone_ciphertext text,
  p_national_id_ciphertext text,
  p_address_ciphertext text,
  p_full_name_lookup_hash text,
  p_phone_lookup_hash text,
  p_national_id_lookup_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_customer jsonb;
  v_customer_id uuid;
  v_report jsonb;
begin
  v_customer := public.api_create_customer(
    p_full_name_ciphertext, p_phone_ciphertext, p_national_id_ciphertext, p_address_ciphertext,
    p_full_name_lookup_hash, p_phone_lookup_hash, p_national_id_lookup_hash
  );
  v_customer_id := (v_customer ->> 'customer_id')::uuid;
  v_report := public.api_create_stolen_report(
    p_imei, v_customer_id, p_report_type, p_incident_at, p_description, p_priority,
    p_agency_id, p_incident_location_id, p_imei2, p_brand, p_model, p_color
  );
  return v_report || jsonb_build_object('reporter_customer_id', v_customer_id, 'reporter_reference_code', v_customer ->> 'reference_code');
end;
$$;

-- ----------------------------------------------------------------------------
-- 20260901000800_rate_limiting.sql
-- ----------------------------------------------------------------------------
-- Atomic, server-only rate-limit counters. Edge Functions hash actor/IP identifiers before calling this RPC.
create table public.api_rate_limit_windows (
  bucket_hash text not null check (bucket_hash ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (bucket_hash, window_started_at)
);
create index api_rate_limit_cleanup_idx on public.api_rate_limit_windows(window_started_at);
alter table public.api_rate_limit_windows enable row level security;
revoke all on public.api_rate_limit_windows from anon, authenticated;

create or replace function public.api_consume_rate_limit(
  p_bucket_hash text,
  p_window_seconds integer,
  p_max_requests integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_window timestamptz;
  v_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if p_bucket_hash !~ '^[a-f0-9]{64}$' or p_window_seconds not between 10 and 86400 or p_max_requests not between 1 and 10000 then
    raise exception 'INVALID_RATE_LIMIT_ARGUMENT' using errcode = '22023';
  end if;
  v_window := to_timestamp(floor(extract(epoch from clock_timestamp()) / p_window_seconds) * p_window_seconds);
  insert into public.api_rate_limit_windows (bucket_hash, window_started_at, request_count, updated_at)
  values (p_bucket_hash, v_window, 1, clock_timestamp())
  on conflict (bucket_hash, window_started_at) do update
    set request_count = public.api_rate_limit_windows.request_count + 1,
        updated_at = clock_timestamp()
  returning request_count into v_count;

  return jsonb_build_object(
    'allowed', v_count <= p_max_requests,
    'remaining', greatest(0, p_max_requests - v_count),
    'retry_after_seconds', greatest(1, p_window_seconds - mod(extract(epoch from clock_timestamp())::integer, p_window_seconds))
  );
end;
$$;

revoke execute on function public.api_consume_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.api_consume_rate_limit(text, integer, integer) to service_role;

-- ----------------------------------------------------------------------------
-- 20260901000900_lock_function_privileges.sql
-- ----------------------------------------------------------------------------
-- New functions added after the first privilege migration inherit PostgreSQL's PUBLIC EXECUTE default.
-- Reset that default exposure once more, then allow authenticated requests only through checked functions.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) from public, anon, authenticated;
grant execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) to service_role;
revoke execute on function public.api_consume_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.api_consume_rate_limit(text, integer, integer) to service_role;
revoke all on all functions in schema private from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 20260901001000_upload_intent_authorization.sql
-- ----------------------------------------------------------------------------
-- The Edge Function must not use its service key to inspect an arbitrary object path.
-- These narrow functions authorize ownership/scope before it obtains the path needed for hash verification.

create or replace function public.api_get_pending_evidence_upload(p_evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_evidence public.evidence%rowtype;
begin
  perform private.require_permission('upload_evidence', true);
  select * into v_evidence from public.evidence where id = p_evidence_id;
  if not found or v_evidence.status <> 'pending_upload' then
    raise exception 'EVIDENCE_NOT_PENDING' using errcode = 'P0002';
  end if;
  if v_evidence.uploaded_by <> auth.uid() or not public.can_access_report(v_evidence.report_id) then
    raise exception 'EVIDENCE_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  return jsonb_build_object('bucket', 'evidence-private', 'storage_path', v_evidence.storage_path, 'size_bytes', v_evidence.size_bytes, 'content_type', v_evidence.content_type);
end;
$$;

create or replace function public.api_get_pending_device_media_upload(p_media_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_media public.device_media%rowtype;
begin
  perform private.require_active_account();
  select * into v_media from public.device_media where id = p_media_id;
  if not found or v_media.status <> 'pending_upload' then
    raise exception 'MEDIA_NOT_PENDING' using errcode = 'P0002';
  end if;
  if v_media.uploaded_by <> auth.uid() or not public.can_access_device(v_media.device_id) then
    raise exception 'MEDIA_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  return jsonb_build_object('bucket', 'device-media-private', 'storage_path', v_media.storage_path, 'size_bytes', v_media.size_bytes, 'content_type', v_media.content_type);
end;
$$;

revoke execute on function public.api_get_pending_evidence_upload(uuid) from public, anon, authenticated;
revoke execute on function public.api_get_pending_device_media_upload(uuid) from public, anon, authenticated;
grant execute on function public.api_get_pending_evidence_upload(uuid), public.api_get_pending_device_media_upload(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 20260901001100_user_invite_authorization.sql
-- ----------------------------------------------------------------------------
-- Narrow server authorization for Auth Admin invitations. The service role remains inside the Edge Function.
create or replace function public.api_authorize_user_invite()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_permission('manage_users', true);
  return true;
end;
$$;

create or replace function public.api_record_user_invite(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform private.require_permission('manage_users', true);
  if not exists (select 1 from public.users where id = p_user_id) then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform private.append_audit('create_user', 'user', p_user_id, null, jsonb_build_object('invite', true), 'success');
end;
$$;

revoke execute on function public.api_authorize_user_invite(), public.api_record_user_invite(uuid) from public, anon, authenticated;
grant execute on function public.api_authorize_user_invite(), public.api_record_user_invite(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 20260901001200_final_function_privileges.sql
-- ----------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) from public, anon, authenticated;
grant execute on function public.api_ingest_auth_event(uuid, text, text, jsonb, inet, text) to service_role;
revoke execute on function public.api_consume_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.api_consume_rate_limit(text, integer, integer) to service_role;
revoke all on all functions in schema private from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 20260901001300_identity_document_workflow.sql
-- ----------------------------------------------------------------------------
-- Identity document workflow. Documents are separate private objects so shop staff may submit an
-- approved policy-required document but cannot read it back without view_identity.
create table public.customer_identity_documents (
  id uuid primary key default extensions.gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  storage_path text not null unique check (storage_path !~ '^/' and storage_path !~ '\.\.'),
  original_name text not null check (char_length(original_name) between 1 and 255),
  content_type text not null check (content_type in ('image/jpeg', 'image/png', 'application/pdf')),
  size_bytes integer not null check (size_bytes > 0 and size_bytes <= 10485760),
  sha256 text,
  status public.evidence_status not null default 'pending_upload',
  uploaded_by uuid not null references public.users(id) on delete restrict,
  uploaded_at timestamptz,
  created_at timestamptz not null default now()
);
create index customer_identity_documents_customer_idx on public.customer_identity_documents(customer_id, created_at desc);
alter table public.customer_identity_documents enable row level security;
revoke all on public.customer_identity_documents from anon, authenticated;

create or replace function private.guard_identity_document_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'IMMUTABLE_IDENTITY_DOCUMENT' using errcode = '42501';
  end if;
  if current_setting('app.identity_upload_completion', true) <> 'on'
    or new.id is distinct from old.id
    or new.customer_id is distinct from old.customer_id
    or new.storage_path is distinct from old.storage_path
    or new.original_name is distinct from old.original_name
    or new.content_type is distinct from old.content_type
    or new.size_bytes is distinct from old.size_bytes
    or new.uploaded_by is distinct from old.uploaded_by
    or new.created_at is distinct from old.created_at then
    raise exception 'DIRECT_IDENTITY_DOCUMENT_UPDATE_FORBIDDEN' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger identity_document_guard_update
before update or delete on public.customer_identity_documents
for each row execute procedure private.guard_identity_document_update();
create trigger immutable_customer_sensitive_data
before update or delete on public.customer_sensitive_data
for each row execute procedure private.reject_mutation();

create policy identity_document_metadata_read_identity_permission on public.customer_identity_documents
for select to authenticated using (
  public.has_permission('view_identity') and public.can_access_customer(customer_id)
);
grant select on public.customer_identity_documents to authenticated;

create or replace function public.api_create_identity_document_upload_intent(
  p_customer_id uuid,
  p_original_name text,
  p_content_type text,
  p_size_bytes integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid := extensions.gen_random_uuid();
  v_safe_name text;
  v_path text;
begin
  perform private.require_active_account();
  if not (public.has_permission('create_sale') or public.has_permission('create_stolen_report')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not public.can_access_customer(p_customer_id) then
    raise exception 'CUSTOMER_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  if p_content_type not in ('image/jpeg', 'image/png', 'application/pdf') or p_size_bytes not between 1 and 10485760 then
    raise exception 'INVALID_IDENTITY_DOCUMENT_METADATA' using errcode = '22023';
  end if;
  v_safe_name := nullif(regexp_replace(left(coalesce(p_original_name, ''), 255), '[^A-Za-z0-9._-]', '_', 'g'), '');
  v_safe_name := coalesce(v_safe_name, 'identity-document.bin');
  v_path := 'customers/' || p_customer_id::text || '/' || v_id::text || '-' || v_safe_name;
  insert into public.customer_identity_documents (id, customer_id, storage_path, original_name, content_type, size_bytes, uploaded_by)
  values (v_id, p_customer_id, v_path, v_safe_name, p_content_type, p_size_bytes, auth.uid());
  perform private.append_audit('create_identity_document_upload', 'customer_identity_document', v_id, null, null, 'success', jsonb_build_object('customer_id', p_customer_id));
  return jsonb_build_object('identity_document_id', v_id, 'bucket', 'identity-private', 'storage_path', v_path);
end;
$$;

create or replace function public.api_get_pending_identity_document_upload(p_identity_document_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_document public.customer_identity_documents%rowtype;
begin
  perform private.require_active_account();
  select * into v_document from public.customer_identity_documents where id = p_identity_document_id;
  if not found or v_document.status <> 'pending_upload' then raise exception 'IDENTITY_DOCUMENT_NOT_PENDING' using errcode = 'P0002'; end if;
  if v_document.uploaded_by <> auth.uid() or not public.can_access_customer(v_document.customer_id) then raise exception 'CUSTOMER_OUT_OF_SCOPE' using errcode = '42501'; end if;
  return jsonb_build_object('bucket', 'identity-private', 'storage_path', v_document.storage_path, 'size_bytes', v_document.size_bytes, 'content_type', v_document.content_type);
end;
$$;

create or replace function public.api_complete_identity_document_upload(p_identity_document_id uuid, p_sha256 text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_document public.customer_identity_documents%rowtype;
begin
  perform private.require_active_account();
  select * into v_document from public.customer_identity_documents where id = p_identity_document_id for update;
  if not found or v_document.status <> 'pending_upload' then raise exception 'IDENTITY_DOCUMENT_NOT_PENDING' using errcode = 'P0002'; end if;
  if v_document.uploaded_by <> auth.uid() or not public.can_access_customer(v_document.customer_id) then raise exception 'CUSTOMER_OUT_OF_SCOPE' using errcode = '42501'; end if;
  if p_sha256 !~ '^[a-fA-F0-9]{64}$' then raise exception 'INVALID_FILE_HASH' using errcode = '22023'; end if;
  perform set_config('app.identity_upload_completion', 'on', true);
  update public.customer_identity_documents set status = 'uploaded', sha256 = lower(p_sha256), uploaded_at = clock_timestamp() where id = p_identity_document_id;
  perform private.append_audit('upload_identity_document', 'customer_identity_document', p_identity_document_id, jsonb_build_object('status', 'pending_upload'), jsonb_build_object('status', 'uploaded'), 'success', jsonb_build_object('customer_id', v_document.customer_id));
  return jsonb_build_object('identity_document_id', p_identity_document_id, 'status', 'uploaded');
end;
$$;

create or replace function public.api_authorize_identity_document_view(p_identity_document_id uuid, p_purpose text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_document public.customer_identity_documents%rowtype;
  v_ttl integer;
begin
  perform private.require_permission('view_identity', true);
  if char_length(coalesce(btrim(p_purpose), '')) < 5 then raise exception 'ACCESS_PURPOSE_REQUIRED' using errcode = '22023'; end if;
  select * into v_document from public.customer_identity_documents where id = p_identity_document_id;
  if not found or v_document.status <> 'uploaded' then raise exception 'IDENTITY_DOCUMENT_NOT_AVAILABLE' using errcode = 'P0002'; end if;
  if not public.can_access_customer(v_document.customer_id) then raise exception 'CUSTOMER_OUT_OF_SCOPE' using errcode = '42501'; end if;
  perform private.log_sensitive_access('identity_document', v_document.customer_id, left(btrim(p_purpose), 500), 'view_identity');
  v_ttl := least(greatest(private.setting_integer('security.signed_url_ttl_seconds', 60), 30), 300);
  return jsonb_build_object('bucket', 'identity-private', 'storage_path', v_document.storage_path, 'ttl_seconds', v_ttl);
end;
$$;

revoke execute on function public.api_create_identity_document_upload_intent(uuid, text, text, integer), public.api_get_pending_identity_document_upload(uuid), public.api_complete_identity_document_upload(uuid, text), public.api_authorize_identity_document_view(uuid, text) from public, anon, authenticated;
grant execute on function public.api_create_identity_document_upload_intent(uuid, text, text, integer), public.api_get_pending_identity_document_upload(uuid), public.api_complete_identity_document_upload(uuid, text), public.api_authorize_identity_document_view(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 20260901001400_denied_request_telemetry.sql
-- ----------------------------------------------------------------------------
-- Server-only telemetry for denied authenticated requests. Edge Functions pass only a normalized reason,
-- never request bodies or raw error stacks.
create or replace function public.api_record_denied_request(
  p_actor_id uuid,
  p_action text,
  p_reason_code text,
  p_ip_address inet default null,
  p_device_information text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_event_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if p_action !~ '^[a-z][a-z0-9_-]{1,98}$' or p_reason_code !~ '^[A-Z0-9_]{2,100}$' then
    raise exception 'INVALID_DENIED_REQUEST_TELEMETRY' using errcode = '22023';
  end if;
  v_event_id := private.raise_security_event(
    'unauthorized_api_request', 'warning', jsonb_build_object('action', p_action, 'reason', p_reason_code),
    p_actor_id, p_ip_address, p_device_information
  );
  perform private.append_audit(
    'unauthorized_api_request', 'api_request', null, null, null, 'denied',
    jsonb_build_object('action', p_action, 'reason', p_reason_code), p_ip_address, p_device_information, p_actor_id
  );
  return v_event_id;
end;
$$;
revoke execute on function public.api_record_denied_request(uuid, text, text, inet, text) from public, anon, authenticated;
grant execute on function public.api_record_denied_request(uuid, text, text, inet, text) to service_role;

-- ----------------------------------------------------------------------------
-- 20260901001500_case_assignee_directory.sql
-- ----------------------------------------------------------------------------
-- Minimal, case-scoped directory for authorized assignment. It never exposes contact or identity data.
create or replace function public.api_get_case_assignees(p_report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_agency_id uuid;
begin
  perform private.require_permission('assign_case', true);
  if not public.can_access_report(p_report_id) then
    raise exception 'REPORT_OUT_OF_SCOPE' using errcode = '42501';
  end if;
  select agency_id into v_agency_id from public.stolen_reports where id = p_report_id;
  if not found then
    raise exception 'REPORT_NOT_FOUND' using errcode = 'P0002';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object('id', q.id, 'display_name', q.display_name, 'role', q.role) order by q.display_name, q.role)
    from (
      select distinct u.id, u.display_name, 'officer'::text as role
      from public.users u
      join public.user_roles ur on ur.user_id = u.id
      join public.roles r on r.id = ur.role_id
      where u.account_status = 'active'
        and r.key in ('authorized_officer', 'investigation_officer', 'system_admin')
        and (r.key = 'system_admin' or u.agency_id = v_agency_id)
      union
      select distinct u.id, u.display_name, 'delegate'::text as role
      from public.users u
      join public.delegates d on d.user_id = u.id
      where u.account_status = 'active' and d.is_active and d.agency_id = v_agency_id
    ) q
  ), '[]'::jsonb);
end;
$$;
revoke execute on function public.api_get_case_assignees(uuid) from public, anon, authenticated;
grant execute on function public.api_get_case_assignees(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 20260901001600_schema_function_hardening.sql
-- ----------------------------------------------------------------------------
-- ============================================================
-- Hardening: leftover schema/function privileges (additive, safe)
-- ============================================================
-- Addressed here without touching previously shipped migrations:
--   1. API-exposed roles must not create objects in the public schema.
--      (The earlier blanket revokes removed TABLE grants, but the schema-level
--      CREATE privilege inherited from the PUBLIC pseudo-role was not removed.)
--   2. Objects created by future migrations must not silently inherit
--      PUBLIC EXECUTE or anon/authenticated write grants.
--   3. The Auth profile trigger runs as its owner; a later blanket
--      "grant execute on all functions in schema public to authenticated"
--      had re-exposed direct EXECUTE on it. Re-revoke it as a final cleanup.
--
-- These are privilege revocations only: no schema/object changes, no data
-- changes, and they are idempotent. Existing explicit GRANTs (e.g. SELECT
-- policies, api_* EXECUTE to authenticated) are unaffected.

-- 1) Remove object-creation ability from the API/global roles in `public`.
revoke create on schema public from public, anon, authenticated;

-- 2) Future objects created by the migration role (postgres) must not inherit
--    PUBLIC EXECUTE on functions nor write grants on tables by default.
alter default privileges for role postgres in schema public
  revoke execute on functions from public;
alter default privileges for role postgres in schema public
  revoke insert, update, delete on tables from anon, authenticated;

-- 3) The Auth profile trigger function is owner-only; no caller needs direct EXECUTE.
revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;

commit;
