import { supabase } from 'boot/supabase'
import { rpc } from './rpc'
import { StoreError } from './errors'
import { normPhone } from './format'

// Admin API: requires a Supabase Auth session; the database also checks store.admins.

export const isAdmin = () => rpc('store_admin_is_admin')

// s169 (owner 2026-11-01): a hidden customer (e.g. DEMO) is left out of every list; customersAll() keeps him. Before s169 nobody is hidden.
export const hiddenCustomers = () => rpc('store_admin_hidden_customers').then((x) => x || []).catch(() => [])
export const customersAll = () => rpc('store_admin_customers')
export const customers = async () => {
  const [list, hidden] = await Promise.all([customersAll(), hiddenCustomers()])
  const out = new Set((hidden || []).map(Number))
  return (list || []).filter((c) => !out.has(Number(c.customer_id ?? c.id)))
}
export const customerHide = (customerId, hidden) => rpc('store_admin_customer_hide', { p_customer_id: customerId, p_hidden: hidden })
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
// s168: the v2 feed names an Idoom or game top-up (kind, target, job_status); before s168 the v1 feed, as before
const missingFn = (e) => e?.raw?.code === 'PGRST202' || /Could not find the function|does not exist/.test(String(e?.raw?.message || ''))
const opsArgs = (f) => ({
  p_scope: f.scope || null,
  p_customer_id: f.customerId || null,
  p_type: f.type || null,
  p_from: f.from || null,
  p_to: f.to || null,
  p_query: f.query || null,
  p_limit: f.limit,
  p_offset: f.offset
})
export const ops = (f) => rpc('store_admin_ops_v2', opsArgs(f))
  .catch((e) => (missingFn(e) ? rpc('store_admin_ops', opsArgs(f)) : Promise.reject(e)))

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
// v1.59: a card's own minimum (null clears it)
// v1.60: cards in stock × their cost, card sales profit, the shops' flexy share (last N days)
export const capital = (days) => rpc('store_admin_capital', { p_days: days })
// s173: the cards without the suspect ones, and the suspect ones apart ({n, capital}); before s173 the call fails and capital() answers
export const capitalV2 = (days) => rpc('store_admin_capital_v2', { p_days: days })
// «التغذية» (v1.61): the cards taken to feed the Sama SIMs that need the owner, «صحّح الرمز» (back to feeding), «مستعملة»
export const feedCards = () => rpc('store_admin_feed_cards')
// v1.62: the Mobilis values the feeding can take now, with their counts (the page's list)
export const feedFaces = () => rpc('store_admin_feed_faces')
// s170: suspect cards per value (feeding) and per product (Idoom); the owner's Idoom top-up from a suspect card
export const feedSuspectFaces = () => rpc('store_admin_feed_suspect_faces')
// s171: each batch's code with its history (Q4-H50-W70); by Idoom job; find by any part; the suppliers' letters
// s172: the batches holding a card (per Idoom product / per feeding value), and an Idoom top-up from the chosen batch
export const batchesForProduct = (productId, suspect) => rpc('store_admin_batches_for_product', { p_product_id: productId, p_suspect: !!suspect }).catch(() => [])
export const batchesForFace = (face, suspect) => rpc('store_admin_batches_for_face', { p_face: face, p_suspect: !!suspect }).catch(() => [])
export const idoomCreateFromBatch = (productId, line, requestId, batchId, suspect) => rpc('store_admin_idoom_create_from_batch',
  { p_product_id: productId, p_line: line, p_request_id: requestId, p_batch: batchId, p_suspect: !!suspect }).then((r) => r?.[0] || null)
// The owner's pick: «تلقائي (الأقدم)» or one batch (its code and its cards left); null = cancelled. Empty list = no question.
export async function pickBatch (Dialog, title, list) {
  if (!list || !list.length) return { batch: null }
  return await new Promise((resolve) => {
    Dialog.create({
      title, cancel: 'إلغاء', ok: 'متابعة',
      options: { type: 'radio', model: 'auto', items: [{ label: 'تلقائي (الأقدم)', value: 'auto' },
        // newest first (owner 2026-11-01); «تلقائي» still takes the oldest
        ...[...list].sort((a, b) => Number(b.batch_id) - Number(a.batch_id)).map((b) => ({ label: `${b.code || '#' + b.batch_id} · ${b.n} بطاقة`, value: String(b.batch_id) }))] }
    }).onOk((v) => resolve({ batch: v === 'auto' ? null : Number(v) })).onCancel(() => resolve(null))
  })
}
export const batchCodeMap = (ids) => rpc('store_admin_batch_code_map', { p_batch_ids: ids }).catch(() => ({}))
export const idoomJobBatches = (ids) => rpc('store_admin_idoom_job_batches', { p_job_ids: ids }).catch(() => ({}))
export const batchFind = (part) => rpc('store_admin_batch_find', { p_part: part })
export const supplierLetters = () => rpc('store_admin_supplier_letters').catch(() => ({}))
export const supplierLetter = (supplierId, letter) => rpc('store_admin_supplier_letter', { p_supplier: supplierId, p_letter: letter })
export const suspectCounts = () => rpc('store_admin_suspect_counts')
export const idoomCreateSuspect = (productId, line, requestId) => rpc('store_admin_idoom_create_suspect', { p_product_id: productId, p_line: line, p_request_id: requestId }).then((r) => r?.[0] || null)
export const feedFix = (cardId, code) => rpc('store_admin_feed_fix', { p_card: cardId, p_code: code })
export const feedUsed = (cardId) => rpc('store_admin_feed_used', { p_card: cardId })
export const setLowMin = (productId, min) => rpc('store_admin_set_low_min', { p_product_id: productId, p_min: min })

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
// s167 (suspect stock): four states, «عرض» (whole codes logged), «الصق كودًا», each batch's errors, the 2-bad alerts
export const codesState = (codeIds, state) => rpc('store_admin_codes_state', { p_code_ids: codeIds, p_state: state })
export const batchCodesV3 = (batchId, reveal = false) => rpc('store_admin_batch_codes_v3', { p_batch_id: batchId, p_reveal: reveal })
export const batchesExtra = (batchIds) => rpc('store_admin_batches_extra', { p_batch_ids: batchIds })
export const codeFind = (text) => rpc('store_admin_code_find', { p_text: text })
export const batchAlerts = () => rpc('store_admin_batch_alerts')
export const batchAlertsSeen = (batchId = null) => rpc('store_admin_batch_alerts_seen', { p_batch_id: batchId })
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
// s164 (owner 2026-10-31): Free Fire by the Rech-Doom phone: a switch per phone, and what each phone said on game orders
export const executorGame = (id, on) => rpc('store_admin_executor_game', { p_executor_id: id, p_on: on })
export const gamePhoneView = () => rpc('store_admin_game_phone_view')
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
// الخدمات (owner 2026-10-31): the owner alone works the queue
export const services = () => rpc('store_admin_services')
export const serviceSave = (productId, s) => rpc('store_admin_service_save', {
  p_product_id: productId, p_is_service: s.isService ?? null, p_open: s.open ?? null, p_fields: s.fields ?? null, p_default_cost: s.defaultCost ?? null
})
export const serviceQueue = (open, limit, offset) => rpc('store_admin_service_queue', { p_open: open, p_limit: limit, p_offset: offset })
export const serviceOpenCount = () => rpc('store_admin_service_open_count')
export const serviceClaim = (id) => rpc('store_admin_service_claim', { p_id: id })
export const servicePrice = (id, unitPrice, reason) => rpc('store_admin_service_price', { p_id: id, p_unit_price: unitPrice, p_reason: reason })
export const serviceDone = (id, qtyDone, costTotal, reply) => rpc('store_admin_service_done', {
  p_id: id, p_qty_done: qtyDone, p_cost_total: costTotal ?? null, p_reply: reply || null
})
export const serviceFail = (id, reply) => rpc('store_admin_service_fail', { p_id: id, p_reply: reply || null })
export const setPlayerTopup = (productId, enabled) => rpc('store_admin_set_player_topup', { p_product_id: productId, p_enabled: enabled })
export const playerTopupProducts = () => rpc('store_admin_player_topup_products')
// v1.49: orders by player id accepted any time (null = read only)
export const gameAlwaysOpen = (on = null) => rpc('store_admin_game_always_open', { p_on: on })
// v1.50: the owner orders a top-up FOR a customer (WhatsApp); his short balance becomes debt
// s165: «من رصيد المنصة» per game product, and the owner's order for such a product
export const gamePlatformList = () => rpc('store_game_platform_list', { p_token: null })
export const gamePlatformSet = (productId, on, cost) => rpc('store_admin_game_platform_set', { p_product_id: productId, p_on: on, p_cost: cost })
export const gameOrderPlatformFor = (customerId, productId, playerId, requestId) =>
  rpc('store_admin_game_order_platform', { p_customer_id: customerId, p_product_id: productId, p_player_id: playerId, p_request_id: requestId })
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
// «اللوحة التلقائية» (store s166): read (token null = the owner) and switch
export const flexyUi = () => rpc('store_flexy_ui', { p_token: null })
export const setFlexyAutomix = (on) => rpc('store_admin_flexy_automix_set', { p_on: on })
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

// s176: the network's own words kept with each judged card ({ [code_id]: { reply, reply_at, line } }); empty before s176
export async function codeReplies (ids) {
  if (!ids?.length) return {}
  try {
    const rows = await rpc('store_admin_code_replies', { p_ids: ids })
    return Object.fromEntries((rows || []).map((r) => [r.code_id, r]))
  } catch { return {} }
}

// s178: a platform's API key (topup-dz), kept in Vault, never read back: { [platform]: { last4, saved_at } }
export const platformKeys = () => rpc('store_admin_platform_keys')
export const platformKeySet = (platform, key) => rpc('store_admin_platform_key_set', { p_platform: platform, p_key: key })
export const platformKeyClear = (platform) => rpc('store_admin_platform_key_clear', { p_platform: platform })
// s178: the dollar's price as the owner bought it (cost in dinars = platform price × rate)
export const platformRates = () => rpc('store_admin_platform_rates')
export const platformRateSet = (platform, rate) => rpc('store_admin_platform_rate_set', { p_platform: platform, p_rate: rate })
// s179: the platform's product list saved once ({ products, n, fetched_at } | null); refreshed only on the owner's press
export const platformCatalog = (platform) => rpc('store_admin_platform_catalog', { p_platform: platform })
export const platformCatalogSave = (platform, products) => rpc('store_admin_platform_catalog_save', { p_platform: platform, p_products: products })
// s180: «اربطه» — our game product tied to one platform product (no money, no switch)
export const platformLinks = () => rpc('store_admin_platform_links')
export const platformLink = (productId, platform, platformProductId) =>
  rpc('store_admin_platform_link', { p_product: productId, p_platform: platform, p_platform_product: platformProductId })
// s181: «دفتر المخزون» — per card: in / sold / voided / fed / left; a card's (or one batch's) movements with the count left
export const stockLedger = () => rpc('store_admin_stock_ledger')
export const stockMoves = (productId, limit = 200, batchId = null) => rpc('store_admin_stock_moves', { p_product: productId, p_limit: limit, p_batch: batchId })
