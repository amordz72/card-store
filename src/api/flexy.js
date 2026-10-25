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
  const { data, error } = await supabase.functions.invoke('flexy-api/v1/owner/' + path, init)
  if (!error) return { status: 200, body: data }
  const res = error.context
  if (res && typeof res.json === 'function') {
    let body = null
    try { body = await res.json() } catch { body = null }
    return { status: res.status, body }
  }
  return { status: 0, body: { ok: false, error: error.message || 'NETWORK' } }
}

export const ownerPreflight = (phone, amount) => owner('630/preflight', { method: 'POST', body: { phone, amount } })
// simUuid: the SIM Flexy Core chose at «تحقق»; the send is refused if its choice changed since.
export const ownerSend = (phone, amount, distributorAccount, idempotencyKey, simUuid) => owner('630/send', {
  method: 'POST',
  body: { phone, amount, distributor_account: distributorAccount, idempotency_key: idempotencyKey, ...(simUuid ? { sim_uuid: simUuid } : {}) }
})
export const ownerStatus = (idempotencyKey) => owner('630/' + encodeURIComponent(idempotencyKey), { method: 'GET' })
// Offers from the owner's page: the same flow as the shops', under the owner's switch, no wallet.
export const ownerOffers = (phone) => owner('offers/lookup', { method: 'POST', body: { phone } })
export const ownerOfferSend = (phone, offer, idempotencyKey) => owner('665/send', { method: 'POST', body: { phone, offer, idempotency_key: idempotencyKey } })
export const ownerOfferStatus = (idempotencyKey) => owner('665/' + encodeURIComponent(idempotencyKey), { method: 'GET' })
// The money switch, kept in Flexy Core (owner only). Off = every send refuses.
export const ownerSwitch = () => owner('settings', { method: 'GET' })
export const setOwnerSwitch = (on) => owner('settings', { method: 'POST', body: { send_enabled: on } })
// The shops' switch in Flexy Core (apps.630.send_enabled), read with ownerSwitch().
export const setAppsSwitch = (on) => owner('settings', { method: 'POST', body: { apps_send_enabled: on } })

export const capabilities = () => call('capabilities', { method: 'GET' })
export const validate = (phone, amount, distributorAccount) => call('validate', {
  method: 'POST',
  body: { operation_key: 'mobilis.arsselli.ordinary.630', phone, amount, distributor_account: distributorAccount }
})
