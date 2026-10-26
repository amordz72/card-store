import { ref } from 'vue'

// One list from several sources, newest first (owner 2026-10-26: the cards, the shops' Flexy and
// the owner's own Flexy, which Flexy Core keeps, in one «العمليات»). Each source gives its newest
// rows page by page: fetch(limit, state) → { rows, state, done, total? } or undefined on error.
// A page takes the newest rows across the sources, so no row of one source is skipped by another.
export function useOpsFeed (sources, { size = 20, key = 'key' } = {}) {
  const rows = ref([])
  const total = ref(0)         // null while a source cannot count (Flexy Core)
  const hasMore = ref(false)
  const loading = ref(false)
  const loadingMore = ref(false)
  let seq = 0
  let srcs = []

  async function fill (s, n, mine) {
    while (!s.done && s.buf.length < n) {
      const r = await s.fetch(Math.max(n - s.buf.length, size), s.state)
      if (mine !== seq) return
      if (!r) { s.done = true; return }
      s.buf.push(...r.rows.map((x) => ({ ...x, t: Date.parse(x.created_at) || 0 })))
      s.state = r.state
      s.done = r.done
      if (r.total != null) s.total = r.total
    }
  }

  async function take (n, mine) {
    await Promise.all(srcs.map((s) => fill(s, n, mine)))
    if (mine !== seq) return null
    const out = []
    while (out.length < n) {
      let best = null
      for (const s of srcs) if (s.buf.length && (!best || s.buf[0].t > best.buf[0].t)) best = s
      if (!best) break
      out.push(best.buf.shift())
    }
    hasMore.value = srcs.some((s) => s.buf.length || !s.done)
    total.value = srcs.every((s) => s.total != null) ? srcs.reduce((a, s) => a + s.total, 0) : null
    return out
  }

  async function reset () {
    const mine = ++seq
    srcs = sources().map((fetch) => ({ fetch, state: null, buf: [], done: false, total: null }))
    loading.value = true
    loadingMore.value = false
    try {
      const out = await take(size, mine)
      if (out) rows.value = out
    } finally {
      if (mine === seq) loading.value = false
    }
  }

  async function more () {
    if (loadingMore.value || !hasMore.value) return
    const mine = seq
    loadingMore.value = true
    try {
      const out = await take(size, mine)
      if (!out) return
      const seen = new Set(rows.value.map((r) => r[key]))
      rows.value = rows.value.concat(out.filter((r) => !seen.has(r[key])))
    } finally {
      if (mine === seq) loadingMore.value = false
    }
  }

  return { rows, total, hasMore, loading, loadingMore, reset, more, size }
}

// A source over an offset list of the store database (rows carry total_count).
export function offsetSource (fetcher, mapRow = (r) => r) {
  return async (limit, offset) => {
    const at = offset || 0
    const data = await fetcher(Math.min(limit, 100), at)
    if (!data) return undefined
    const count = data.length ? Number(data[0].total_count) : at
    return { rows: data.map(mapRow), state: at + data.length, done: at + data.length >= count || !data.length, total: count }
  }
}
