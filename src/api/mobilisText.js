// Mobilis messages in Arabic, under the French original (owner 2026-10-30: «Transaction échouée» = «ايشوي»?)
const RULES = [
  [/^transaction [ée]chou[ée]e/i, () => 'فشلت العملية'],
  [/vous avez recharg\w* un montant de ([\d.,]+) DZD vers le (\d+)\D*(?:transaction est (\d+))?/i,
    (m) => `شحنت مبلغ ${Number(m[1].replace(',', '.'))} دج إلى الرقم 0${m[2]}${m[3] ? '، رقم العملية ' + m[3] : ''}`],
  [/votre balance/i, () => 'رصيد الشريحة (حسب الحسابات)'],
  [/est insuffisante/i, () => 'الرصيد غير كافٍ'],
  [/code pin|pin (?:incorrect|erron)/i, () => 'الرمز PIN مرفوض'],
  [/vous avez re[çc]u/i, () => 'وصلك رصيد']
]

export function mobilisArabic (text) {
  const t = String(text || '').trim()
  for (const [re, f] of RULES) {
    const m = t.match(re)
    if (m) return f(m)
  }
  return ''
}
