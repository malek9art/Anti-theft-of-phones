import { createClient, type SupabaseClient, type User } from 'npm:@supabase/supabase-js@2.112.4'

const url = Deno.env.get('SUPABASE_URL')
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')

function required(value: string | undefined, name: string): string {
  if (!value) throw new Error(`MISSING_${name}`)
  return value
}

export type RequestContext = {
  user: User
  client: SupabaseClient
  accessToken: string
  ipAddress: string | null
  deviceInformation: string | null
}

export async function requestContext(request: Request): Promise<RequestContext> {
  const authorization = request.headers.get('authorization')
  if (!authorization?.startsWith('Bearer ')) throw new Error('AUTH_REQUIRED')
  const accessToken = authorization.slice('Bearer '.length)
  const client = createClient(required(url, 'SUPABASE_URL'), required(anonKey, 'SUPABASE_ANON_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  })
  const { data, error } = await client.auth.getUser(accessToken)
  if (error || !data.user) throw new Error('AUTH_REQUIRED')

  const forwarded = request.headers.get('x-forwarded-for')
  return {
    user: data.user,
    client,
    accessToken,
    ipAddress: forwarded ? forwarded.split(',')[0].trim().slice(0, 64) : null,
    deviceInformation: (request.headers.get('user-agent') ?? '').slice(0, 500) || null,
  }
}

export function serviceClient(): SupabaseClient {
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  return createClient(required(url, 'SUPABASE_URL'), required(serviceRoleKey, 'SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

export async function rpc<T>(client: SupabaseClient, name: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await client.rpc(name, args)
  if (error) throw new Error(error.message)
  return data as T
}
