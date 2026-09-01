-- Row Level Security is a second enforcement layer. The browser has no write policy for
-- critical records; it must use the audited api_* functions through Edge Functions.

alter table public.agencies enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.users enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.locations enable row level security;
alter table public.shops enable row level security;
alter table public.shop_users enable row level security;
alter table public.technicians enable row level security;
alter table public.delegates enable row level security;
alter table public.device_status_transitions enable row level security;
alter table public.devices enable row level security;
alter table public.device_imeis enable row level security;
alter table public.device_media enable row level security;
alter table public.customers enable row level security;
alter table public.customer_sensitive_data enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.repair_records enable row level security;
alter table public.format_records enable row level security;
alter table public.stolen_reports enable row level security;
alter table public.report_status_history enable row level security;
alter table public.report_follow_ups enable row level security;
alter table public.report_status_transitions enable row level security;
alter table public.evidence enable row level security;
alter table public.evidence_access_logs enable row level security;
alter table public.audit_logs enable row level security;
alter table public.sensitive_data_access_logs enable row level security;
alter table public.security_events enable row level security;
alter table public.notifications enable row level security;
alter table public.device_events enable row level security;
alter table public.record_corrections enable row level security;
alter table public.system_settings enable row level security;

-- Directory/RBAC reads are deliberately narrow.
create policy agencies_read_authorized on public.agencies
for select to authenticated using (public.is_active_account());
create policy roles_read_active on public.roles
for select to authenticated using (public.is_active_account());
create policy permissions_read_active on public.permissions
for select to authenticated using (public.is_active_account());
create policy users_read_self_or_admin on public.users
for select to authenticated using (id = auth.uid() or public.has_permission('manage_users'));
create policy role_permissions_read_admin on public.role_permissions
for select to authenticated using (public.has_permission('manage_permissions'));
create policy user_roles_read_self_or_admin on public.user_roles
for select to authenticated using (user_id = auth.uid() or public.has_permission('manage_users'));

create policy locations_read_scoped on public.locations
for select to authenticated using (
  public.has_permission('view_all_reports') or public.has_permission('manage_shops')
);
create policy shops_read_scoped on public.shops
for select to authenticated using (public.can_access_shop(id) or public.has_permission('manage_shops'));
create policy shop_users_read_scoped on public.shop_users
for select to authenticated using (
  user_id = auth.uid() or public.has_permission('manage_shops') or public.can_access_shop(shop_id)
);
create policy technicians_read_scoped on public.technicians
for select to authenticated using (user_id = auth.uid() or public.has_permission('manage_shops'));
create policy delegates_read_self_or_admin on public.delegates
for select to authenticated using (user_id = auth.uid() or public.has_permission('manage_users'));
create policy device_transitions_read_admin on public.device_status_transitions
for select to authenticated using (public.has_permission('manage_system_settings'));
create policy report_transitions_read_admin on public.report_status_transitions
for select to authenticated using (public.has_permission('manage_system_settings'));

create policy devices_read_scoped on public.devices
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(id));
create policy device_imeis_read_scoped on public.device_imeis
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));
create policy device_media_read_scoped on public.device_media
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));

create policy customers_read_reference_scoped on public.customers
for select to authenticated using (public.has_permission('view_customer') and public.can_access_customer(id));
-- Intentionally no policy for customer_sensitive_data: ciphertext is only read by a service-role
-- Edge Function after api_authorize_sensitive_customer_access() has logged the purpose.

create policy sales_read_scoped on public.sales
for select to authenticated using (
  public.has_permission('view_sales') and (
    public.has_permission('view_all_devices') or exists (
      select 1 from public.shop_users su
      where su.shop_id = sales.shop_id and su.user_id = auth.uid() and su.is_active
    )
  )
);
create policy sale_items_read_scoped on public.sale_items
for select to authenticated using (public.has_permission('view_sales') and public.can_access_device(device_id));
create policy repairs_read_scoped on public.repair_records
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));
create policy formats_read_scoped on public.format_records
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));

create policy reports_read_scoped on public.stolen_reports
for select to authenticated using (public.can_access_report(id));
create policy report_history_read_scoped on public.report_status_history
for select to authenticated using (public.can_access_report(report_id));
create policy report_follow_ups_read_scoped on public.report_follow_ups
for select to authenticated using (public.can_access_report(report_id));
create policy evidence_read_scoped on public.evidence
for select to authenticated using (public.has_permission('view_evidence') and public.can_access_report(report_id));
create policy evidence_access_logs_read_audit on public.evidence_access_logs
for select to authenticated using (public.has_permission('view_audit_logs'));

create policy audit_logs_read_audit on public.audit_logs
for select to authenticated using (public.has_permission('view_audit_logs'));
create policy sensitive_access_logs_read_audit on public.sensitive_data_access_logs
for select to authenticated using (public.has_permission('view_audit_logs'));
create policy security_events_read_authorized on public.security_events
for select to authenticated using (public.has_permission('view_security_events'));
create policy notifications_read_own on public.notifications
for select to authenticated using (recipient_id = auth.uid());
create policy device_events_read_scoped on public.device_events
for select to authenticated using (public.has_permission('view_device') and public.can_access_device(device_id));
create policy corrections_read_audit on public.record_corrections
for select to authenticated using (public.has_permission('view_audit_logs'));
create policy settings_read_non_sensitive_admin on public.system_settings
for select to authenticated using (public.has_permission('manage_system_settings') and not is_sensitive);

-- No direct INSERT/UPDATE/DELETE policy has been added to critical entities.
-- Explicit SELECT grants keep PostgREST from exposing unapproved write paths.
revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.agencies, public.roles, public.permissions, public.users, public.role_permissions,
  public.user_roles, public.locations, public.shops, public.shop_users, public.technicians, public.delegates,
  public.device_status_transitions, public.report_status_transitions, public.devices, public.device_imeis,
  public.device_media, public.customers, public.sales, public.sale_items, public.repair_records,
  public.format_records, public.stolen_reports, public.report_status_history, public.report_follow_ups, public.evidence,
  public.evidence_access_logs, public.audit_logs, public.sensitive_data_access_logs, public.security_events,
  public.notifications, public.device_events, public.record_corrections, public.system_settings
  to authenticated;

revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.handle_new_auth_user() from public, anon, authenticated;

-- Private storage only. The browser receives scoped signed URLs from an Edge Function after a
-- database authorization + access-log operation. There is no public object URL and no direct policy.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('evidence-private', 'evidence-private', false, 15728640, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('device-media-private', 'device-media-private', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('identity-private', 'identity-private', false, 10485760, array['image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- These explicit deny policies document the invariant. service_role used inside Edge Functions
-- bypasses RLS; authenticated browser users do not.
create policy "deny browser access to evidence-private"
on storage.objects for all to authenticated
using (bucket_id <> 'evidence-private' and false)
with check (false);
create policy "deny browser access to device-media-private"
on storage.objects for all to authenticated
using (bucket_id <> 'device-media-private' and false)
with check (false);
create policy "deny browser access to identity-private"
on storage.objects for all to authenticated
using (bucket_id <> 'identity-private' and false)
with check (false);
