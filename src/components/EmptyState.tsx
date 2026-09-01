import type { LucideIcon } from 'lucide-react'
import type { ReactNode } from 'react'

export function EmptyState({ icon: Icon, title, description, action }: { icon: LucideIcon; title: string; description: string; action?: ReactNode }) {
  return <section className="empty-state"><Icon size={34} strokeWidth={1.5} /><h3>{title}</h3><p>{description}</p>{action}</section>
}
