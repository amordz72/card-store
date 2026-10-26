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

// One press, no «تحقق» (owner 2026-10-25): Flexy Core chooses the SIM and account at send time.
// 409 STATION_NOT_READY with refresh.state 'waiting' = nothing created, a 632 is on its way.
export const ownerSend = (phone, amount, idempotencyKey) => owner('630/send', {
  method: 'POST', body: { phone, amount, idempotency_key: idempotencyKey }
})
export const ownerStatus = (idempotencyKey) => owner('630/' + encodeURIComponent(idempotencyKey), { method: 'GET' })
// Offers from the owner's page: the same flow as the shops', under the owner's switch, no wallet.
// retry: «أعد المحاولة» after a discovery that ended; otherwise a running one is followed (Flexy Core 0030)
// via 'phone': «أرسل من هاتفي», the owner's admin phone (Flexy Core 0033), his choice only
export const ownerOffers = (phone, retry = false, via = null) =>
  owner('offers/lookup', { method: 'POST', body: { phone, ...(retry ? { retry: true } : {}), ...(via ? { via } : {}) } })
export const ownerOfferSend = (phone, offer, idempotencyKey, via = null) =>
  owner('665/send', { method: 'POST', body: { phone, offer, idempotency_key: idempotencyKey, ...(via ? { via } : {}) } })
// The admin phone: linked phones and their SIM, and a phone app waiting for approval; approve one
export const ownerPhone = () => owner('phone', { method: 'GET' })
export const approvePhone = (stationUuid, label) => owner('phone', { method: 'POST', body: { approve: stationUuid, label } })
export const ownerOfferStatus = (idempotencyKey) => owner('665/' + encodeURIComponent(idempotencyKey), { method: 'GET' })
// «آخر العمليات» of the owner's page: newest 630s and offers, older than `before` (created_at).
export const ownerOperations = (limit, before) =>
  owner('operations?limit=' + limit + (before ? '&before=' + encodeURIComponent(before) : ''), { method: 'GET' })
// The money switch, kept in Flexy Core (owner only). Off = every send refuses.
export const ownerSwitch = () => owner('settings', { method: 'GET' })
export const setOwnerSwitch = (on) => owner('settings', { method: 'POST', body: { send_enabled: on } })
// The shops' switch in Flexy Core (apps.630.send_enabled), read with ownerSwitch().
export const setAppsSwitch = (on) => owner('settings', { method: 'POST', body: { apps_send_enabled: on } })
// Stations and SIMs: computers → modems → SIM, each with Flexy Core's verdict (read only, owner only).
export const ownerDevices = () => owner('devices', { method: 'GET' })
// A SIM's PIN, name and note (owner only). The PIN is never sent back; fields left out are not changed.
export const saveSimSettings = (simUuid, fields) => owner('sims/settings', { method: 'POST', body: { sim_uuid: simUuid, ...fields } })
// An approved SIM's balance read once more: one balance code, no money (Flexy Core 0018).
export const readSimBalance = (simUuid) => owner('sims/read-balance', { method: 'POST', body: { sim_uuid: simUuid } })
// Agent updates: what each computer runs and what main on GitHub holds, and its last request;
// ask one computer to pull main (its version as shown) or move gateway (its updater applies it
// and rolls back by itself); withdraw a request not yet taken.
export const ownerUpdates = () => owner('updates', { method: 'GET' })
export const requestUpdate = (stationUuid, kind, value) => owner('updates', {
  method: 'POST',
  body: kind === 'release' ? { station_uuid: stationUuid, kind, release: value } : { station_uuid: stationUuid, kind, config: value }
})
export const cancelUpdate = (deploymentId) => owner('updates', { method: 'POST', body: { cancel: deploymentId } })

export const capabilities = () => call('capabilities', { method: 'GET' })
export const validate = (phone, amount, distributorAccount) => call('validate', {
  method: 'POST',
  body: { operation_key: 'mobilis.arsselli.ordinary.630', phone, amount, distributor_account: distributorAccount }
})
