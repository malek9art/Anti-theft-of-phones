import { CheckCircle2, CircleAlert, X } from 'lucide-react'

export function Toast({ type = 'success', message, onClose }: { type?: 'success' | 'error'; message: string; onClose: () => void }) {
  return <div className={`toast toast-${type}`} role="status">{type === 'success' ? <CheckCircle2 size={20} /> : <CircleAlert size={20} />}<span>{message}</span><button onClick={onClose} aria-label="إغلاق"><X size={16} /></button></div>
}
