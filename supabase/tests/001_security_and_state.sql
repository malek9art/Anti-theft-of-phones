-- Run with `supabase test db`. Requires pgTAP from the local Supabase test image.
begin;
select plan(12);

select ok(public.is_valid_imei('490154203237518'), 'accepts a Luhn-valid IMEI');
select ok(not public.is_valid_imei('490154203237519'), 'rejects bad Luhn check digit');
select ok(not public.is_valid_imei('49015420323751'), 'rejects short IMEI');
select ok(not public.is_valid_imei('49015420323751X'), 'rejects non-numeric IMEI');

select ok(exists (select 1 from public.device_status_transitions where from_status = 'registered' and to_status = 'sold'), 'registered device can be sold through trusted API');
select ok(exists (select 1 from public.device_status_transitions where from_status = 'in_repair' and to_status = 'formatted'), 'repair can transition to formatted');
select ok(not exists (select 1 from public.device_status_transitions where from_status = 'stolen' and to_status = 'available'), 'stolen device cannot be silently made available');
select ok(not exists (select 1 from public.device_status_transitions where from_status = 'flagged' and to_status = 'sold'), 'flagged device cannot be sold');

select ok((select relrowsecurity from pg_class where oid = 'public.devices'::regclass), 'devices has RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.customer_sensitive_data'::regclass), 'customer ciphertext table has RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.audit_logs'::regclass), 'audit log has RLS enabled');
select ok(exists (select 1 from pg_trigger where tgrelid = 'public.audit_logs'::regclass and tgname = 'immutable_audit_logs'), 'audit log has immutable trigger');

select * from finish();
rollback;
