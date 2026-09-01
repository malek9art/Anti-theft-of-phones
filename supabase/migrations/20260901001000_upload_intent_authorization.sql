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
