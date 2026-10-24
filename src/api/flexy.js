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

export const capabilities = () => call('capabilities', { method: 'GET' })
export const validate = (phone, amount, distributorAccount) => call('validate', {
  method: 'POST',
  body: { operation_key: 'mobilis.arsselli.ordinary.630', phone, amount, distributor_account: distributorAccount }
})
