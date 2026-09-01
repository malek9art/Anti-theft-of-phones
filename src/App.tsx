import { Navigate, Route, Routes } from 'react-router-dom'
import { AppShell } from './components/AppShell'
import { LoadingState } from './components/LoadingState'
import { useAuth } from './contexts/AuthContext'
import { AdvancedSearchPage } from './pages/AdvancedSearchPage'
import { AuditLogsPage } from './pages/AuditLogsPage'
import { ConfigurationPage } from './pages/ConfigurationPage'
import { CreateDevicePage } from './pages/CreateDevicePage'
import { DashboardPage } from './pages/DashboardPage'
import { DeviceCheckPage } from './pages/DeviceCheckPage'
import { DeviceDetailPage } from './pages/DeviceDetailPage'
import { DevicesPage } from './pages/DevicesPage'
import { ExportsPage } from './pages/ExportsPage'
import { ForbiddenPage } from './pages/ForbiddenPage'
import { FormatRecordPage } from './pages/FormatRecordPage'
import { LoginPage } from './pages/LoginPage'
import { MfaPage } from './pages/MfaPage'
import { OnboardingPage } from './pages/OnboardingPage'
import { ReportDetailPage } from './pages/ReportDetailPage'
import { ReportsPage } from './pages/ReportsPage'
import { SalePage } from './pages/SalePage'
import { SecurityEventsPage } from './pages/SecurityEventsPage'
import { SecuritySettingsPage } from './pages/SecuritySettingsPage'
import { ShopsPage } from './pages/ShopsPage'
import { TechnicianIntakePage } from './pages/TechnicianIntakePage'
import { UsersPage } from './pages/UsersPage'

function Guard({ anyOf, children }: { anyOf: string[]; children: JSX.Element }) {
  const { can } = useAuth()
  return anyOf.some(can) ? children : <ForbiddenPage />
}

export default function App() {
  const { configured, loading, session, bootstrap, needsMfa } = useAuth()
  if (!configured) return <ConfigurationPage />
  if (loading) return <main className="initial-loader"><LoadingState label="جارٍ التحقق من الجلسة الآمنة…" /></main>
  if (!session) return <LoginPage />
  if (!bootstrap) return <main className="initial-loader"><LoadingState label="جارٍ التحقق من صلاحيات الحساب…" /></main>
  if (bootstrap.user.account_status === 'pending') return <OnboardingPage />
  if (needsMfa) return <MfaPage />

  return <Routes>
    <Route element={<AppShell />}>
      <Route index element={<DashboardPage />} />
      <Route path="check" element={<Guard anyOf={['search_imei']}><DeviceCheckPage /></Guard>} />
      <Route path="search" element={<Guard anyOf={['search_imei', 'view_all_reports']}><AdvancedSearchPage /></Guard>} />
      <Route path="devices" element={<Guard anyOf={['view_device']}><DevicesPage /></Guard>} />
      <Route path="devices/new" element={<Guard anyOf={['create_device']}><CreateDevicePage /></Guard>} />
      <Route path="devices/:id" element={<Guard anyOf={['view_device']}><DeviceDetailPage /></Guard>} />
      <Route path="sales/new" element={<Guard anyOf={['create_sale']}><SalePage /></Guard>} />
      <Route path="intake" element={<Guard anyOf={['create_repair']}><TechnicianIntakePage /></Guard>} />
      <Route path="format" element={<Guard anyOf={['create_format_record']}><FormatRecordPage /></Guard>} />
      <Route path="reports" element={<Guard anyOf={['view_all_reports', 'update_follow_up', 'create_stolen_report']}><ReportsPage /></Guard>} />
      <Route path="reports/:id" element={<Guard anyOf={['view_all_reports', 'update_follow_up']}><ReportDetailPage /></Guard>} />
      <Route path="shops" element={<Guard anyOf={['manage_shops', 'manage_shop_staff']}><ShopsPage /></Guard>} />
      <Route path="users" element={<Guard anyOf={['manage_users', 'manage_permissions']}><UsersPage /></Guard>} />
      <Route path="exports" element={<Guard anyOf={['generate_reports']}><ExportsPage /></Guard>} />
      <Route path="audit" element={<Guard anyOf={['view_audit_logs']}><AuditLogsPage /></Guard>} />
      <Route path="security-events" element={<Guard anyOf={['view_security_events']}><SecurityEventsPage /></Guard>} />
      <Route path="security" element={<SecuritySettingsPage />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Route>
  </Routes>
}
