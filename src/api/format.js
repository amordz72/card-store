// Shared display helpers (amounts are whole dinars)

export function money (n) {
  return Math.abs(Number(n) || 0).toLocaleString('en-US') + ' دج'
}

export function signed (n) {
  const v = Number(n) || 0
  return (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(v).toLocaleString('en-US')
}

export function dateTime (iso) {
  const d = new Date(iso)
  const p = (x) => String(x).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
}

export const CATEGORIES = [
  { id: 'phone', label: 'هاتف' },
  { id: 'net', label: 'إنترنت' },
  { id: 'game', label: 'ألعاب' },
  // «منتجات أخرى» (services, owner 2026-10-31): the last section of the store
  { id: 'other', label: 'منتجات أخرى' }
]

const BRAND_COLORS = {
  Mobilis: '#2E7D32',
  Djezzy: '#C62828',
  Ooredoo: '#9F1239',
  'Idoom ADSL': '#5B3A8E',
  'Idoom 4G': '#1E3A8A',
  'Free Fire': '#C2410C',
  PUBG: '#1F2937'
}

export function brandColor (brand) {
  return BRAND_COLORS[brand] || '#374151'
}

// Card reports (v1.20)
export const REPORT_REASONS = {
  used: 'مستعملة',
  not_found: 'غير موجودة / رقم خطأ',
  rejected: 'لا تُقبل',
  other: 'أخرى'
}
export const REPORT_STATUS = {
  open: { label: 'بانتظار التحقق', color: 'warning' },
  accepted: { label: 'مقبول', color: 'positive' },
  rejected: { label: 'مرفوض', color: 'negative' }
}

// Wallet entry kinds: label + badge colour (effects are computed in the database)
export const KINDS = {
  debt: { label: 'دَين', color: '#DC2626', help: 'يزيد الرصيد ويزيد الدين. حد الدين لا يمنعك (تنبيه فقط).' },
  debt_refund: { label: 'استرداد دَين', color: '#0E7490', help: 'ينقص الرصيد وينقص الدين.' },
  cash: { label: 'نقد', color: '#1D4ED8', help: 'يزيد الرصيد فقط.' },
  cash_refund: { label: 'استرداد نقد', color: '#0E7490', help: 'ينقص الرصيد فقط.' },
  pay: { label: 'دفع', color: '#15803D', help: 'ينقص الدين فقط. الدفع الزائد يجعل الدين بالسالب (له عندك).' },
  pay_refund: { label: 'استرداد دفع', color: '#0E7490', help: 'يرجع الدين كما كان.' },
  self: { label: 'شحن ذاتي', color: '#B45309' },
  purchase: { label: 'شراء', color: '#374151' },
  purchase_refund: { label: 'استرجاع شراء', color: '#0E7490' },
  shop_topup: { label: 'شحن المحل', color: '#C2410C' },
  shop_topup_refund: { label: 'استرداد شحن المحل', color: '#0E7490' }
}

export function effectText (dBalance, dDebt) {
  return [
    dBalance ? 'الرصيد ' + signed(dBalance) : 'الرصيد لا يتغير',
    dDebt ? 'الدين ' + signed(dDebt) : 'الدين لا يتغير'
  ].join(' · ')
}

export function debtView (debt, customerSide) {
  if (debt > 0) return { label: customerSide ? 'ديوني' : 'عليه دين', text: money(debt), cls: 'amount-neg' }
  if (debt < 0) return { label: customerSide ? 'لي عندكم' : 'له عندك', text: money(debt), cls: 'amount-pos' }
  return { label: customerSide ? 'ديوني' : 'الدين', text: '0 دج', cls: '' }
}

// A game card's amount as its name says it («Free Fire 210 جوهرة» → «210 جوهرة», «PUBG 60 UC» → «60 UC»): shown big on the
// card, the price under it (owner 2026-10-30: «أخطئ: أظن السعر عدد الجواهر»). Null when the name has no number.
export function gameAmount (name) {
  const n = String(name || '').match(/(\d[\d,.]*)/)
  if (!n) return null
  const unit = /جوهر/.test(name) ? 'جوهرة' : /\buc\b/i.test(name) ? 'UC' : ''
  return (n[1] + (unit ? ' ' + unit : '')).trim()
}

// A phone as people type it (owner 2026-10-30: «يرسله بفراغات… وحتى 213»): Arabic digits, spaces, dashes, +213 / 00213 /
// 213 → «0XXXXXXXXX». The server does the same (store_norm_phone); here so the copied message and the login are clean.
export function asciiDigits (s) {
  return String(s ?? '').replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x6F0))
}
export function normPhone (s) {
  const x = asciiDigits(s).replace(/[^0-9]/g, '')
  if (/^00213[0-9]{9}$/.test(x)) return '0' + x.slice(5)
  if (/^213[0-9]{9}$/.test(x)) return '0' + x.slice(3)
  if (/^[5-7][0-9]{8}$/.test(x)) return '0' + x
  return x
}
