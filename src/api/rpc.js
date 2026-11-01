import { supabase } from 'boot/supabase'
import { toStoreError } from './errors'

// Reads kept on this device for a short while (owner 2026-11-01: «كلما حدّثت الصفحة يقوم بطلب جديد… يكونون محفوظين»):
// a page opened or refreshed again within TTL shows the kept answer at once, with no request to the database. Any call
// that changes something (a write) clears them all, so nothing stale is shown after an action.
const CACHE_KEY = 'rpc.cache.v1'
const TTL = {
  store_admin_stock_v2: 60_000, store_admin_brands: 300_000, store_admin_suppliers: 300_000, store_admin_product_costs: 300_000,
  store_admin_price_list: 120_000, store_admin_low_stock: 60_000, store_admin_stock_ledger: 60_000, store_admin_suspect_counts: 60_000,
  store_admin_customers: 60_000, store_admin_batches_v2: 60_000, store_admin_platform_catalog: 600_000,
  store_admin_daily_report: 120_000
}
const WRITE = /_(set|save|add|create|delete|remove|update|mark|resolve|cancel|topup|buy|order|transfer|retry|judge|link|clear|freeze|void|restore|state|hide|confirm|approve|apply|reveal|fix|used|take|move|assign|send|pay|debt|refund|split|rename|reorder|toggle|import|upload|enable|disable|record|note|done|start|stop|change|reset)(_|$)/
// A kept answer serves only the first call after the page opens (a reload, a new tab): «تحديث» inside the page always asks
const OPENED = Math.random().toString(36).slice(2)
let mem = null
const readCache = () => { if (mem) return mem; try { mem = JSON.parse(localStorage.getItem(CACHE_KEY) || '{}') } catch { mem = {} } return mem }
const writeCache = () => { try { localStorage.setItem(CACHE_KEY, JSON.stringify(mem || {})) } catch { /* full or private: memory only */ } }
export function clearRpcCache () { mem = {}; try { localStorage.removeItem(CACHE_KEY) } catch { /* private mode */ } }

// Every store_* call goes through here so errors are always mapped the same way.
export async function rpc (fn, args = {}) {
  const ttl = TTL[fn]
  const key = ttl ? fn + ':' + JSON.stringify(args) : null
  if (key) {
    const hit = readCache()[key]
    if (hit && hit.o !== OPENED && Date.now() - hit.at < ttl) { hit.o = OPENED; return hit.data }
  } else if (WRITE.test(fn)) {
    clearRpcCache()
  }
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw toStoreError(error, fn)
  if (key) { readCache()[key] = { at: Date.now(), data, o: OPENED }; writeCache() }
  return data
}

// One id per user action. Reusing it on retry makes the database apply the action once.
export function newRequestId () {
  return crypto.randomUUID()
}
