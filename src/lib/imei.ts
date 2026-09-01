export function normalizeImei(value: string): string {
  return value.trim()
}

export function isValidImei(value: string): boolean {
  const imei = normalizeImei(value)
  if (!/^\d{15}$/.test(imei)) return false
  let sum = 0
  let shouldDouble = false
  for (let index = imei.length - 1; index >= 0; index -= 1) {
    let digit = Number(imei[index])
    if (shouldDouble) {
      digit *= 2
      if (digit > 9) digit -= 9
    }
    sum += digit
    shouldDouble = !shouldDouble
  }
  return sum % 10 === 0
}

export const deviceStatusLabel: Record<string, string> = {
  registered: 'مسجل', available: 'متاح', sold: 'مباع', in_repair: 'قيد الصيانة', formatted: 'تمت الفرمتة',
  flagged: 'تحت التنبيه', stolen: 'مسروق', recovered: 'مسترد', blocked: 'محظور', archived: 'مؤرشف',
}

export const reportStatusLabel: Record<string, string> = {
  draft: 'مسودة', submitted: 'مقدّم', under_review: 'قيد المراجعة', verified: 'تم التحقق', active: 'نشط',
  assigned: 'مُحال', recovered: 'تم الاسترداد', closed: 'مغلق', rejected: 'مرفوض', cancelled: 'ملغى',
}
