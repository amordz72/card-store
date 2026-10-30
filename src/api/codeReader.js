// «قارئ المورّد» (owner 2026-10-30): a supplier's message pasted as it is → the card codes only.
// A line is a code when it is one word of letters / digits (dashes inside allowed), with a digit, of the reader's length;
// everything else is left out and shown (a date, «Mobilis -- 100», «Quantity 10», a line of dashes). The message's own
// quantity and card («Mobilis -- 100») are read to check the count and the chosen card.
// A supplier's reader (store.suppliers.reader, v1.57) may say where the codes start («بعد سطر فيه -----») and their length.

export const DEFAULT_READER = { startAfter: '', minLen: 6, maxLen: 40 }

const QTY = /(?:quantity|qty|qte|quantité|الكمية|العدد)\s*[:=-]?\s*(\d{1,5})/i
const CARD = /^([A-Za-z][A-Za-z0-9 ]{1,30}?)\s*[-–—:]*\s*(\d{2,6})\s*(?:da|dzd|دج)?$/i

export function readCodes (text, reader = DEFAULT_READER) {
  const r = { ...DEFAULT_READER, ...(reader || {}) }
  const min = Math.max(2, Number(r.minLen) || DEFAULT_READER.minLen)
  const max = Math.max(min, Number(r.maxLen) || DEFAULT_READER.maxLen)
  const codeRe = new RegExp(`^(?=.*\\d)[0-9A-Za-z](?:[0-9A-Za-z-]{${Math.max(0, min - 2)},${max - 2}})[0-9A-Za-z]$`)
  const lines = String(text || '').split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
  const codes = []
  const ignored = []
  let quantity = null
  let card = null
  let started = !String(r.startAfter || '').trim()
  for (const line of lines) {
    if (!started) {
      if (line.toLowerCase().includes(String(r.startAfter).trim().toLowerCase())) started = true
      ignored.push(line)
      continue
    }
    const sep = (line.match(/[;,|]/) || [null])[0]
    const code = (sep ? line.slice(0, line.indexOf(sep)) : line).trim()
    const serial = sep ? line.slice(line.indexOf(sep) + 1).trim() : ''
    if (codeRe.test(code) && !/^\d{1,2}[/.-]\d{1,2}/.test(code)) {
      codes.push({ code, serial })
      continue
    }
    ignored.push(line)
    const q = line.match(QTY)
    if (q && quantity == null) quantity = Number(q[1])
    const c = line.match(CARD)
    if (c && !card && !q) card = { brand: c[1].trim(), amount: Number(c[2]) }
  }
  const unique = [...new Map(codes.map((c) => [c.code, c])).values()]
  return { codes: unique, dups: codes.length - unique.length, ignored, quantity, card }
}

/** What the store gets: one card per line, «code ; serial» */
export const toLines = (codes) => codes.map((c) => (c.serial ? `${c.code} ; ${c.serial}` : c.code)).join('\n')
