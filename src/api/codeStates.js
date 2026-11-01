// The four states of a code (owner 2026-11-01, s167). `state` is what store_admin_codes_state takes.
export const CODE_STATES = [
  { state: 'ok', label: 'سليم', color: 'positive' },
  { state: 'suspect', label: 'مشكوك فيه', color: 'deep-orange' },
  { state: 'used', label: 'تالف', color: 'negative' },
  { state: 'return', label: 'ترجع للمورّد', color: 'purple-8' }
]
// One word for a code as the owner reads it
export function codeWord (c) {
  if (c.bad === 'used') return { label: 'تالف', color: 'negative' }
  if (c.bad === 'return') return { label: 'ترجع للمورّد', color: 'purple-8' }
  if (c.status === 'sold') return { label: 'مباع', color: 'grey-7' }
  if (c.status === 'void') return { label: 'ملغى', color: 'grey-6' }
  if (c.suspect) return { label: 'مشكوك فيه', color: 'deep-orange' }
  if (c.frozen) return { label: 'مجمّد', color: 'warning' }
  return { label: 'سليم', color: 'positive' }
}
