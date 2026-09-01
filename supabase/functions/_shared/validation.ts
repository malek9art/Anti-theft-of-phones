export function normalizeImei(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

/** 15-digit IMEI with its Luhn check digit. This deliberately does more than a regex match. */
export function isValidImei(value: unknown): value is string {
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

export function text(value: unknown, label: string, min = 1, max = 1000): string {
  if (typeof value !== 'string') throw new Error(`INVALID_${label}`)
  const normalized = value.trim()
  if (normalized.length < min || normalized.length > max) throw new Error(`INVALID_${label}`)
  return normalized
}

export function optionalText(value: unknown, label: string, max = 1000): string | null {
  if (value === undefined || value === null || value === '') return null
  return text(value, label, 1, max)
}

export function uuid(value: unknown, label: string): string {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error(`INVALID_${label}`)
  }
  return value
}

export function enumValue<T extends readonly string[]>(value: unknown, values: T, label: string): T[number] {
  if (typeof value !== 'string' || !values.includes(value)) throw new Error(`INVALID_${label}`)
  return value as T[number]
}

export function numberInRange(value: unknown, label: string, min: number, max: number): number | null {
  if (value === null || value === undefined || value === '') return null
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) throw new Error(`INVALID_${label}`)
  return value
}

export function optionalUuid(value: unknown, label: string): string | null {
  if (value === null || value === undefined || value === '') return null
  return uuid(value, label)
}
