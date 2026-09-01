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
