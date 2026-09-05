// ============================================================================
// فحص توازن الأقواس في ملفات SQL (schema_combined.sql وغيره)
// ============================================================================
// Postgres غير متاح دائمًا في بيئة التشغيل، لذا يتحقق هذا الفاحص بشكل ثابت من أن
// كل قوس مفتوح له قوس مغلق مطابق، مع تجاهل التعليقات والنصوص المقتبسة والمعرّفات
// المزدوجة الاقتباس. يُمسح داخل أجسام الدوال ($$ ... $$) لأن أخطاء الأقواس تقع
// غالبًا داخل PL/pgSQL. يلتقط أخطاء مثل:
//   ERROR: 42601: mismatched parentheses at or near ")"
//
// الاستخدام: node scripts/check-sql-balance.mjs [ملف1 [ملف2 ...]]
// بدون وسائط يفحص supabase/scripts/schema_combined.sql
// ============================================================================

import { readFileSync, existsSync } from 'node:fs'

const defaults = ['supabase/scripts/schema_combined.sql']
const files = process.argv.slice(2).length ? process.argv.slice(2) : defaults

function scanSql(text) {
  const problems = []
  let depth = 0
  let line = 1
  let col = 1
  let i = 0
  const n = text.length

  const advance = (count = 1) => {
    for (let k = 0; k < count; k += 1) {
      if (text[i] === '\n') { line += 1; col = 1 } else { col += 1 }
      i += 1
    }
  }

  while (i < n) {
    const c = text[i]
    const next = text[i + 1]

    // تعليق سطر
    if (c === '-' && next === '-') {
      while (i < n && text[i] !== '\n') advance()
      continue
    }

    // تعليق كتلة (متداخل كما في Postgres)
    if (c === '/' && next === '*') {
      let nesting = 1
      advance(2)
      while (i < n && nesting > 0) {
        if (text[i] === '/' && text[i + 1] === '*') { nesting += 1; advance(2) }
        else if (text[i] === '*' && text[i + 1] === '/') { nesting -= 1; advance(2) }
        else advance()
      }
      continue
    }

    // نص مقتبس بعلامة مفردة (مع هروب '' أو \')
    if (c === "'") {
      advance()
      while (i < n) {
        if (text[i] === '\\' && text[i + 1] !== undefined) { advance(2); continue }
        if (text[i] === "'") {
          if (text[i + 1] === "'") { advance(2); continue }
          advance()
          break
        }
        advance()
      }
      continue
    }

    // معرّف مقتبس بعلامة مزدوجة (مع هروب "")
    if (c === '"') {
      advance()
      while (i < n) {
        if (text[i] === '"') {
          if (text[i + 1] === '"') { advance(2); continue }
          advance()
          break
        }
        advance()
      }
      continue
    }

    if (c === '(') {
      depth += 1
      advance()
      continue
    }

    if (c === ')') {
      depth -= 1
      if (depth < 0) {
        problems.push(`line ${line}: unmatched closing ')' (depth went negative)`)
      }
      advance()
      continue
    }

    advance()
  }

  if (depth !== 0) {
    problems.push(`end of file: ${depth} unclosed '(' (depth ${depth} at EOF)`)
  }

  return problems
}

let failed = false
for (const file of files) {
  if (!existsSync(file)) {
    console.error(`Missing file: ${file}`)
    failed = true
    continue
  }
  const problems = scanSql(readFileSync(file, 'utf8'))
  if (problems.length) {
    failed = true
    console.error(`SQL paren imbalance in ${file}:`)
    for (const p of problems) console.error(`  - ${p}`)
  } else {
    console.log(`OK  ${file} (parentheses balanced)`)
  }
}

process.exit(failed ? 1 : 0)
