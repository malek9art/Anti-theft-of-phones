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
