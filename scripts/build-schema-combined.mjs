// Generates supabase/scripts/schema_combined.sql from supabase/migrations/*.sql (in order).
// Purpose: a browser-only setup path. Users who cannot run the Supabase CLI can paste this
// single file into the Supabase Dashboard SQL Editor to create the whole schema atomically.
// The source of truth remains supabase/migrations/. Run `node scripts/build-schema-combined.mjs`
// after adding or editing migrations to keep the combined file in sync (a test enforces this).
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const MIGRATIONS_DIR = join(root, 'supabase', 'migrations')
const OUT_FILE = join(root, 'supabase', 'scripts', 'schema_combined.sql')

const HEADER = `-- ============================================================================
-- حماية | المخطط الكامل (كل migrations مدموجة بالترتيب) — لطريقة المتصفح فقط
-- ============================================================================
-- هذا الملف مُولَّد تلقائيًا من supabase/migrations/*.sql بالترتيب. المصدر المرجعي
-- هو مجلد migrations؛ لا تعدّل هذا الملف يدويًا. لإعادة توليده:
--   node scripts/build-schema-combined.mjs
--
-- الاستخدام (من المتصفح فقط، بدون تيرمينال):
--   1) افتح Supabase Dashboard → مشروعك → SQL Editor.
--   2) الصق محتوى هذا الملف كاملًا ثم Run.
--   3) يُنفَّذ الكل داخل معاملة واحدة (إما نجح كل شيء أو لم يُطبَّق شيء).
--   4) ملاحظة: هذه الطريقة لا تسجّل الملفات في supabase_migrations.schema_migrations.
--      عند استخدام CLI لاحقًا راجع قسم migration repair في docs-source/RUNBOOK_AR.md.
-- ============================================================================
`

export function buildCombined() {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((name) => name.endsWith('.sql'))
    .sort()
  const sections = files.map((name) => {
    const body = readFileSync(join(MIGRATIONS_DIR, name), 'utf8').replace(/\s+$/, '')
    return `-- ----------------------------------------------------------------------------\n-- ${name}\n-- ----------------------------------------------------------------------------\n${body}`
  })
  return `${HEADER}\nbegin;\n\n${sections.join('\n\n')}\n\ncommit;\n`
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  writeFileSync(OUT_FILE, buildCombined())
  console.log(`Wrote ${OUT_FILE}`)
}
