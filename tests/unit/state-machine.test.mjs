import test from 'node:test'
import assert from 'node:assert/strict'

const allowed = new Set([
  'registered:available', 'registered:sold', 'registered:in_repair', 'registered:flagged', 'registered:archived',
  'available:sold', 'available:in_repair', 'available:flagged', 'available:blocked', 'available:archived',
  'sold:in_repair', 'sold:formatted', 'sold:flagged', 'sold:blocked',
  'in_repair:formatted', 'in_repair:sold', 'in_repair:flagged', 'in_repair:blocked',
  'formatted:sold', 'formatted:in_repair', 'formatted:flagged', 'formatted:blocked',
  'flagged:stolen', 'flagged:recovered', 'flagged:available', 'flagged:blocked',
  'stolen:recovered', 'stolen:blocked', 'recovered:available', 'recovered:in_repair', 'recovered:archived', 'recovered:flagged',
  'blocked:recovered', 'blocked:archived', 'blocked:flagged',
])
const canTransition = (from, to) => allowed.has(`${from}:${to}`)

test('permits the operational lifecycle edges used by sale, repair, report and recovery', () => {
  assert.equal(canTransition('registered', 'sold'), true)
  assert.equal(canTransition('sold', 'in_repair'), true)
  assert.equal(canTransition('in_repair', 'formatted'), true)
  assert.equal(canTransition('formatted', 'flagged'), true)
  assert.equal(canTransition('flagged', 'stolen'), true)
  assert.equal(canTransition('stolen', 'recovered'), true)
})

test('rejects arbitrary transitions that could clear a reported device', () => {
  assert.equal(canTransition('stolen', 'available'), false)
  assert.equal(canTransition('blocked', 'sold'), false)
  assert.equal(canTransition('archived', 'available'), false)
  assert.equal(canTransition('flagged', 'sold'), false)
})
