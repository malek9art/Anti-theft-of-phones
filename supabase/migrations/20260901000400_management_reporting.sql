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
