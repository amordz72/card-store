import { rpc } from './rpc'

// Customer API: token-based, independent of the admin's Supabase session.

export async function login (phone, password) {
  const rows = await rpc('store_login', { p_phone: phone, p_password: password })
  // No row = wrong phone/password, locked or inactive (one generic answer by design)
  return rows && rows[0] ? rows[0] : null
}

export const logout = (token) => rpc('store_logout', { p_token: token })

export async function me (token) {
  const rows = await rpc('store_me', { p_token: token })
  return rows[0]
}

export const catalog = (token) => rpc('store_catalog_v2', { p_token: token })
export const banners = (token) => rpc('store_banners', { p_token: token })
export const myPrices = (token) => rpc('store_my_prices', { p_token: token })

export async function buy (token, productId, qty, requestId) {
  const rows = await rpc('store_buy', { p_token: token, p_product_id: productId, p_qty: qty, p_request_id: requestId })
  return rows[0]
}

export const orders = (token, f) => rpc('store_orders', {
  p_token: token,
  p_category: f.category || null,
  p_from: f.from || null,
  p_to: f.to || null,
  p_query: f.query || null,
  p_limit: f.limit,
  p_offset: f.offset
})

// v2 adds code_id and the report state of each card (v1.20)
export const orderCodes = (token, orderId) => rpc('store_order_codes_v2', { p_token: token, p_order_id: orderId })
// «مساعدة»: report a card that did not work. reason: 'used' | 'not_found' | 'rejected' | 'other'
export const reportCode = (token, codeId, reason, note) =>
  rpc('store_report_code', { p_token: token, p_code_id: codeId, p_reason: reason, p_note: note || null })
export const myReports = (token) => rpc('store_my_reports', { p_token: token })
export const entries = (token, limit, offset) => rpc('store_entries', { p_token: token, p_limit: limit, p_offset: offset })
// «التحويلات»: wallet movements that are not purchases. kind: null | 'debt' | 'cash' | 'pay' | 'self' (with its refunds)
export const transfers = (token, f) => rpc('store_transfers', {
  p_token: token, p_kind: f.kind || null, p_from: f.from || null, p_to: f.to || null, p_limit: f.limit, p_offset: f.offset
})

export async function selfTopup (token, amount, requestId) {
  const rows = await rpc('store_self_topup', { p_token: token, p_amount: amount, p_request_id: requestId })
  return rows[0]
}

export const changePassword = (token, oldPassword, newPassword) =>
  rpc('store_change_password', { p_token: token, p_old: oldPassword, p_new: newPassword })

// Device lock PIN (the fingerprint never reaches the server)
export const lockStatus = (token) => rpc('store_lock_status', { p_token: token })
export const setPin = (token, pin) => rpc('store_set_pin', { p_token: token, p_pin: pin })
export const checkPin = (token, pin) => rpc('store_check_pin', { p_token: token, p_pin: pin })
export const lockOff = (token) => rpc('store_lock_off', { p_token: token })

// IDOOM top-up (v1.23): only for customers the owner enabled; the card is paid from the balance at once
export async function idoomStatus (token) {
  const rows = await rpc('store_idoom_status', { p_token: token })
  return rows?.[0] || { enabled: false, phone_online: false }
}
export async function idoomCreate (token, productId, line, requestId) {
  const rows = await rpc('store_idoom_create', { p_token: token, p_product_id: productId, p_line: line, p_request_id: requestId })
  return rows?.[0] || null
}
export const idoomJobs = (token, limit, offset) => rpc('store_idoom_jobs', { p_token: token, p_limit: limit, p_offset: offset })
export const idoomCancel = (token, jobId) => rpc('store_idoom_cancel', { p_token: token, p_job_id: jobId })
export async function idoomLineInfo (token, line) {
  const rows = await rpc('store_idoom_line_info', { p_token: token, p_line: line })
  return rows?.[0] || null
}
