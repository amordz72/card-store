import { ref } from 'vue'

// «تحميل المزيد»: the first batch, then each tap appends the next batch below (newest first).
// fetcher(limit, offset) resolves to rows carrying total_count (and total_amount for transfers),
// or undefined on error. Rows are append-only in the database, so a purchase made while browsing
// only shifts the offsets: the repeated rows are dropped by `key`, nothing is skipped, and the new
// rows are fetched and put on top.
const MAX_LIMIT = 100   // the database caps p_limit at 100

export function useLoadMore (fetcher, { key, size = 20 } = {}) {
  const rows = ref([])
  const total = ref(0)
  const sum = ref(0)
  const loadingMore = ref(false)
  let seq = 0   // a newer reset wins over an older reply that arrives late

  function take (data) {
    total.value = data.length ? Number(data[0].total_count) : 0
    sum.value = data.length ? Number(data[0].total_amount ?? 0) : 0
  }

  // start again from the top (filters changed, or a new movement was added)
  async function reset (limit = size) {
    const mine = ++seq
    loadingMore.value = false
    const data = await fetcher(Math.min(limit, MAX_LIMIT), 0)
    if (mine !== seq || !data) return
    rows.value = data
    take(data)
  }

  // reload what is already shown (after a reversal) without collapsing the list
  const refresh = () => reset(Math.max(size, rows.value.length))

  function append (data) {
    const seen = new Set(rows.value.map((r) => r[key]))
    rows.value = rows.value.concat(data.filter((r) => !seen.has(r[key])))
  }

  async function more () {
    if (loadingMore.value || rows.value.length >= total.value) return
    const mine = seq
    loadingMore.value = true
    try {
      const data = await fetcher(size, rows.value.length)
      if (mine !== seq || !data) return
      const before = total.value
      append(data)
      if (data.length) take(data)
      // new movements arrived on top while browsing: put them first so the count adds up
      const added = total.value - before
      if (added > 0) {
        const top = await fetcher(Math.min(added, MAX_LIMIT), 0)
        if (mine !== seq || !top) return
        const seen = new Set(rows.value.map((r) => r[key]))
        rows.value = top.filter((r) => !seen.has(r[key])).concat(rows.value)
        if (top.length) take(top)
      }
    } finally {
      if (mine === seq) loadingMore.value = false
    }
  }

  return { rows, total, sum, loadingMore, reset, refresh, more, size }
}
