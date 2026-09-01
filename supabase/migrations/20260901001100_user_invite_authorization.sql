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
