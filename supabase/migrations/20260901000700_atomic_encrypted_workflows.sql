-- Atomic wrappers keep encrypted customer creation and its sale/report in one database transaction.

create or replace function public.api_register_sale_with_customer(
  p_shop_id uuid,
  p_imei text,
  p_unit_price numeric,
  p_notes text,
  p_full_name_ciphertext text,
  p_phone_ciphertext text,
  p_national_id_ciphertext text,
  p_address_ciphertext text,
  p_full_name_lookup_hash text,
  p_phone_lookup_hash text,
  p_national_id_lookup_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_customer jsonb;
  v_customer_id uuid;
  v_sale jsonb;
begin
  v_customer := public.api_create_customer(
    p_full_name_ciphertext, p_phone_ciphertext, p_national_id_ciphertext, p_address_ciphertext,
    p_full_name_lookup_hash, p_phone_lookup_hash, p_national_id_lookup_hash
  );
  v_customer_id := (v_customer ->> 'customer_id')::uuid;
  v_sale := public.api_register_sale(p_shop_id, p_imei, v_customer_id, p_unit_price, p_notes);
  return v_sale || jsonb_build_object('customer_id', v_customer_id, 'customer_reference_code', v_customer ->> 'reference_code');
end;
$$;

create or replace function public.api_create_stolen_report_with_reporter(
  p_imei text,
  p_report_type text,
  p_incident_at timestamptz,
  p_description text,
  p_priority public.report_priority,
  p_agency_id uuid,
  p_incident_location_id uuid,
  p_imei2 text,
  p_brand text,
  p_model text,
  p_color text,
  p_full_name_ciphertext text,
  p_phone_ciphertext text,
  p_national_id_ciphertext text,
  p_address_ciphertext text,
  p_full_name_lookup_hash text,
  p_phone_lookup_hash text,
  p_national_id_lookup_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_customer jsonb;
  v_customer_id uuid;
  v_report jsonb;
begin
  v_customer := public.api_create_customer(
    p_full_name_ciphertext, p_phone_ciphertext, p_national_id_ciphertext, p_address_ciphertext,
    p_full_name_lookup_hash, p_phone_lookup_hash, p_national_id_lookup_hash
  );
  v_customer_id := (v_customer ->> 'customer_id')::uuid;
  v_report := public.api_create_stolen_report(
    p_imei, v_customer_id, p_report_type, p_incident_at, p_description, p_priority,
    p_agency_id, p_incident_location_id, p_imei2, p_brand, p_model, p_color
  );
  return v_report || jsonb_build_object('reporter_customer_id', v_customer_id, 'reporter_reference_code', v_customer ->> 'reference_code');
end;
$$;
