export function formatDate(value: string | null | undefined, withTime = true): string {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'
  return new Intl.DateTimeFormat('ar', {
    dateStyle: 'medium',
    ...(withTime ? { timeStyle: 'short' } : {}),
  }).format(date)
}

export function compactId(value: string | null | undefined): string {
  if (!value) return '—'
  return `${value.slice(0, 8)}…${value.slice(-4)}`
}

export function bytes(value: number): string {
  if (value < 1024) return `${value} بايت`
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} كيلوبايت`
  return `${(value / (1024 * 1024)).toFixed(1)} ميجابايت`
}
