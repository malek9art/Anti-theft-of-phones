-- Atomic, server-only rate-limit counters. Edge Functions hash actor/IP identifiers before calling this RPC.
create table public.api_rate_limit_windows (
  bucket_hash text not null check (bucket_hash ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (bucket_hash, window_started_at)
);
create index api_rate_limit_cleanup_idx on public.api_rate_limit_windows(window_started_at);
alter table public.api_rate_limit_windows enable row level security;
revoke all on public.api_rate_limit_windows from anon, authenticated;

create or replace function public.api_consume_rate_limit(
  p_bucket_hash text,
  p_window_seconds integer,
  p_max_requests integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_window timestamptz;
  v_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if p_bucket_hash !~ '^[a-f0-9]{64}$' or p_window_seconds not between 10 and 86400 or p_max_requests not between 1 and 10000 then
    raise exception 'INVALID_RATE_LIMIT_ARGUMENT' using errcode = '22023';
  end if;
  v_window := to_timestamp(floor(extract(epoch from clock_timestamp()) / p_window_seconds) * p_window_seconds);
  insert into public.api_rate_limit_windows (bucket_hash, window_started_at, request_count, updated_at)
  values (p_bucket_hash, v_window, 1, clock_timestamp())
  on conflict (bucket_hash, window_started_at) do update
    set request_count = public.api_rate_limit_windows.request_count + 1,
        updated_at = clock_timestamp()
  returning request_count into v_count;

  return jsonb_build_object(
    'allowed', v_count <= p_max_requests,
    'remaining', greatest(0, p_max_requests - v_count),
    'retry_after_seconds', greatest(1, p_window_seconds - mod(extract(epoch from clock_timestamp())::integer, p_window_seconds))
  );
end;
$$;

revoke execute on function public.api_consume_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.api_consume_rate_limit(text, integer, integer) to service_role;
