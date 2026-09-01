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
