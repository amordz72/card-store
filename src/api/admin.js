import { supabase } from 'boot/supabase'
import { rpc } from './rpc'
import { StoreError } from './errors'
import { normPhone } from './format'

// Admin API: requires a Supabase Auth session; the database also checks store.admins.

export const isAdmin = () => rpc('store_admin_is_admin')

export const customers = () => rpc('store_admin_customers')
export const createCustomer = (name, phone, password) => createCustomerRaw(name, normPhone(phone), password)
const createCustomerRaw = (name, phone, password) =>
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

// v1.37: «العمليات» as one list, cards and the shops' Flexy together (type: phone|net|game|flexy|offer)
export const ops = (f) => rpc('store_admin_ops', {
  p_scope: f.scope || null,
  p_customer_id: f.customerId || null,
  p_type: f.type || null,
  p_from: f.from || null,
  p_to: f.to || null,
  p_query: f.query || null,
  p_limit: f.limit,
  p_offset: f.offset
})

// v1.38: the Flexy Core keys of shop Flexy rows, to read the SIM that ran each (owner only)
export const flexyKeys = (jobIds) => rpc('store_admin_flexy_keys', { p_job_ids: jobIds })

export const orderCodes = (orderId) => rpc('store_admin_order_codes', { p_order_id: orderId })

// Card reports from customers (v1.20). status: null (all) | 'open' | 'accepted' | 'rejected'
export const reports = (status) => rpc('store_admin_reports', { p_status: status || null })
export const resolveReport = (reportId, status, note) =>
  rpc('store_admin_resolve_report', { p_report_id: reportId, p_status: status, p_note: note || null })
export const openReportsCount = () => rpc('store_admin_open_reports_count')
// v1.27: the owner marks the shop's own cards only; reads whether any buyer copied (never the code)
export const markCopied = (codeId) => rpc('store_admin_mark_copied', { p_code_id: codeId })
export const orderCopies = (orderId) => rpc('store_admin_order_copies', { p_order_id: orderId })
export const revealCode = (codeId) => rpc('store_admin_reveal_code', { p_code_id: codeId })

export async function addCodes (productId, supplierId, cost, lines) {
  const rows = await rpc('store_admin_add_codes', {
    p_product_id: productId, p_supplier_id: supplierId || null, p_cost: cost || null, p_lines: lines
  })
  return rows[0]
}

export const stock = () => rpc('store_admin_stock_v2')
// v1.57: each supplier's reader of its message (where the codes start, their length)
export const supplierReaders = () => rpc('store_admin_supplier_readers')
export const setSupplierReader = (supplierId, reader) => rpc('store_admin_set_supplier_reader', { p_supplier_id: supplierId, p_reader: reader })
// v1.53: cards about to run out (at their pace of the last 7 days), and the owner's two numbers
export const lowStock = () => rpc('store_admin_low_stock')
// v1.54: what to buy (out / buy / trial / idle), and the owner's three numbers
export const buyList = () => rpc('store_admin_buy_list')
export const setBuyList = (cover, trial, idle) => rpc('store_admin_set_buy_list', { p_cover: cover, p_trial: trial, p_idle: idle })
export const setLowStock = (days, count) => rpc('store_admin_set_low_stock', { p_days: days, p_count: count })

// Batches: freeze stops a code from being sold (reversible); void removes it
// from stock for good, keeping it in history. Sold codes are never touched.
// v2 (v1.28): «suspect» is its own count/flag; «frozen» no longer includes it
export const batches = (productId, limit, offset) =>
  rpc('store_admin_batches_v2', { p_product_id: productId || null, p_limit: limit, p_offset: offset })
// v1.48: a wrong purchase price corrected in place (what the shops paid never changes here)
export const batchCostPreview = (batchId, cost) => rpc('store_admin_batch_cost_preview', { p_batch_id: batchId, p_cost: cost })
export const batchCostSet = (batchId, cost) => rpc('store_admin_batch_cost_set', { p_batch_id: batchId, p_cost: cost })
export const batchCostChanges = () => rpc('store_admin_batch_cost_changes')
// v1.58: the batch's supplier and/or card (null keeps it); the card only when nothing of it was sold or used
export const batchEdit = (batchId, supplierId, productId) => rpc('store_admin_batch_edit', { p_batch_id: batchId, p_supplier_id: supplierId, p_product_id: productId })
export const batchChanges = () => rpc('store_admin_batch_changes')
export const batchCodes = (batchId) => rpc('store_admin_batch_codes_v2', { p_batch_id: batchId })
export const freezeCodes = (codeIds, frozen) => rpc('store_admin_codes_freeze', { p_code_ids: codeIds, p_frozen: frozen })
export const voidCodes = (codeIds, reason) => rpc('store_admin_codes_void', { p_code_ids: codeIds, p_reason: reason })
// v1.28: a voided card never reached a buyer comes back as «مشكوك فيها» (owner only, used one by one)
export async function restoreBatch (batchId, lines, reason) {
  const rows = await rpc('store_admin_batch_restore', { p_batch_id: batchId, p_lines: lines, p_reason: reason })
  return rows[0]
}
// v1.29: one shop card did not work → void + its cost back to the shop. result: 'used' | 'not_found' | 'other'
export async function cardFailed (codeId, result, requestId) {
  const rows = await rpc('store_admin_card_failed', { p_code_id: codeId, p_result: result, p_note: null, p_request_id: requestId })
  return rows[0]
}
export const setSuspect = (codeIds, suspect) => rpc('store_admin_codes_set_suspect', { p_code_ids: codeIds, p_suspect: suspect })
export async function useSuspect (productId, requestId) {
  const rows = await rpc('store_admin_use_suspect', { p_product_id: productId, p_request_id: requestId })
  return rows[0]
}
export const brands = () => rpc('store_admin_brands_v2')
export const saveBrand = (b) => rpc('store_admin_save_brand', {
  p_brand_id: b.id ?? null, p_name: b.name ?? null, p_category: b.category ?? null, p_sort: b.sort ?? null, p_active: b.active ?? null
})
export const saveProduct = (p) => rpc('store_admin_save_product', {
  p_product_id: p.id ?? null, p_brand_id: p.brandId ?? null, p_name: p.name ?? null,
  p_base_price: p.basePrice ?? null, p_sort: p.sort ?? null, p_active: p.active ?? null
})
// Images (v1.19): kind 'brand' | 'product'; image null removes it
export const setImage = (kind, id, image) => rpc('store_admin_set_image', { p_kind: kind, p_id: id, p_image: image ?? null })

// Shrinks the picture on the phone (max 600px, webp) then uploads it to the public bucket; returns its URL
// maxSide: 600 for logos and cards, 1200 for home banners
export async function uploadImage (file, kind, id, maxSide = 600) {
  if (!/^image\/(png|jpeg|webp)$/.test(file.type)) throw new StoreError('INVALID_IMAGE')
  const bitmap = await createImageBitmap(file)
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * scale)
  canvas.height = Math.round(bitmap.height * scale)
  canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/webp', 0.85))
  if (!blob || blob.size > 1048576) throw new StoreError('IMAGE_TOO_BIG')
  const path = `${kind}/${id}-${Date.now()}.webp`
  const { error } = await supabase.storage.from('store-images').upload(path, blob, { contentType: 'image/webp' })
  if (error) throw new StoreError(/row-level security|Unauthorized/i.test(error.message) ? 'NOT_ADMIN' : 'NETWORK', error)
  return supabase.storage.from('store-images').getPublicUrl(path).data.publicUrl
}

export const suppliers = () => rpc('store_admin_suppliers')
export const addSupplier = (name) => rpc('store_admin_add_supplier', { p_name: name })
// Includes stopped cards (active = false) and the usual purchase cost
export const priceList = (category) => rpc('store_admin_price_list', { p_category: category || null })
export const setDefaultCost = (productId, cost) => rpc('store_admin_set_default_cost', { p_product_id: productId, p_cost: cost ?? null })
export const productCosts = () => rpc('store_admin_product_costs')
// mode: 'fixed' | 'amount' | 'pct' | 'share' | 'inherit' (customer only); customerId null = default row
export const setPrice = (customerId, productId, mode, value) =>
  rpc('store_admin_set_price', { p_customer_id: customerId, p_product_id: productId, p_mode: mode, p_value: value ?? null })
export const getAnnouncement = () => rpc('store_admin_get_announcement')
export const setAnnouncement = (text) => rpc('store_admin_set_announcement', { p_text: text })
export const reconcile = () => rpc('store_admin_reconcile')

// Shop account («حساب المحل»): the owner's own wallet
export const shopCatalog = () => rpc('store_admin_shop_catalog_v2')
export async function shopBuy (productId, qty, requestId) {
  const rows = await rpc('store_admin_shop_buy', { p_product_id: productId, p_qty: qty, p_request_id: requestId })
  return rows[0]
}
export const shopSplitOffers = () => rpc('store_admin_shop_split_offers')
export async function shopBuySplit (productId, qty, requestId) {
  const rows = await rpc('store_admin_shop_buy_split', { p_product_id: productId, p_qty: qty, p_request_id: requestId })
  return rows[0]
}
export async function shopTopup (amount, note, requestId) {
  const rows = await rpc('store_admin_shop_topup', { p_amount: amount, p_note: note || null, p_request_id: requestId })
  return rows[0]
}
export const shopSummary = (from, to) => rpc('store_admin_shop_summary', { p_from: from || null, p_to: to || null })

// Device lock PIN for the owner
export const lockStatus = () => rpc('store_admin_lock_status')
export const setPin = (pin) => rpc('store_admin_set_pin', { p_pin: pin })
export const checkPin = (pin) => rpc('store_admin_check_pin', { p_pin: pin })
export const lockOff = () => rpc('store_admin_lock_off')
// a customer who forgot his PIN, or asked for the lock to be off
export const customerLockOff = (customerId) => rpc('store_admin_customer_lock_off', { p_customer_id: customerId })

// IDOOM direct top-up through the Rech-Doom phone app (v1.11)
export async function idoomCreate (productId, line, requestId) {
  const rows = await rpc('store_admin_idoom_create', { p_product_id: productId, p_line: line, p_request_id: requestId })
  return rows[0]
}
export async function idoomLookup (line, requestId) {
  const rows = await rpc('store_admin_idoom_lookup', { p_line: line, p_request_id: requestId })
  return rows[0]
}
// v3 adds the customer who asked (null = the owner)
export const idoomJobs = (limit = 30) => rpc('store_admin_idoom_jobs_v3', { p_limit: limit })
// IDOOM top-up for customers (v1.23): per-customer switch, and customer jobs waiting for review (bell)
export const setIdoomTopup = (customerId, enabled) => rpc('store_admin_set_idoom_topup', { p_customer_id: customerId, p_enabled: enabled })
export const idoomTopupCustomers = () => rpc('store_admin_idoom_topup_customers')
export const idoomReviewCount = () => rpc('store_admin_idoom_review_count')
// A customer's job in review: done, or not done → full refund to the customer
export const idoomResolve = (jobId, done) => rpc('store_admin_idoom_resolve', { p_job_id: jobId, p_done: done })
// last known offer of a line, display only (v1.17)
export async function idoomLineInfo (line) {
  const rows = await rpc('store_admin_idoom_line_info', { p_line: line })
  return rows[0] || null
}
export const executors = () => rpc('store_admin_executors')
// v1.30: a disabled phone gets no job (refused while it has one in progress)
export const executorNewToken = (id) => rpc('store_admin_executor_new_token', { p_executor_id: id })
export const executorSetActive = (id, active) => rpc('store_admin_executor_set_active', { p_executor_id: id, p_active: active })
// v1.37: only a disabled phone; it leaves the list and its token stops for good (past jobs keep it)
export const executorDelete = (id) => rpc('store_admin_executor_delete', { p_executor_id: id })
export const idoomCancel = (jobId) => rpc('store_admin_idoom_cancel', { p_job_id: jobId })
export async function executorCreate (name) {
  const rows = await rpc('store_admin_executor_create', { p_name: name })
  return rows[0]
}

// Home image banners (v1.22). liveBanners = what the home page shows now (same rule as customers)
export const liveBanners = () => rpc('store_banners', { p_token: null })
export const banners = () => rpc('store_admin_banners')
export const saveBanner = (b) => rpc('store_admin_save_banner', {
  p_id: b.id || null,
  p_image: b.image,
  p_title: b.title || '',
  p_link_kind: b.linkKind,
  p_link: b.linkKind === 'none' ? null : b.link,
  p_starts_at: b.startsAt || null,
  p_ends_at: b.endsAt || null
})
export const setBannerActive = (id, active) => rpc('store_admin_set_banner_active', { p_id: id, p_active: active })
export const moveBanner = (id, dir) => rpc('store_admin_move_banner', { p_id: id, p_dir: dir })
export const removeBanner = (id) => rpc('store_admin_remove_banner', { p_id: id })

// Game top-up (v1.25): workers, cards topped up by player id, the top-up site link
export const setGameOperator = (customerId, enabled) => rpc('store_admin_set_game_operator', { p_customer_id: customerId, p_enabled: enabled })
export const gameOperators = () => rpc('store_admin_game_operators')
export const setPlayerTopup = (productId, enabled) => rpc('store_admin_set_player_topup', { p_product_id: productId, p_enabled: enabled })
export const playerTopupProducts = () => rpc('store_admin_player_topup_products')
// v1.49: orders by player id accepted any time (null = read only)
export const gameAlwaysOpen = (on = null) => rpc('store_admin_game_always_open', { p_on: on })
// v1.50: the owner orders a top-up FOR a customer (WhatsApp); his short balance becomes debt
export const gameOrderFor = (customerId, productId, playerId, requestId) =>
  rpc('store_admin_game_order', { p_customer_id: customerId, p_product_id: productId, p_player_id: playerId, p_request_id: requestId })
// v1.51: by amount, split into cards; and the owner's «يسمح بالتقسيم» per game
export const gameSplitPreviewFor = (customerId, brand, units) => rpc('store_admin_game_split_preview', { p_customer_id: customerId, p_brand: brand, p_units: units })
export const gameOrderUnitsFor = (customerId, brand, units, playerId, requestId) =>
  rpc('store_admin_game_order_units', { p_customer_id: customerId, p_brand: brand, p_units: units, p_player_id: playerId, p_request_id: requestId })
export const gameBrands = () => rpc('store_admin_game_brands')
export const setGameSplit = (brand, on) => rpc('store_admin_set_game_split', { p_brand: brand, p_on: on })
export const setGameUrl = (url) => rpc('store_admin_set_game_url', { p_url: url || null })

// Site links (v1.32): the shared official link, and extra sites allowed to call store-flexy
export const DEFAULT_OFFICIAL_SITE = 'https://amordz72.github.io/card-store/'
export async function siteLinks () {
  const rows = await rpc('store_site_links')
  const r = rows?.[0] || {}
  return { officialUrl: r.official_url || '', extraOrigins: r.extra_origins || [] }
}
export const setOfficialUrl = (url) => rpc('store_admin_set_official_url', { p_url: url || null })
export const setExtraOrigins = (origins) => rpc('store_admin_set_extra_origins', { p_origins: origins })

// Flexy for shops (v1.33): the owner's settings, per-shop rates («نسب المحلات»), the shops' operations and reviews
// v1.39: a rate per operator per shop (rate_630 = Mobilis, rate_630_djezzy, rate_630_ooredoo; null = closed for it)
export async function flexySettings () {
  const rows = await rpc('store_admin_flexy_settings_v2')
  return rows?.[0] || null
}
export const setFlexySettings = (open, rate630, rateOffer, max, rateDjezzy = null, rateOoredoo = null) =>
  rpc('store_admin_set_flexy_settings_v2', { p_open: open, p_rate_630: rate630, p_rate_offer: rateOffer, p_max: max, p_rate_630_djezzy: rateDjezzy, p_rate_630_ooredoo: rateOoredoo })
// v1.55 adds the Ooredoo / Djezzy offers' rates; before it, v3
export const flexyCustomers = () => rpc('store_admin_flexy_customers_v4').catch(() => rpc('store_admin_flexy_customers_v3'))
// v1.41: one change for a list of shops (the selection or one shop): { service, rate } | { service, block } | { enabled } | { max } | { role }
export const flexyBulk = (ids, { service = null, rate = null, block = null, enabled = null, max = null, role = null } = {}) =>
  rpc('store_admin_flexy_bulk', { p_ids: ids, p_service: service, p_rate: rate, p_block: block, p_enabled: enabled, p_max: max, p_role: role })
export const setCustomerFlexy = (customerId, { enabled = null, role = null, rate630 = null, rateOffer = null, max = null, rateDjezzy = null, rateOoredoo = null }) =>
  rpc('store_admin_set_customer_flexy_v2', { p_customer_id: customerId, p_enabled: enabled, p_role: role, p_rate_630: rate630, p_rate_offer: rateOffer, p_max: max, p_rate_630_djezzy: rateDjezzy, p_rate_630_ooredoo: rateOoredoo })
// v1.40: keeps the rate as the default and gives it to every enabled shop that has none for the service
// ('mobilis' | 'offer' | 'ooredoo' | 'djezzy'); returns how many shops got it
export const fillRate = (service, rate) => rpc('store_admin_flexy_fill_rate_v2', { p_service: service, p_rate: rate })
export const flexyJobs = (status = null, limit = 20, before = null) => rpc('store_admin_flexy_jobs', { p_status: status, p_limit: limit, p_before: before })
export const flexyReviewCount = () => rpc('store_admin_flexy_review_count')
// v1.43: failed or not sent, and the shop's charge not back (5 minutes after)
export const flexyUnrefunded = async () => (await rpc('store_admin_flexy_unrefunded'))?.[0] || { count: 0, amount: 0 }
// A shop's job in review: sent (the charge stays) or not sent (full refund to the shop)
export const flexyResolve = (jobId, done) => rpc('store_admin_flexy_resolve', { p_job_id: jobId, p_done: done })

// v1.44: the pages the owner and the shops open (light: one per page per person every 10 minutes)
export const pageSeen = (page) => rpc('store_admin_page_seen', { p_page: page })
export const usage = (days) => rpc('store_admin_usage', { p_days: days })

// v1.45: each shop's spending, this period against the one before; the two numbers are the owner's
export const indicators = (days) => rpc('store_admin_indicators', { p_days: days })
export const setIndicators = (changePct, minAmount) => rpc('store_admin_set_indicators', { p_change_pct: changePct, p_min_amount: minAmount })

// v1.46: one shop's visits page by page, with what it looked at (brands, buy sheets, searches)
export const usageShop = (customerId, days) => rpc('store_admin_usage_shop', { p_customer: customerId, p_days: days })
