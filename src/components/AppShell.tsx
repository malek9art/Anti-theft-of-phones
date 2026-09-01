import { useEffect, useMemo, useState } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import {
  Bell, BookOpenCheck, Building2, ChevronDown, ClipboardList, FileBarChart2,
  Gauge, HardDrive, LogOut, Menu, PlusCircle, Search, SearchCheck, Settings2,
  ShieldAlert, ShieldCheck, Smartphone, Store, Wrench,
} from 'lucide-react'
import { useAuth } from '../contexts/AuthContext'
import { invoke } from '../lib/api'
import { formatDate } from '../lib/format'
import type { Notification } from '../types/domain'
import { Logo } from './Logo'
import { OfflineBanner } from './OfflineBanner'
import { SeverityBadge } from './StatusBadge'

const roleLabel: Record<string, string> = {
  system_admin: 'مدير النظام', authorized_officer: 'موظف جهة مختصة', investigation_officer: 'ضابط بحث جنائي',
  delegate: 'مندوب متابعة', shop_manager: 'مدير محل', technician: 'فني', auditor: 'مدقق',
}

type NavItem = { to: string; label: string; icon: typeof Gauge; show: boolean }

export function AppShell() {
  const { bootstrap, can, signOut } = useAuth()
  const [menuOpen, setMenuOpen] = useState(false)
  const [notificationsOpen, setNotificationsOpen] = useState(false)
  const [notifications, setNotifications] = useState<Notification[]>([])
  const navigate = useNavigate()

  useEffect(() => {
    void invoke<Notification[]>('get-notifications', { limit: 12 }).then(setNotifications).catch(() => undefined)
  }, [])

  const items = useMemo<NavItem[]>(() => [
    { to: '/', label: 'لوحة التحكم', icon: Gauge, show: true },
    { to: '/check', label: 'فحص الجهاز', icon: SearchCheck, show: can('search_imei') },
    { to: '/search', label: 'البحث المتقدم', icon: Search, show: can('search_imei') || can('view_all_reports') },
    { to: '/devices', label: 'الأجهزة', icon: Smartphone, show: can('view_device') },
    { to: '/devices/new', label: 'تسجيل جهاز', icon: PlusCircle, show: can('create_device') },
    { to: '/sales/new', label: 'تسجيل بيع', icon: Store, show: can('create_sale') },
    { to: '/intake', label: 'استلام وصيانة', icon: Wrench, show: can('create_repair') },
    { to: '/format', label: 'تسجيل فرمتة', icon: HardDrive, show: can('create_format_record') },
    { to: '/reports', label: 'البلاغات', icon: ClipboardList, show: can('view_all_reports') || can('update_follow_up') || can('create_stolen_report') },
    { to: '/shops', label: 'المحلات', icon: Building2, show: can('manage_shops') || can('manage_shop_staff') },
    { to: '/users', label: 'المستخدمون والصلاحيات', icon: ShieldCheck, show: can('manage_users') || can('manage_permissions') },
    { to: '/exports', label: 'التقارير', icon: FileBarChart2, show: can('generate_reports') },
    { to: '/audit', label: 'سجل التدقيق', icon: BookOpenCheck, show: can('view_audit_logs') },
    { to: '/security-events', label: 'الأمن والتنبيهات', icon: ShieldAlert, show: can('view_security_events') },
    { to: '/security', label: 'أمان الحساب', icon: Settings2, show: true },
  ], [can])

  const unread = notifications.filter((item) => !item.read_at).length
  const roles = (bootstrap?.roles ?? []).map((role) => roleLabel[role] ?? role).join(' • ')

  async function openNotification(notification: Notification) {
    if (!notification.read_at) {
      void invoke('mark-notification-read', { notification_id: notification.id }).catch(() => undefined)
      setNotifications((current) => current.map((item) => item.id === notification.id ? { ...item, read_at: new Date().toISOString() } : item))
    }
    setNotificationsOpen(false)
    if (notification.entity_type === 'stolen_report' && notification.entity_id) navigate(`/reports/${notification.entity_id}`)
    if (notification.entity_type === 'device' && notification.entity_id) navigate(`/devices/${notification.entity_id}`)
  }

  return (
    <div className="app-frame">
      <aside className="sidebar">
        <Logo />
        <div className="tenant-chip"><span className="pulse-dot" />بيئة تشغيل محمية</div>
        <nav className="sidebar-nav" aria-label="التنقل الرئيسي">
          {items.filter((item) => item.show).map(({ to, label, icon: Icon }) => (
            <NavLink key={to} to={to} end={to === '/'} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
              <Icon size={19} /><span>{label}</span>
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-footer"><ShieldCheck size={18} /><span>العمليات الحساسة مسجلة</span></div>
      </aside>

      <main className="main-content">
        <OfflineBanner />
        <header className="topbar">
          <button className="icon-button mobile-menu" onClick={() => setMenuOpen((value) => !value)} aria-label="القائمة"><Menu size={21} /></button>
          <div className="topbar-security"><span className="secure-dot" />جلسة محمية</div>
          <div className="topbar-spacer" />
          <div className="notification-wrap">
            <button className="icon-button notification-button" onClick={() => setNotificationsOpen((value) => !value)} aria-label="التنبيهات"><Bell size={20} />{unread > 0 && <em>{unread > 9 ? '9+' : unread}</em>}</button>
            {notificationsOpen && <div className="notification-panel">
              <div className="panel-heading"><b>التنبيهات</b><span>{unread ? `${unread} غير مقروءة` : 'لا توجد تنبيهات جديدة'}</span></div>
              {notifications.length ? notifications.map((notification) => (
                <button key={notification.id} className={`notification-row ${notification.read_at ? '' : 'unread'}`} onClick={() => void openNotification(notification)}>
                  <SeverityBadge severity={notification.severity} /><span><b>{notification.title}</b><small>{notification.body}</small><time>{formatDate(notification.created_at)}</time></span>
                </button>
              )) : <p className="panel-empty">لا توجد تنبيهات في الوقت الحالي.</p>}
            </div>}
          </div>
          <div className="user-menu-wrap">
            <button className="user-menu" onClick={() => setMenuOpen((value) => !value)}><span className="avatar">{bootstrap?.user.display_name.slice(0, 1) ?? 'م'}</span><span className="user-menu-text"><b>{bootstrap?.user.display_name}</b><small>{roles || 'حساب معتمد'}</small></span><ChevronDown size={16} /></button>
            {menuOpen && <div className="user-popover"><button onClick={() => navigate('/security')}><Settings2 size={16} />أمان الحساب</button><button className="danger-action" onClick={() => void signOut()}><LogOut size={16} />تسجيل الخروج</button></div>}
          </div>
        </header>
        <div className="page-content"><Outlet /></div>
      </main>

      <nav className="mobile-nav" aria-label="تنقل سريع">
        {items.filter((item) => item.show).slice(0, 5).map(({ to, label, icon: Icon }) => <NavLink key={to} to={to} end={to === '/'}><Icon size={19} /><small>{label}</small></NavLink>)}
      </nav>
    </div>
  )
}
