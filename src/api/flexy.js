import { supabase } from 'boot/supabase'

// Flexy Core, read-only test (admin only). Goes through the Edge Function
// store-flexy, which holds the Flexy key server-side. Nothing is sent to any
// network from here: no money, no USSD.
// Returns { status, body } as answered, so the page can show it unchanged.
async function call (path, init) {
  const { data, error } = await supabase.functions.invoke('store-flexy/' + path, init)
  if (!error) return { status: 200, body: data }
  const res = error.context
  if (res && typeof res.json === 'function') {
    let body = null
    try { body = await res.json() } catch { body = null }
    return { status: res.status, body }
  }
  return { status: 0, body: { ok: false, error: error.message || 'NETWORK' } }
}

// Owner console (real money): straight to flexy-api with the owner's own session.
// Station Connect re-checks that this session is the shop admin. No key in the browser.
async function owner (path, init) {
  const { data, error } = await supabase.functions.invoke('flexy-api/v1/owner/630/' + path, init)
  if (!error) return { status: 200, body: data }
  const res = error.context
  if (res && typeof res.json === 'function') {
    let body = null
    try { body = await res.json() } catch { body = null }
    return { status: res.status, body }
  }
  return { status: 0, body: { ok: false, error: error.message || 'NETWORK' } }
}

export const ownerPreflight = (phone, amount) => owner('preflight', { method: 'POST', body: { phone, amount } })
export const ownerSend = (phone, amount, distributorAccount, idempotencyKey) => owner('send', {
  method: 'POST',
  body: { phone, amount, distributor_account: distributorAccount, idempotency_key: idempotencyKey }
})
export const ownerStatus = (idempotencyKey) => owner(encodeURIComponent(idempotencyKey), { method: 'GET' })

export const capabilities = () => call('capabilities', { method: 'GET' })
export const validate = (phone, amount, distributorAccount) => call('validate', {
  method: 'POST',
  body: { operation_key: 'mobilis.arsselli.ordinary.630', phone, amount, distributor_account: distributorAccount }
})
