import { useEffect, useState, type FormEvent } from 'react'
import { AlertTriangle, BadgeCheck, KeyRound, MailPlus, ShieldCheck, UserCog, UsersRound } from 'lucide-react'
import { EmptyState } from '../components/EmptyState'
import { InlineLoader, LoadingState } from '../components/LoadingState'
import { Modal } from '../components/Modal'
import { PageHeader } from '../components/PageHeader'
import { StatusBadge } from '../components/StatusBadge'
import { useAuth } from '../contexts/AuthContext'
import { invoke, readableError } from '../lib/api'
import { compactId, formatDate } from '../lib/format'

type UserRow = { id: string; display_name: string; account_status: string; mfa_required: boolean; agency_id: string | null; created_at: string; roles: string[] }
const allRoles = [
  ['system_admin', 'مدير النظام'], ['authorized_officer', 'موظف جهة مختصة'], ['investigation_officer', 'ضابط بحث جنائي'],
  ['delegate', 'مندوب'], ['shop_manager', 'مدير محل'], ['technician', 'فني'], ['auditor', 'مدقق'],
] as const

export function UsersPage() {
  const { can } = useAuth()
  const [users, setUsers] = useState<UserRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<UserRow | null>(null)
  const [inviteOpen, setInviteOpen] = useState(false)

  const load = () => { setUsers(null); setError(null); void invoke<UserRow[]>('get-users', { limit: 100, offset: 0 }).then(setUsers).catch((caught) => setError(readableError(caught))) }
  useEffect(load, []) // eslint-disable-line react-hooks/exhaustive-deps
  return <><PageHeader eyebrow="إدارة الهوية" title="المستخدمون والصلاحيات" description="الأدوار لا تُمنح من الجهاز العميل. كل تعديل يتطلب صلاحية إدارية ويسجل في سجل التدقيق." actions={can('manage_users') ? <button className="primary-button" onClick={() => setInviteOpen(true)}><MailPlus size={18} />دعوة مستخدم</button> : undefined} />{error ? <EmptyState icon={AlertTriangle} title="تعذر تحميل المستخدمين" description={error} /> : !users ? <LoadingState /> : !users.length ? <EmptyState icon={UsersRound} title="لا توجد حسابات" description="استخدم دعوة مستخدم لإرسال رابط تفعيل آمن." /> : <section className="users-list">{users.map((user) => <button className="user-row" key={user.id} onClick={() => setSelected(user)}><span className="avatar large-avatar">{user.display_name.slice(0, 1)}</span><span className="user-row-main"><b>{user.display_name}</b><small>{compactId(user.id)} · انضم {formatDate(user.created_at, false)}</small><span className="role-chips">{user.roles.length ? user.roles.map((role) => <em key={role}>{allRoles.find(([key]) => key === role)?.[1] ?? role}</em>) : <em>دون دور</em>}</span></span><span className="user-row-status"><StatusBadge status={user.account_status} label={{ active: 'نشط', pending: 'قيد الاعتماد', suspended: 'معلق', inactive: 'غير نشط' }[user.account_status]} />{user.mfa_required && <span className="mfa-mini"><KeyRound size={13} />MFA</span>}</span></button>)}</section>}{selected && <EditUserModal user={selected} canManagePermissions={can('manage_permissions')} onClose={() => setSelected(null)} onDone={() => { setSelected(null); load() }} />}{inviteOpen && <InviteModal onClose={() => setInviteOpen(false)} onDone={() => { setInviteOpen(false); load() }} />}</>
}

function InviteModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [email, setEmail] = useState('')
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); setError(null); try { await invoke('invite-user', { email, display_name: name || null }); onDone() } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  return <Modal title="دعوة مستخدم" onClose={onClose}><p className="modal-intro">ترسل الدعوة من Supabase Auth؛ لا تُنشأ كلمة مرور أو مفتاح سري من هذه الواجهة.</p><form className="form-stack" onSubmit={submit}><label>البريد الإلكتروني<input dir="ltr" type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label><label>الاسم المعروض<input value={name} onChange={(event) => setName(event.target.value)} maxLength={160} /></label>{error && <div className="inline-alert danger">{error}</div>}<div className="modal-actions"><button type="button" className="secondary-button" onClick={onClose}>إلغاء</button><button className="primary-button" disabled={busy}>{busy ? <InlineLoader /> : <><MailPlus size={17} />إرسال الدعوة</>}</button></div></form></Modal>
}

function EditUserModal({ user, canManagePermissions, onClose, onDone }: { user: UserRow; canManagePermissions: boolean; onClose: () => void; onDone: () => void }) {
  const [status, setStatus] = useState(user.account_status)
  const [mfaRequired, setMfaRequired] = useState(user.mfa_required)
  const [roles, setRoles] = useState<string[]>(user.roles)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); setError(null); try { await invoke('update-user-status', { user_id: user.id, status, reason: status === 'suspended' ? reason : null, mfa_required: mfaRequired }); if (canManagePermissions) await invoke('set-user-roles', { user_id: user.id, role_keys: roles }); onDone() } catch (caught) { setError(readableError(caught)) } finally { setBusy(false) } }
  function toggleRole(role: string) { setRoles((current) => current.includes(role) ? current.filter((item) => item !== role) : [...current, role]) }
  return <Modal title="إدارة حساب المستخدم" onClose={onClose} wide><form className="form-grid" onSubmit={submit}><div className="form-span-2 user-edit-heading"><span className="avatar large-avatar">{user.display_name.slice(0, 1)}</span><div><h3>{user.display_name}</h3><small>{compactId(user.id)}</small></div></div><label>حالة الحساب<select value={status} onChange={(event) => setStatus(event.target.value)}><option value="pending">قيد الاعتماد</option><option value="active">نشط</option><option value="suspended">معلّق</option><option value="inactive">غير نشط</option></select></label><label className="switch-label"><span>إلزام التحقق بخطوتين<small>يطبّق على العمليات الحساسة بعد التفعيل.</small></span><input type="checkbox" checked={mfaRequired} onChange={(event) => setMfaRequired(event.target.checked)} /></label>{status === 'suspended' && <label className="form-span-2">سبب التعليق<textarea rows={3} value={reason} onChange={(event) => setReason(event.target.value)} minLength={5} maxLength={1000} required /></label>}{canManagePermissions && <fieldset className="form-span-2 role-fieldset"><legend><ShieldCheck size={17} />الأدوار الممنوحة</legend><div>{allRoles.map(([key, label]) => <label key={key} className="role-choice"><input type="checkbox" checked={roles.includes(key)} onChange={() => toggleRole(key)} /><span>{label}</span></label>)}</div></fieldset>}{error && <div className="inline-alert danger form-span-2">{error}</div>}<div className="modal-actions form-span-2"><button type="button" className="secondary-button" onClick={onClose}>إلغاء</button><button className="primary-button" disabled={busy}>{busy ? <InlineLoader /> : <><UserCog size={17} />حفظ التغييرات</>}</button></div></form></Modal>
}
