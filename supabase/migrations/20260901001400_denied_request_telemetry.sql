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
