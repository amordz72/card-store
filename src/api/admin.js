import { rpc } from './rpc'

// Admin API: requires a Supabase Auth session; the database also checks store.admins.

export const isAdmin = () => rpc('store_admin_is_admin')

export const customers = () => rpc('store_admin_customers')
export const createCustomer = (name, phone, password) =>
  rpc('store_admin_create_customer', { p_name: name, p_phone: phone, p_password: password })
export const updateCustomer = (id, patch) => rpc('store_admin_update_customer', {
  p_customer_id: id,
  p_name: patch.name ?? null,
  p_phone: patch.phone ?? null,
  p_debt_limit: patch.debtLimit ?? null,
  p_self_topup: patch.selfTopup ?? null,
  p_active: patch.active ?? null
})
export const setPassword = (id, password) => rpc('store_admin_set_password', { p_customer_id: id, p_password: password })
export const revokeSessions = (id) => rpc('store_admin_revoke_sessions', { p_customer_id: id })

export async function transfer (customerId, kind, amount, note, requestId) {
  const rows = await rpc('store_admin_transfer', {
    p_customer_id: customerId, p_kind: kind, p_amount: amount, p_note: note || null, p_request_id: requestId
  })
  return rows[0]
}

export async function reverse (entryId, note, requestId) {
  const rows = await rpc('store_admin_reverse', { p_entry_id: entryId, p_note: note || null, p_request_id: requestId })
  return rows[0]
}

export const entries = (f) => rpc('store_admin_entries', {
  p_customer_id: f.customerId || null,
  p_kind: f.kind || null,
  p_from: f.from || null,
  p_to: f.to || null,
  p_limit: f.limit,
  p_offset: f.offset,
  p_scope: f.scope || null
})

export const orders = (f) => rpc('store_admin_orders', {
  p_customer_id: f.customerId || null,
  p_category: f.category || null,
  p_from: f.from || null,
  p_to: f.to || null,
  p_query: f.query || null,
  p_limit: f.limit,
  p_offset: f.offset,
  p_scope: f.scope || null
})

export const orderCodes = (orderId) => rpc('store_admin_order_codes', { p_order_id: orderId })
export const revealCode = (codeId) => rpc('store_admin_reveal_code', { p_code_id: codeId })

export async function addCodes (productId, supplierId, cost, lines) {
  const rows = await rpc('store_admin_add_codes', {
    p_product_id: productId, p_supplier_id: supplierId || null, p_cost: cost || null, p_lines: lines
  })
  return rows[0]
}

export const stock = () => rpc('store_admin_stock')
export const brands = () => rpc('store_admin_brands')
export const saveBrand = (b) => rpc('store_admin_save_brand', {
  p_brand_id: b.id ?? null, p_name: b.name ?? null, p_category: b.category ?? null, p_sort: b.sort ?? null, p_active: b.active ?? null
})
export const saveProduct = (p) => rpc('store_admin_save_product', {
  p_product_id: p.id ?? null, p_brand_id: p.brandId ?? null, p_name: p.name ?? null,
  p_base_price: p.basePrice ?? null, p_sort: p.sort ?? null, p_active: p.active ?? null
})
export const suppliers = () => rpc('store_admin_suppliers')
export const addSupplier = (name) => rpc('store_admin_add_supplier', { p_name: name })
export const rates = (category) => rpc('store_admin_rates', { p_category: category || null })
export const setRate = (customerId, productId, pct) =>
  rpc('store_admin_set_rate', { p_customer_id: customerId, p_product_id: productId, p_pct: pct })
export const getAnnouncement = () => rpc('store_admin_get_announcement')
export const setAnnouncement = (text) => rpc('store_admin_set_announcement', { p_text: text })
export const reconcile = () => rpc('store_admin_reconcile')

// Shop account («حساب المحل»): the owner's own wallet
export const shopCatalog = () => rpc('store_admin_shop_catalog')
export async function shopBuy (productId, qty, requestId) {
  const rows = await rpc('store_admin_shop_buy', { p_product_id: productId, p_qty: qty, p_request_id: requestId })
  return rows[0]
}
export async function shopTopup (amount, note, requestId) {
  const rows = await rpc('store_admin_shop_topup', { p_amount: amount, p_note: note || null, p_request_id: requestId })
  return rows[0]
}
export const shopSummary = (from, to) => rpc('store_admin_shop_summary', { p_from: from || null, p_to: to || null })
