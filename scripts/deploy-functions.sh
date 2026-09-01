#!/usr/bin/env bash
set -euo pipefail

# Deploy only after `supabase secrets set --env-file supabase/.env` has been run.
functions=(
  bootstrap check-imei create-device register-sale create-repair create-format-record
  create-stolen-report update-report-status assign-report get-device-timeline
  access-sensitive-data search-sensitive-customer create-evidence-upload complete-evidence-upload get-evidence-url
  create-device-media-upload complete-device-media-upload get-device-media-url
  create-identity-document-upload complete-identity-document-upload get-identity-document-url
  get-dashboard get-notifications mark-notification-read generate-report security-event ingest-auth-event
  add-report-follow-up get-reports get-report-detail get-devices get-audit-logs get-security-events
  submit-shop approve-shop suspend-shop link-shop-user set-user-roles update-user-status create-location
  search-records get-shops resolve-security-event update-system-setting revoke-other-sessions get-users invite-user get-case-assignees
)
for function_name in "${functions[@]}"; do
  echo "Deploying ${function_name}"
  supabase functions deploy "$function_name"
done
