export function LoadingState({ label = 'جارٍ تحميل البيانات…' }: { label?: string }) {
  return <div className="loading-state" role="status"><span className="spinner" />{label}</div>
}

export function InlineLoader() {
  return <span className="spinner spinner-small" aria-label="جارٍ التحميل" />
}
