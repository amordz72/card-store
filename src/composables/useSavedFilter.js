import { ref, watch } from 'vue'

// A list's filter as it was last left, kept on this phone (owner 2026-10-26: «العمليات» opens
// filtered as before). Only the keys of `defaults` are kept, minus `skip` (the search text).
// Storage may be blocked or empty: the page then opens with the defaults.
export function useSavedFilter (key, defaults, { skip = [] } = {}) {
  let saved = {}
  try {
    saved = JSON.parse(localStorage.getItem(key) || '{}') || {}
  } catch {
    saved = {}
  }
  const kept = Object.keys(defaults).filter((k) => !skip.includes(k) && k in saved)
  const f = ref({ ...defaults, ...Object.fromEntries(kept.map((k) => [k, saved[k]])) })
  watch(f, (v) => {
    try {
      localStorage.setItem(key, JSON.stringify(Object.fromEntries(Object.keys(defaults).filter((k) => !skip.includes(k)).map((k) => [k, v[k]]))))
    } catch { /* the filter still works, it is just not remembered */ }
  }, { deep: true })
  return f
}

// The quick dates: «اليوم»، «أمس»، «7 أيام»، «الكل»، or the two days chosen («تاريخ محدد»).
const day = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
export function rangeDates (f) {
  const now = new Date()
  const ago = (n) => day(new Date(now.getFullYear(), now.getMonth(), now.getDate() - n))
  if (f.range === 'today') return { from: ago(0), to: ago(0) }
  if (f.range === 'yesterday') return { from: ago(1), to: ago(1) }
  if (f.range === '7d') return { from: ago(6), to: ago(0) }
  if (f.range === 'custom') return { from: f.from || '', to: f.to || '' }
  return { from: '', to: '' }
}
