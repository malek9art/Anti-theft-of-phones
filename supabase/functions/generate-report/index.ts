import { withAuthenticatedRequest } from '../_shared/handler.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { readJson } from '../_shared/http.ts'
import { rpc } from '../_shared/supabase.ts'
import { enumValue } from '../_shared/validation.ts'

const kinds = ['sales', 'repairs', 'formats', 'reports'] as const

type ExportPayload = { kind: string; from: string; to: string; rows: Array<Record<string, unknown>> }

function optionalDate(value: unknown): string | null {
  if (value === null || value === undefined || value === '') return null
  if (typeof value !== 'string' || Number.isNaN(new Date(value).getTime())) throw new Error('INVALID_DATE')
  return new Date(value).toISOString()
}

// Prevent spreadsheet formula injection when a CSV is opened in Excel/LibreOffice.
function csvValue(value: unknown): string {
  const raw = value === null || value === undefined ? '' : String(value)
  const safe = /^[=+\-@]/.test(raw) ? `'${raw}` : raw
  return `"${safe.replaceAll('"', '""')}"`
}

Deno.serve(withAuthenticatedRequest(async (request, context) => {
  const body = await readJson(request)
  const report = await rpc<ExportPayload>(context.client, 'api_export_report', {
    p_kind: enumValue(body.kind, kinds, 'REPORT_KIND'),
    p_from: optionalDate(body.from),
    p_to: optionalDate(body.to),
  })
  const columns = [...new Set(report.rows.flatMap((row) => Object.keys(row)))]
  const csv = `\uFEFF${columns.join(',')}\r\n${report.rows.map((row) => columns.map((column) => csvValue(row[column])).join(',')).join('\r\n')}`
  return new Response(csv, {
    status: 200,
    headers: {
      ...corsHeaders(request),
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="himaya-${report.kind}-${new Date().toISOString().slice(0, 10)}.csv"`,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  })
}, { scope: 'generate-report', maxRequests: 10, windowSeconds: 600 }))
