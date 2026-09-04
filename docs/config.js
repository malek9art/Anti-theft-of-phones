// ============================================================================
// حماية | إعداد الاتصال العام (قيم المتصفح الآمنة فقط)
// ============================================================================
// عند النشر عبر الفرع (GitHub Pages → Deploy from a branch) لا يمكن حقن أسرار
// GitHub، لذلك تُقرأ القيمتان من هذا الملف وقت التشغيل.
//
//   1) لِتغيير مشروع Supabase لاحقًا: افتح  docs/config.js  في مستودع GitHub
//      واضغط أيقونة التعديل ثم غيّر القيمتين و Commit.
//   2) لا تضع هنا أبدًا Service Role Key أو مفاتيح التشفير — هاتان القيمتان
//      عامّتان بطبيعتهما (Anon/Publishable key).
//
// القيمتان أدناه معبأتان مسبقًا لمشروع Supabase الحالي، ويمكن تعديلهما وقت
// التشغيل دون إعادة بناء الموقع. عند البناء عبر GitHub Actions تبقى الحقول فارغة،
// فيقرأ التطبيق VITE_SUPABASE_URL و VITE_SUPABASE_ANON_KEY من بيئة البناء.
// ============================================================================
window.__HIMAYA_CONFIG__ = {
  SUPABASE_URL: "https://chgauqwrfcdjlpmrpjda.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNoZ2F1cXdyZmNkamxwbXJwamRhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyOTExODEsImV4cCI6MjEwMzg2NzE4MX0.FqkoPQU7JqCl0-QWiquVK6UpFoOT0B010ySVlT3x0y0",
};
