import { ShieldCheck } from 'lucide-react'

export function Logo({ compact = false }: { compact?: boolean }) {
  return (
    <div className="brand" aria-label="حماية">
      <span className="brand-mark"><ShieldCheck size={compact ? 22 : 26} strokeWidth={2.3} /></span>
      {!compact && <span><b>حماية</b><small>سجل الجهاز الموثوق</small></span>}
    </div>
  )
}
