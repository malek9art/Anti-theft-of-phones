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
  for v_index in reverse 1..15 loop
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
