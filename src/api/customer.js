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

export const catalog = (token) => rpc('store_catalog', { p_token: token })
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

export const orderCodes = (token, orderId) => rpc('store_order_codes', { p_token: token, p_order_id: orderId })
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
