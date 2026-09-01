-- End-to-end authorization scenario required by the product brief.
-- Run in a disposable local Supabase database: `supabase test db`.
begin;
select plan(17);

do $scenario$
declare
  v_admin uuid := '10000000-0000-4000-8000-000000000001';
  v_manager uuid := '10000000-0000-4000-8000-000000000002';
  v_technician uuid := '10000000-0000-4000-8000-000000000003';
  v_officer uuid := '10000000-0000-4000-8000-000000000004';
  v_delegate uuid := '10000000-0000-4000-8000-000000000005';
  v_shop uuid;
  v_agency uuid;
  v_device uuid;
  v_customer uuid;
  v_report uuid;
  v_payload jsonb;
  v_check jsonb;
  v_timeline jsonb;
  v_audits jsonb;
  v_envelope text := 'v1.aaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbb';
  v_hash text := repeat('a', 64);
begin
  -- Minimal Auth rows cause the production trigger to create the public profiles.
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    (v_admin, 'authenticated', 'authenticated', 'admin.lifecycle@test.local', '{"provider":"email","providers":["email"]}', '{"display_name":"مدير اختبار"}', now(), now()),
    (v_manager, 'authenticated', 'authenticated', 'manager.lifecycle@test.local', '{"provider":"email","providers":["email"]}', '{"display_name":"مدير محل اختبار"}', now(), now()),
    (v_technician, 'authenticated', 'authenticated', 'technician.lifecycle@test.local', '{"provider":"email","providers":["email"]}', '{"display_name":"فني اختبار"}', now(), now()),
    (v_officer, 'authenticated', 'authenticated', 'officer.lifecycle@test.local', '{"provider":"email","providers":["email"]}', '{"display_name":"موظف مختص اختبار"}', now(), now()),
    (v_delegate, 'authenticated', 'authenticated', 'delegate.lifecycle@test.local', '{"provider":"email","providers":["email"]}', '{"display_name":"مندوب اختبار"}', now(), now());
  update public.users set account_status = 'active' where id in (v_admin, v_manager, v_technician, v_officer, v_delegate);
  insert into public.agencies (name, code) values ('جهة اختبار', 'TEST-AGENCY') returning id into v_agency;
  update public.users set agency_id = v_agency where id in (v_officer, v_delegate);
  insert into public.delegates (user_id, agency_id, professional_reference) values (v_delegate, v_agency, 'DEL-TEST');

  insert into public.user_roles (user_id, role_id)
  select v_admin, id from public.roles where key = 'system_admin';
  insert into public.user_roles (user_id, role_id)
  select v_manager, id from public.roles where key = 'shop_manager';
  insert into public.user_roles (user_id, role_id)
  select v_technician, id from public.roles where key = 'technician';
  insert into public.user_roles (user_id, role_id)
  select v_officer, id from public.roles where key = 'authorized_officer';
  insert into public.user_roles (user_id, role_id)
  select v_delegate, id from public.roles where key = 'delegate';

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  perform throws_ok(
    'select public.api_approve_shop(''00000000-0000-4000-8000-000000000099''::uuid)',
    '42501', 'MFA_REQUIRED', 'sensitive administrative operations reject an AAL1 session'
  );

  perform set_config('request.jwt.claim.sub', v_manager::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  -- All privileged workflow calls require an AAL2 JWT in production.
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  select (public.api_submit_shop('محل اختبار A', 'Test Shop A', null, null) ->> 'shop_id')::uuid into v_shop;
  perform ok(v_shop is not null, 'shop manager can submit an onboarding shop');

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.api_approve_shop(v_shop);
  perform public.api_link_shop_user(v_shop, v_technician, 'فني', true);
  perform ok((select status = 'approved' from public.shops where id = v_shop), 'admin approval activates shop A');

  perform set_config('request.jwt.claim.sub', v_manager::text, true);
  select public.api_create_device(v_shop, 'TestBrand', 'TestModel', 'Black', null, '490154203237518', null) into v_payload;
  v_device := (v_payload ->> 'device_id')::uuid;
  perform ok(v_device is not null, 'shop A registers device with valid IMEI');

  select public.api_register_sale_with_customer(
    v_shop, '490154203237518', 2500, 'بيع اختبار', v_envelope, v_envelope, null, null, v_hash, v_hash, null
  ) into v_payload;
  v_customer := (v_payload ->> 'customer_id')::uuid;
  perform ok((select status = 'sold' from public.devices where id = v_device), 'sale moves device to sold through state machine');
  perform ok(v_customer is not null, 'sale creates encrypted customer reference atomically');

  perform set_config('request.jwt.claim.sub', v_technician::text, true);
  select public.api_create_repair(v_shop, '490154203237518', v_technician, 'فحص وتشخيص', 'اختبار', 'مكتمل', '[]'::jsonb, '[]'::jsonb, null) into v_payload;
  perform ok((v_payload ->> 'operation_number') is not null, 'technician creates immutable repair operation');
  select public.api_create_format_record(v_shop, '490154203237518', v_technician, 'إعادة ضبط المصنع', null, null, 'مكتمل') into v_payload;
  perform ok((select status = 'formatted' from public.devices where id = v_device), 'technician records formatting through trusted transition');

  perform set_config('request.jwt.claim.sub', v_officer::text, true);
  select public.api_create_stolen_report_with_reporter(
    '490154203237518', 'سرقة جهاز', now() - interval '1 hour', 'وصف واقعة اختبار يتجاوز الحد الأدنى.', 'high', null, null,
    null, null, null, null, v_envelope, v_envelope, null, null, v_hash, v_hash, null
  ) into v_payload;
  v_report := (v_payload ->> 'report_id')::uuid;
  perform ok(v_report is not null and (select status = 'flagged' from public.devices where id = v_device), 'officer report flags the device immediately');

  perform set_config('request.jwt.claim.sub', v_technician::text, true);
  select public.api_check_imei('490154203237518') into v_check;
  perform ok((v_check ->> 'security_alert')::boolean, 'technician sees an immediate security alert on reported IMEI');
  perform ok((v_check -> 'report') is null, 'technician receives no report/case details');
  perform throws_ok(
    format($sql$select public.api_authorize_sensitive_customer_access('%s'::uuid, 'سبب اختبار كاف', false)$sql$, v_customer),
    '42501', 'FORBIDDEN', 'shop technician cannot access reporter/customer identity'
  );

  perform set_config('request.jwt.claim.sub', v_officer::text, true);
  perform public.api_update_report_status(v_report, 'under_review', 'بدء المراجعة');
  perform public.api_update_report_status(v_report, 'verified', 'تم التحقق');
  perform public.api_update_report_status(v_report, 'active', 'تم التفعيل');
  perform public.api_assign_report(v_report, v_officer, v_delegate, 'تحويل للمندوب');
  perform ok((select status = 'assigned' from public.stolen_reports where id = v_report), 'authorized officer can progress and assign case');

  perform set_config('request.jwt.claim.sub', v_delegate::text, true);
  perform public.api_add_report_follow_up(v_report, 'تمت متابعة الحالة ميدانيًا.', null);
  perform ok(exists (select 1 from public.report_follow_ups where report_id = v_report and created_by = v_delegate), 'assigned delegate can add a scoped follow-up');

  perform set_config('request.jwt.claim.sub', v_officer::text, true);
  perform public.api_update_report_status(v_report, 'recovered', 'تم الاسترداد');
  perform public.api_update_report_status(v_report, 'closed', 'إغلاق بعد الاسترداد');
  perform ok((select status = 'recovered' from public.devices where id = v_device), 'recovery leaves device in recovered state after case closure');
  select public.api_get_device_timeline(v_device, 100, null) into v_timeline;
  perform ok(jsonb_array_length(v_timeline -> 'events') >= 8, 'full lifecycle events appear in the device timeline');

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  select public.api_get_audit_logs(200, null) into v_audits;
  perform ok(jsonb_array_length(v_audits) >= 12, 'all lifecycle operations produce immutable audit records');
end;
$scenario$;

select * from finish();
rollback;
