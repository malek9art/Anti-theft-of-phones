import { deviceStatusLabel, reportStatusLabel } from '../lib/imei'

const toneByStatus: Record<string, string> = {
  registered: 'neutral', available: 'success', sold: 'info', in_repair: 'warning', formatted: 'info',
  flagged: 'danger', stolen: 'danger', recovered: 'success', blocked: 'danger', archived: 'neutral',
  draft: 'neutral', submitted: 'warning', under_review: 'warning', verified: 'info', active: 'danger',
  assigned: 'info', closed: 'neutral', rejected: 'neutral', cancelled: 'neutral', approved: 'success',
  suspended: 'danger', pending: 'warning', active_account: 'success', inactive: 'neutral',
}

export function StatusBadge({ status, label }: { status: string; label?: string }) {
  const translated = label ?? deviceStatusLabel[status] ?? reportStatusLabel[status] ?? status
  return <span className={`status-badge status-${toneByStatus[status] ?? 'neutral'}`}>{translated}</span>
}

export function SeverityBadge({ severity }: { severity: string }) {
  const labels: Record<string, string> = { info: 'معلومة', warning: 'تحذير', important: 'مهم', critical: 'حرج', low: 'منخفض', normal: 'عادي', high: 'مرتفع' }
  return <span className={`status-badge status-${severity === 'critical' ? 'danger' : severity === 'high' || severity === 'important' ? 'warning' : severity === 'warning' ? 'warning' : 'info'}`}>{labels[severity] ?? severity}</span>
}
