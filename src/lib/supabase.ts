import { createClient, type SupabaseClient } from '@supabase/supabase-js'

declare global {
  interface Window {
    __HIMAYA_CONFIG__?: { SUPABASE_URL?: string; SUPABASE_ANON_KEY?: string }
  }
}

// Public browser configuration. Branch-based GitHub Pages cannot inject VITE_* at
// build time, so the served config.js exposes the same two public values at runtime.
// VITE_* remains the fallback for local development and GitHub Actions builds.
const runtime = typeof window !== 'undefined' ? window.__HIMAYA_CONFIG__ : undefined
const url = runtime?.SUPABASE_URL?.trim() || import.meta.env.VITE_SUPABASE_URL?.trim()
const anonKey = runtime?.SUPABASE_ANON_KEY?.trim() || import.meta.env.VITE_SUPABASE_ANON_KEY?.trim()

export const isSupabaseConfigured = Boolean(
  url && anonKey && (/^https:\/\//.test(url) || /^http:\/\/(localhost|127\.0\.0\.1)/.test(url)),
)

// Tokens and any business data are memory-only. No device/customer/report data is written to localStorage.
export const supabase: SupabaseClient | null = isSupabaseConfigured
  ? createClient(url!, anonKey!, {
      auth: {
        persistSession: false,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
      global: {
        headers: { 'X-Client-Application': 'himaya-web' },
      },
    })
  : null

export function requireSupabase(): SupabaseClient {
  if (!supabase) throw new Error('SUPABASE_NOT_CONFIGURED')
  return supabase
}
