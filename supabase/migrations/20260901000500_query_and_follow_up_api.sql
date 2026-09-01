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
