export type AccountStatus = 'pending' | 'active' | 'suspended' | 'inactive'
export type DeviceStatus = 'registered' | 'available' | 'sold' | 'in_repair' | 'formatted' | 'flagged' | 'stolen' | 'recovered' | 'blocked' | 'archived'
export type ReportStatus = 'draft' | 'submitted' | 'under_review' | 'verified' | 'active' | 'assigned' | 'recovered' | 'closed' | 'rejected' | 'cancelled'
export type Severity = 'info' | 'warning' | 'important' | 'critical'

export type ShopSummary = {
  id: string
  name: string
  status: string
  verification_status: string
  title: string | null
}

export type Bootstrap = {
  user: {
    id: string
    display_name: string
    account_status: AccountStatus
    mfa_required: boolean
    agency_id: string | null
  }
  roles: string[]
  permissions: string[]
  shops: ShopSummary[]
}

export type DashboardMetrics = {
  period: { from: string; to: string }
  devices_registered: number
  devices_sold: number
  repair_operations: number
  format_operations: number
  active_reports: number
  new_reports: number
  recovered_devices: number
  active_shops: number
  suspended_shops: number
  suspicious_operations: number
  unauthorized_attempts: number
}

export type ImeiResult = {
  imei: string
  found: boolean
  security_alert: boolean
  message_code: 'not_registered' | 'reported_device' | 'no_active_report'
  message_ar: string
  device?: {
    id: string
    brand: string
    model: string
    status: DeviceStatus
  } | null
  report?: {
    id: string
    report_number: string
    status: ReportStatus
    priority: string
    created_at: string
    agency_id: string | null
  } | null
}

export type TimelineEvent = {
  id: string
  event_type: string
  entity_type: string
  entity_id: string | null
  operation_number: string | null
  actor_id: string | null
  shop_id: string | null
  agency_id: string | null
  notes: string | null
  metadata: Record<string, unknown>
  occurred_at: string
}

export type DeviceTimeline = {
  device: {
    id: string
    brand: string
    model: string
    color: string | null
    serial_number: string | null
    status: DeviceStatus
    created_at: string
    imeis: Array<{ slot: number; imei: string }>
  }
  events: TimelineEvent[]
}

export type RepairReceipt = {
  repair_id: string
  operation_number: string
  device_id: string
  technician_id: string
  created_at: string
}

export type ReportSummary = {
  id: string
  report_number: string
  device_id: string
  imei_last4: string
  report_type: string
  incident_at: string
  status: ReportStatus
  priority: Severity | 'low' | 'normal' | 'high'
  agency_id: string | null
  assigned_officer_id: string | null
  assigned_delegate_id: string | null
  created_at: string
}

export type ReportDetail = {
  report: {
    id: string
    report_number: string
    device_id: string
    imei_snapshot: string
    imei2_snapshot: string | null
    report_type: string
    incident_at: string
    incident_location_id: string | null
    description: string
    status: ReportStatus
    priority: Severity | 'low' | 'normal' | 'high'
    agency_id: string | null
    assigned_officer_id: string | null
    assigned_delegate_id: string | null
    created_at: string
    updated_at: string
    closed_at: string | null
  }
  status_history: Array<{ id: string; from_status: ReportStatus | null; to_status: ReportStatus; note: string | null; changed_by: string; changed_at: string }>
  follow_ups: Array<{ id: string; note: string; location_id: string | null; created_by: string; created_at: string }>
  evidence: Array<{ id: string; evidence_type: string; original_name: string; content_type: string; size_bytes: number; description: string | null; access_level: string; status: string; uploaded_at: string | null }>
}

export type Notification = {
  id: string
  severity: Severity
  notification_type: string
  title: string
  body: string
  entity_type: string | null
  entity_id: string | null
  read_at: string | null
  created_at: string
}

export type Shop = {
  id: string
  shop_name: string
  commercial_name: string | null
  status: string
  verification_status: string
  created_at: string
  approved_at: string | null
  suspension_reason: string | null
}

export type AuditLog = {
  id: string
  sequence_number: number
  actor_id: string | null
  actor_roles: string[]
  action: string
  entity_type: string
  entity_id: string | null
  result: 'success' | 'failure' | 'denied'
  metadata: Record<string, unknown>
  occurred_at: string
  entry_hash: string
  previous_hash: string | null
}

export type SecurityEvent = {
  id: string
  event_type: string
  severity: Severity
  metadata: Record<string, unknown>
  created_at: string
  resolved_at: string | null
  resolved_by: string | null
}

export type ApiErrorShape = { error?: { code?: string; message_ar?: string; message?: string } }
