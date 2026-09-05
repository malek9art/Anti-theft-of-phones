import { useEffect, useMemo, useRef, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import {
  Bell, BookOpenCheck, Building2, ChevronDown, ClipboardList, FileBarChart2,
  Gauge, HardDrive, LogOut, Menu, MoreHorizontal, PlusCircle, Search, SearchCheck,
  Settings2, ShieldAlert, ShieldCheck, Smartphone, Store, Wrench, X,
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
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [userMenuOpen, setUserMenuOpen] = useState(false)
  const [notificationsOpen, setNotificationsOpen] = useState(false)
  const [notifications, setNotifications] = useState<Notification[]>([])
  const navigate = useNavigate()
  const location = useLocation()
  const closeDrawerRef = useRef<HTMLButtonElement>(null)
  const menuButtonRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    void invoke<Notification[]>('get-notifications', { limit: 12 }).then(setNotifications).catch(() => undefined)
  }, [])

  // Close every transient panel as soon as the route changes.
  useEffect(() => {
    setDrawerOpen(false)
    setUserMenuOpen(false)
    setNotificationsOpen(false)
  }, [location.pathname])

  // Escape closes everything; body scroll is locked while the mobile drawer is open.
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        setDrawerOpen(false)
        setUserMenuOpen(false)
        setNotificationsOpen(false)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  useEffect(() => {
    if (drawerOpen) {
      document.body.classList.add('no-scroll')
      closeDrawerRef.current?.focus()
    } else {
      document.body.classList.remove('no-scroll')
    }
  }, [drawerOpen])

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

  const visibleItems = useMemo(() => items.filter((item) => item.show), [items])

  // The bottom quick bar keeps the four most-used destinations (filtered by role) plus "more".
  const bottomItems = useMemo(() => {
    const ordered = ['/', '/check', '/devices', '/reports']
      .map((to) => visibleItems.find((item) => item.to === to))
      .filter((item): item is NavItem => Boolean(item))
    return ordered.slice(0, 4)
  }, [visibleItems])

  const unread = notifications.filter((item) => !item.read_at).length
  const roles = (bootstrap?.roles ?? []).map((role) => roleLabel[role] ?? role).join(' • ')
  const displayName = bootstrap?.user.display_name ?? 'مستخدم'

  async function openNotification(notification: Notification) {
    if (!notification.read_at) {
      void invoke('mark-notification-read', { notification_id: notification.id }).catch(() => undefined)
      setNotifications((current) => current.map((item) => item.id === notification.id ? { ...item, read_at: new Date().toISOString() } : item))
    }
    setNotificationsOpen(false)
    if (notification.entity_type === 'stolen_report' && notification.entity_id) navigate(`/reports/${notification.entity_id}`)
    if (notification.entity_type === 'device' && notification.entity_id) navigate(`/devices/${notification.entity_id}`)
  }

  function renderNav(onNavigate?: () => void) {
    return (
      <nav className="sidebar-nav" aria-label="التنقل الرئيسي">
        {visibleItems.map(({ to, label, icon: Icon }) => (
          <NavLink key={to} to={to} end={to === '/'} onClick={onNavigate} className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
            <Icon size={19} /><span>{label}</span>
          </NavLink>
        ))}
      </nav>
    )
  }

  return (
    <div className="app-frame">
      <a className="skip-link" href="#main-content">تخطَّ إلى المحتوى الرئيسي</a>

      <aside className="sidebar">
        <Logo />
        <div className="tenant-chip"><span className="pulse-dot" />بيئة تشغيل محمية</div>
        {renderNav()}
        <div className="sidebar-footer"><ShieldCheck size={18} /><span>العمليات الحساسة مسجلة</span></div>
      </aside>

      {drawerOpen && <div className="drawer-backdrop" aria-hidden="true" onClick={() => setDrawerOpen(false)} />}
      <aside id="mobile-drawer" className={`drawer ${drawerOpen ? 'open' : ''}`} role="dialog" aria-modal="true" aria-label="التنقل الرئيسي">
        <div className="drawer-head">
          <Logo />
          <button ref={closeDrawerRef} className="icon-button" onClick={() => setDrawerOpen(false)} aria-label="إغلاق القائمة"><X size={21} /></button>
        </div>
        <div className="drawer-user">
          <span className="avatar">{displayName.slice(0, 1)}</span>
          <span><b>{displayName}</b><small>{roles || 'حساب معتمد'}</small></span>
        </div>
        {renderNav(() => setDrawerOpen(false))}
        <div className="drawer-foot">
          <button onClick={() => { setDrawerOpen(false); navigate('/security') }}><Settings2 size={16} />أمان الحساب</button>
          <button className="danger-action" onClick={() => void signOut()}><LogOut size={16} />تسجيل الخروج</button>
        </div>
      </aside>

      <main className="main-content" id="main-content">
        <OfflineBanner />
        <header className="topbar">
          <button ref={menuButtonRef} className="icon-button mobile-menu" onClick={() => setDrawerOpen(true)} aria-label="فتح القائمة" aria-expanded={drawerOpen} aria-controls="mobile-drawer"><Menu size={21} /></button>
          <div className="topbar-security"><span className="secure-dot" />جلسة محمية</div>
          <div className="topbar-spacer" />

          <div className="notification-wrap">
            <button className="icon-button notification-button" onClick={() => setNotificationsOpen((value) => !value)} aria-label="التنبيهات" aria-expanded={notificationsOpen} aria-haspopup="menu"><Bell size={20} />{unread > 0 && <em>{unread > 9 ? '9+' : unread}</em>}</button>
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
            <button className="user-menu" onClick={() => setUserMenuOpen((value) => !value)} aria-expanded={userMenuOpen} aria-haspopup="menu">
              <span className="avatar">{displayName.slice(0, 1)}</span>
              <span className="user-menu-text"><b>{displayName}</b><small>{roles || 'حساب معتمد'}</small></span>
              <ChevronDown size={16} />
            </button>
            {userMenuOpen && <div className="user-popover"><button onClick={() => navigate('/security')}><Settings2 size={16} />أمان الحساب</button><button className="danger-action" onClick={() => void signOut()}><LogOut size={16} />تسجيل الخروج</button></div>}
          </div>
        </header>
        <div className="page-content"><Outlet /></div>
      </main>

      <nav className="mobile-nav" aria-label="تنقل سريع">
        {bottomItems.map(({ to, label, icon: Icon }) => (
          <NavLink key={to} to={to} end={to === '/'}><Icon size={19} /><small>{label}</small></NavLink>
        ))}
        <button className="mobile-more" onClick={() => setDrawerOpen(true)} aria-label="عرض كل عناصر القائمة"><MoreHorizontal size={20} /><small>المزيد</small></button>
      </nav>

      {(userMenuOpen || notificationsOpen) && (
        <div className="popover-scrim" aria-hidden="true" onClick={() => { setUserMenuOpen(false); setNotificationsOpen(false) }} />
      )}
    </div>
  )
}
