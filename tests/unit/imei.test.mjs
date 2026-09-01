import test from 'node:test'
import assert from 'node:assert/strict'

function isValidImei(value) {
  const imei = typeof value === 'string' ? value.trim() : ''
  if (!/^\d{15}$/.test(imei)) return false
  let sum = 0
  let shouldDouble = false
  for (let index = imei.length - 1; index >= 0; index -= 1) {
    let digit = Number(imei[index])
    if (shouldDouble) { digit *= 2; if (digit > 9) digit -= 9 }
    sum += digit
    shouldDouble = !shouldDouble
  }
  return sum % 10 === 0
}

test('accepts a valid 15-digit IMEI using the Luhn check digit', () => {
  assert.equal(isValidImei('490154203237518'), true)
  assert.equal(isValidImei(' 490154203237518 '), true)
  assert.equal(isValidImei('356938035643809'), true)
})

test('rejects invalid lengths, characters, and a bad check digit', () => {
  assert.equal(isValidImei('490154203237519'), false)
  assert.equal(isValidImei('49015420323751'), false)
  assert.equal(isValidImei('4901542032375180'), false)
  assert.equal(isValidImei('49015420323751x'), false)
  assert.equal(isValidImei(''), false)
  assert.equal(isValidImei(null), false)
})
