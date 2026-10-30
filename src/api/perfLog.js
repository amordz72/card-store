// «سجل البطء» (owner 2026-10-30: «يتأخر الرد: هل هذا مسجّل؟ حتى بلا إنترنت»): every request the app makes is timed on
// this phone (localStorage, the last 300), with whether there was internet and how long the server itself took
// (flexy-api's x-flexy-ms). Kept even offline; the owner's phone sends what is new when it can (AppLayout).
// Names only (the call, never its arguments): no customer number leaves or is kept.

const KEY = 'cs_perf'
const SENT_KEY = 'cs_perf_sent'
const MAX = 300
let list = null
let saveTimer = null

function load () {
  if (list) return list
  try { list = JSON.parse(localStorage.getItem(KEY) || '[]') } catch { list = [] }
  return list
}
function save () {
  clearTimeout(saveTimer)
  saveTimer = setTimeout(() => { try { localStorage.setItem(KEY, JSON.stringify(list.slice(-MAX))) } catch { /* private mode */ } }, 1000)
}
const net = () => {
  const c = navigator.connection
  return c ? `${c.effectiveType || ''} ${c.downlink ?? ''}Mbps` : ''
}

export function perfNote (e) {
  const l = load()
  l.push({ at: Date.now(), online: navigator.onLine, net: net(), ...e })
  if (l.length > MAX) l.splice(0, l.length - MAX)
  save()
}
export const perfEntries = () => load().slice()

// «/rest/v1/rpc/store_flexy_jobs» → «rpc:store_flexy_jobs»; «/functions/v1/flexy-api/v1/owner/665/<key>» → «flexy-api:owner/665/:id»
export function callName (url) {
  let u
  try { u = new URL(url, location.href) } catch { return '' }
  if (!/supabase\.co$/.test(u.hostname)) return ''
  const p = u.pathname.replace(/\/[A-Za-z0-9_-]{16,}/g, '/:id').replace(/\/\d{6,}/g, '/:n')
  let m = p.match(/^\/rest\/v1\/rpc\/(.+)$/)
  if (m) return 'rpc:' + m[1]
  m = p.match(/^\/functions\/v1\/([^/]+)\/?(?:v1\/)?(.*)$/)
  if (m) return m[1] + ':' + m[2]
  m = p.match(/^\/(auth|rest|storage)\/v1\/([^/]*)/)
  return m ? m[1] + ':' + m[2] : p.slice(0, 40)
}

/** fetch, timed: given to the Supabase client (boot/supabase.js), so every call of the app passes here. */
export async function timedFetch (input, init) {
  const url = typeof input === 'string' ? input : input?.url || String(input)
  const what = callName(url)
  if (!what) return fetch(input, init)
  const t = performance.now()
  try {
    const res = await fetch(input, init)
    const server = Number(res.headers.get('x-flexy-ms'))
    perfNote({ what, ms: Math.round(performance.now() - t), server: Number.isFinite(server) && server > 0 ? server : null, ok: res.ok, status: res.status })
    return res
  } catch (e) {
    perfNote({ what, ms: Math.round(performance.now() - t), ok: false, status: 0, err: String(e?.message || e).slice(0, 60) })
    throw e
  }
}

/** Per call, slowest first: how many, the average, the server's part, and the cause in words. */
export function perfSummary (entries = load(), sinceMs = Date.now() - 24 * 3600_000) {
  const by = new Map()
  for (const e of entries) {
    if (e.at < sinceMs || !e.what) continue
    const g = by.get(e.what) || { what: e.what, n: 0, ms: 0, server: 0, withServer: 0, fails: 0, offline: 0, slow: 0 }
    g.n++
    g.ms += e.ms || 0
    if (e.server) { g.server += e.server; g.withServer++ }
    if (!e.ok) g.fails++
    if (!e.online) g.offline++
    if ((e.ms || 0) > 3000) g.slow++
    by.set(e.what, g)
  }
  return [...by.values()].map((g) => {
    const avg = Math.round(g.ms / g.n)
    const server = g.withServer ? Math.round(g.server / g.withServer) : null
    const cause = g.offline > g.n / 2 ? 'لا إنترنت'
      : server === null ? (avg > 3000 ? 'بطيء (الخادم لا يقول مدته)' : '')
        : avg - server > server ? 'الإنترنت' : 'الخادم'
    return { ...g, avg, serverAvg: server, cause }
  }).sort((a, b) => b.avg - a.avg)
}

/** What was not sent yet, and marking it sent. */
export function perfUnsent () {
  let since = 0
  try { since = Number(localStorage.getItem(SENT_KEY) || 0) } catch { /* private mode */ }
  return load().filter((e) => e.at > since).slice(-200)
}
export function perfMarkSent (at) {
  try { localStorage.setItem(SENT_KEY, String(at)) } catch { /* private mode */ }
}
