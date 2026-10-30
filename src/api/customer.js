import { supabase } from 'boot/supabase'
import { StoreError } from './errors'
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

// v1.52: a game card out of stock made up of cards in stock (310 = 210 + 100): what can be, and its purchase (all the codes)
export const splitOffers = (token) => rpc('store_split_offers', { p_token: token })
export async function buySplit (token, productId, qty, requestId) {
  const rows = await rpc('store_buy_split', { p_token: token, p_product_id: productId, p_qty: qty, p_request_id: requestId })
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

// v1.37: the customer's cards and Flexy in one list
export const ops = (token, f) => rpc('store_ops', {
  p_token: token,
  p_type: f.type || null,
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
// «تم نسخها» on the server (v1.27): a display hint only, never a redemption or sale status
export const markCopied = (token, codeId) => rpc('store_mark_copied', { p_token: token, p_code_id: codeId })
export const orderCopies = (token, orderId) => rpc('store_order_copies', { p_token: token, p_order_id: orderId })
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

// Flexy for shops (v1.33): the shop sees amounts, statuses and network replies, never its rate or charge.
// Sending goes through the Edge function store-flexy: it takes the charge and calls Flexy Core server-side.
// v1.39: djezzy / ooredoo say whether the shop has a rate on that operator (its screen sends to those only)
export async function flexyStatus (token) {
  const rows = await rpc('store_flexy_status_v3', { p_token: token })
  return rows?.[0] || { enabled: false, open: false, max_amount: 0, offers: false, mobilis: false, djezzy: false, ooredoo: false }
}
// v1.47: «هل وصل للزبون؟» for its operations the program could not prove; the answer moves no money
export const flexyQuestions = (token) => rpc('store_flexy_questions', { p_token: token })
export const flexyAnswer = (token, jobId, answer) => rpc('store_flexy_answer', { p_token: token, p_job_id: jobId, p_answer: answer })
export const flexyJobs = (token, limit, before) => rpc('store_flexy_jobs', { p_token: token, p_limit: limit, p_before: before ?? null })
async function shop (path, body) {
  const { data, error } = await supabase.functions.invoke('store-flexy/shop/' + path, { method: 'POST', body })
  if (!error) return data
  let code = 'NETWORK'
  const res = error.context
  if (res && typeof res.json === 'function') {
    const b = await res.json().catch(() => null)
    code = b?.error || 'UNKNOWN'
  }
  throw new StoreError(code, error)
}
export const flexySend = (token, phone, amount, requestId) => shop('send', { token, phone, amount, request_id: requestId })
export const flexyRefresh = (token) => shop('refresh', { token })
// Offers: the line's group and its offers (Flexy Core keeps or discovers the group, no money), then one offer
// by its name; the server takes the price from the name.
export const flexyOffer = (token, phone, offer, requestId) => shop('send', { token, kind: 'offer', phone, offer, request_id: requestId })
export const flexyOffers = (token, phone) => shop('offers', { token, phone })
// «أوتوميكس» (owner 2026-10-29): which quick offers a SIM can take now → { name: true | false }
export const flexyAvailable = (token, offers) => shop('available', { token, offers }).then((r) => r?.available || {})

// Game top-up by player id (v1.25): the card comes from stock and is never shown; an operator tops up by hand
export async function gameStatus (token) {
  const rows = await rpc('store_game_status', { p_token: token })
  return rows?.[0] || { is_open: false, is_operator: false }
}
export const gameCards = (token) => rpc('store_game_cards', { p_token: token })
export async function gameCreate (token, productId, playerId, requestId) {
  const rows = await rpc('store_game_create', { p_token: token, p_product_id: productId, p_player_id: playerId, p_request_id: requestId })
  return rows?.[0] || null
}
// v1.51: any amount, made of several cards (300 = 200 + 100); the price is the sum of the cards
export const gameSplitPreview = (token, brand, units) => rpc('store_game_split_preview', { p_token: token, p_brand: brand, p_units: units })
export const gameCreateUnits = (token, brand, units, playerId, requestId) =>
  rpc('store_game_create_units', { p_token: token, p_brand: brand, p_units: units, p_player_id: playerId, p_request_id: requestId })
export const gameGroups = (token) => rpc('store_game_groups', { p_token: token })
export const gameOrders = (token, limit, offset) => rpc('store_game_orders', { p_token: token, p_limit: limit, p_offset: offset })
export const gameRecentIds = (token) => rpc('store_game_recent_ids', { p_token: token })
export const gameCancel = (token, gameId) => rpc('store_game_cancel', { p_token: token, p_game_id: gameId })

// Operators: a worker passes his token; the owner passes null (his own Supabase session is checked)
export const gamePresence = (token, available) => rpc('store_game_presence', { p_token: token, p_available: available ?? null })
export async function gameBoard (token) {
  const rows = await rpc('store_game_board', { p_token: token })
  return rows?.[0] || null
}
export const gameQueue = (token, open, limit, offset) => rpc('store_game_queue', { p_token: token, p_open: open, p_limit: limit, p_offset: offset })
export const gameOpenCount = (token) => rpc('store_game_open_count', { p_token: token })
export const gameClaim = (token, gameId, claim) => rpc('store_game_claim', { p_token: token, p_game_id: gameId, p_claim: claim })
// result: 'done' | 'used_card' | 'failed'
export const gameFinish = (token, gameId, result, f = {}) => rpc('store_game_finish', {
  p_token: token, p_game_id: gameId, p_result: result, p_txn_ref: f.txnRef || null, p_reason: f.reason || null, p_card_back: f.cardBack ?? null
})

// v1.44: the page the shop opened (its path only)
export const pageSeen = (token, page) => rpc('store_page_seen', { p_token: token, p_page: page })
