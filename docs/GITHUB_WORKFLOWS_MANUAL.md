# ملفات GitHub Actions — النسخ المرجعية الكاملة (تتطلب تطبيقًا يدويًا من مالك المستودع)

اتصال التكامل الحالي **لا يملك صلاحية `workflows`**، لذا لا يمكنه رفع أو تعديل ملفات `.github/workflows/*.yml`. يجب على مالك المستودع تطبيق المحتوى أدناه يدويًا من GitHub عبر **Add file → Create new file** (أو تعديل الملف الموجود) ولصق المحتوى كما هو في المسار المذكور.

الملفات الثلاثة المطلوبة:

- `ci.yml` — تحقق الواجهة والفحوصات الثابتة (حدّث قائمة الفروع إلى `arena/01a06464-anti-theft-of-phones`).
- `deploy-pages.yml` — بناء الواجهة ونشرها كـ PWA على GitHub Pages (حدّث اسم الفرع كذلك).
- `deploy-supabase.yml` — تطبيق migrations ونشر Edge Functions وأسرار الخادم (يدوي فقط عبر GitHub Environments).

لا تضع قيم الأسرار داخل هذه الملفات؛ أبقِ الصيغة `${{ secrets.NAME }}` كما هي.

---

## 1) `.github/workflows/ci.yml`

```yaml
name: Verify Himaya

on:
  push:
    branches: [main, arena/01a06464-anti-theft-of-phones]
  pull_request:

permissions:
  contents: read

jobs:
  web-and-static-security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run check
      - run: npm run check:pwa
      - run: npm run check:edge
      - run: npm test
      - run: npm run build
      - run: npm run secrets:check
```

---

## 2) `.github/workflows/deploy-pages.yml`

```yaml
name: Deploy Himaya PWA to GitHub Pages

on:
  push:
    branches:
      - main
      - arena/01a06464-anti-theft-of-phones
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: github-pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      base_path: ${{ steps.base.outputs.value }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - uses: actions/configure-pages@v5
      - name: Resolve the public base path
        id: base
        env:
          CONFIGURED_BASE_PATH: ${{ vars.PAGES_BASE_PATH }}
          REPOSITORY_NAME: ${{ github.event.repository.name }}
        run: |
          set -euo pipefail
          value="${CONFIGURED_BASE_PATH:-/${REPOSITORY_NAME}/}"
          case "$value" in
            /|/*/) ;;
            *) echo "::error::PAGES_BASE_PATH must be / or start and end with /."; exit 1 ;;
          esac
          echo "value=$value" >> "$GITHUB_OUTPUT"
      - run: npm ci
      - run: npm run check:pwa
      - name: Ensure browser configuration is present
        env:
          VITE_SUPABASE_URL: ${{ secrets.VITE_SUPABASE_URL }}
          VITE_SUPABASE_ANON_KEY: ${{ secrets.VITE_SUPABASE_ANON_KEY }}
        run: |
          set -euo pipefail
          test -n "$VITE_SUPABASE_URL" || { echo "::error::Missing VITE_SUPABASE_URL GitHub secret."; exit 1; }
          test -n "$VITE_SUPABASE_ANON_KEY" || { echo "::error::Missing VITE_SUPABASE_ANON_KEY GitHub secret."; exit 1; }
          [[ "$VITE_SUPABASE_URL" =~ ^https:// ]] || { echo "::error::VITE_SUPABASE_URL must start with https://"; exit 1; }
      - name: Build the static PWA
        env:
          VITE_SUPABASE_URL: ${{ secrets.VITE_SUPABASE_URL }}
          VITE_SUPABASE_ANON_KEY: ${{ secrets.VITE_SUPABASE_ANON_KEY }}
          VITE_APP_ENV: production
          VITE_BASE_PATH: ${{ steps.base.outputs.value }}
          VITE_ROUTER_MODE: hash
        run: npm run build
      - uses: actions/upload-pages-artifact@v3
        with:
          path: dist

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

أضف Repository Secrets التاليين قبل تشغيل هذا workflow:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
```

---

## 3) `.github/workflows/deploy-supabase.yml`

```yaml
name: Deploy Himaya Supabase backend

# Deliberately manual: production database/schema changes require an approved environment.
on:
  workflow_dispatch:
    inputs:
      environment:
        description: GitHub Environment that holds the target Supabase secrets
        required: true
        type: choice
        options:
          - staging
          - production

permissions:
  contents: read

concurrency:
  group: himaya-supabase-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  deploy:
    name: Deploy Supabase to ${{ inputs.environment }}
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    env:
      SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
      SUPABASE_PROJECT_REF: ${{ secrets.SUPABASE_PROJECT_REF }}
      SUPABASE_DB_PASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}
      SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
      SUPABASE_ANON_KEY: ${{ secrets.SUPABASE_ANON_KEY }}
      SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}
      ALLOWED_ORIGINS: ${{ secrets.ALLOWED_ORIGINS }}
      APP_REDIRECT_URL: ${{ secrets.APP_REDIRECT_URL }}
      SENSITIVE_DATA_ENCRYPTION_KEY: ${{ secrets.SENSITIVE_DATA_ENCRYPTION_KEY }}
      SENSITIVE_DATA_LOOKUP_KEY: ${{ secrets.SENSITIVE_DATA_LOOKUP_KEY }}
      AUTH_EVENT_INGEST_SECRET: ${{ secrets.AUTH_EVENT_INGEST_SECRET }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - uses: supabase/setup-cli@v1
      - run: npm ci
      - run: npm run check:edge
      - run: npm test
      - name: Validate deployment inputs without displaying secrets
        run: |
          set -euo pipefail
          required=(
            SUPABASE_ACCESS_TOKEN SUPABASE_PROJECT_REF SUPABASE_DB_PASSWORD SUPABASE_URL SUPABASE_ANON_KEY
            SUPABASE_SERVICE_ROLE_KEY ALLOWED_ORIGINS APP_REDIRECT_URL
            SENSITIVE_DATA_ENCRYPTION_KEY SENSITIVE_DATA_LOOKUP_KEY AUTH_EVENT_INGEST_SECRET
          )
          for key in "${required[@]}"; do
            test -n "${!key}" || { echo "::error::Missing GitHub Environment secret: ${key}"; exit 1; }
          done
          [[ "$SUPABASE_URL" =~ ^https:// ]] || { echo "::error::SUPABASE_URL must use HTTPS."; exit 1; }
          [[ "$APP_REDIRECT_URL" =~ ^https:// ]] || { echo "::error::APP_REDIRECT_URL must use HTTPS."; exit 1; }
          [[ "$ALLOWED_ORIGINS" != *"*"* ]] || { echo "::error::ALLOWED_ORIGINS must not contain a wildcard."; exit 1; }
          [[ "$SENSITIVE_DATA_ENCRYPTION_KEY" =~ ^[A-Za-z0-9_-]{43,44}$ ]] || { echo "::error::SENSITIVE_DATA_ENCRYPTION_KEY must be a 32-byte base64url value."; exit 1; }
          [[ "$SENSITIVE_DATA_LOOKUP_KEY" =~ ^[A-Za-z0-9_-]{43,44}$ ]] || { echo "::error::SENSITIVE_DATA_LOOKUP_KEY must be a distinct 32-byte base64url value."; exit 1; }
          [[ "$SENSITIVE_DATA_ENCRYPTION_KEY" != "$SENSITIVE_DATA_LOOKUP_KEY" ]] || { echo "::error::Encryption and lookup keys must differ."; exit 1; }
          test "${#AUTH_EVENT_INGEST_SECRET}" -ge 32 || { echo "::error::AUTH_EVENT_INGEST_SECRET is too short."; exit 1; }
      - name: Apply schema, send runtime secrets, and deploy Edge Functions
        run: |
          set -euo pipefail
          secret_file="$(mktemp)"
          trap 'rm -f "$secret_file"' EXIT
          cat > "$secret_file" <<EOF
          SUPABASE_URL=${SUPABASE_URL}
          SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
          SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
          ALLOWED_ORIGINS=${ALLOWED_ORIGINS}
          APP_REDIRECT_URL=${APP_REDIRECT_URL}
          SENSITIVE_DATA_ENCRYPTION_KEY=${SENSITIVE_DATA_ENCRYPTION_KEY}
          SENSITIVE_DATA_LOOKUP_KEY=${SENSITIVE_DATA_LOOKUP_KEY}
          AUTH_EVENT_INGEST_SECRET=${AUTH_EVENT_INGEST_SECRET}
          EOF
          supabase link --project-ref "$SUPABASE_PROJECT_REF"
          supabase db push
          supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" --env-file "$secret_file"
          bash scripts/deploy-functions.sh
```

أنشئ GitHub Environments باسم `staging` و`production` ثم ضع فيها الأسرار المطلوبة. `SUPABASE_DB_PASSWORD` هو كلمة مرور قاعدة بيانات المشروع وهي مطلوبة ليعمل `supabase link`/`supabase db push` في بيئة CI غير التفاعلية. لا تضف مفاتيح Service Role أو AES/HMAC إلى workflow Pages أو إلى أسماء تبدأ بـ `VITE_`.
