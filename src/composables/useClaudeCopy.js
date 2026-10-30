import { onUnmounted } from 'vue'
import { copyToClipboard, Notify } from 'quasar'

// «نسخ لـClaude» (owner 2026-10-30): anything Claude may need, from anywhere, instead of Claude reading the database.
//   * the whole page: every card registers what it knows; «نسخ الشاشة» adds it after the visible text;
//   * one item: a small 📋 next to it copies that item alone.
// Plain «key: value» lines, short: cheaper for Claude than a database read, and no permission to ask.
const registry = new Map()

/** A card's technical data for «نسخ الشاشة» (removed when the card goes away). */
export function registerForClaude (name, getter) {
  registry.set(name, getter)
  onUnmounted(() => registry.delete(name))
}

// Customer numbers leave as their last 4 digits (the rule: no full customer number in the chat)
const mask = (t) => t.replace(/(?<!\d)(?:\+?213|0)?([5-7]\d{4})(\d{4})(?!\d)/g, '…$2')
const line = (v) => mask(v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v))
export function claudeBlock (title, obj) {
  const rows = Array.isArray(obj) ? obj : [obj]
  return ['## ' + title, ...rows.map((r, i) => (rows.length > 1 ? `- ${i + 1}. ` : '- ') +
    Object.entries(r || {}).filter(([, v]) => v !== null && v !== undefined && v !== '').map(([k, v]) => `${k}=${line(v)}`).join(' | '))].join('\n')
}

/** Everything the page's cards registered, for the end of «نسخ الشاشة». */
export function claudePageText () {
  const parts = []
  for (const [name, get] of registry) {
    try {
      const v = get()
      if (v && (!Array.isArray(v) || v.length)) parts.push(claudeBlock(name, v))
    } catch { /* a card that cannot say: skipped */ }
  }
  return parts.length ? '\n\n— لـClaude (بيانات تقنية) —\n' + parts.join('\n\n') : ''
}

/** One item, copied alone. */
export async function copyForClaude (title, obj) {
  try {
    await copyToClipboard(claudeBlock(title, obj))
    Notify.create({ message: 'نُسخ لـClaude: الصقه في المحادثة', color: 'positive', position: 'top', timeout: 1200 })
  } catch {
    Notify.create({ message: 'تعذّر النسخ', color: 'negative', position: 'top' })
  }
}
