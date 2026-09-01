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
  select assigned_id, 'important', 'case_assigned', 'تم تعيين حالة لك', 'تم تحويل حالة تحتاج إلى متابعة.', 'stolen_report', p_report_id
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
    ) order by q.created_at desc), '[]'::jsonb)
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
