import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

function normalizedBasePath(value = '/') {
  if (value === '/') return '/'
  return `/${value.replace(/^\/+|\/+$/g, '')}/`
}

// GitHub Pages project sites live below /<repository>/; local and custom-domain builds use /.
const base = normalizedBasePath(process.env.VITE_BASE_PATH?.trim() || '/')

export default defineConfig({
  base,
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    // Arena preview hosts are ephemeral; production is protected by CSP and Edge-origin allow-lists.
    allowedHosts: true,
    strictPort: true,
    port: 5173,
    headers: {
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Permissions-Policy': 'camera=(self), geolocation=(self), microphone=()',
    },
  },
  preview: {
    host: '0.0.0.0',
    strictPort: true,
    port: 4173,
  },
  build: {
    sourcemap: false,
    target: 'es2022',
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined
          if (id.includes('@supabase')) return 'supabase'
          if (id.includes('lucide-react')) return 'icons'
          if (id.includes('react-router') || id.includes('/react/')) return 'react'
          return undefined
        },
      },
    },
  },
})
