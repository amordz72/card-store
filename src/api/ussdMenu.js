// What a USSD reply asks for, read for the lab's buttons (owner 2026-10-28: «buttons from the replies,
// a box for anything not understood»). Shapes from real replies (developer telecom/NETWORK-REPLY-CATALOG.md):
//   menu lines   «48- TOD», «1.Sama Mix 100», «1:Plus de detail Bonus», «0:Plus»
//   one line     «1:Pour Confirmer 2:Pour Annuler», «1-Non 2-Oui»
//   inline       «tapez 1 pour confirmer. Ou tapez 2 pour annuler», «1 OK, 0 annuler», «للتأكيد إختر 1 للإلغاء إختر 0»
//   PIN prompt   «2000Da. vous seront débités, entrez le code PIN :», «Please Enter your PIN code»
// Nothing here sends: the page asks before a money step, and a PIN is only ever sent as {PIN}.

const LETTER = /[A-Za-z؀-ۿ]/
// «N- label», «N:label», «N.label», «N) label», several on one line; a label has a letter (not «20:58»)
const ITEM = /(?:^|\s)(\d{1,3})\s*[-.:)]\s*(.+?)(?=\s+\d{1,3}\s*[-.:)]\s*\S|$)/g
const INLINE = [
  /tapez\s+(\d{1,2})\s+pour\s+([^.,;\n]+)/gi,
  /(?:^|[\s,])(\d)\s+(OK|annuler)\b/gi
]
const ARABIC = /(للتأكيد|للإلغاء)\s*إختر\s*(\d)/g
const PIN = /code\s*pin|pin\s*code|mot de passe|entrez\s+(?:le|votre)\s+(?:code|pin)|\bpin\s*:|الرقم السري|كلمة السر|الرمز السري/i
// The reply announces money: an answer that agrees (or the PIN) is the money step
const MONEY = /d[ée]bit|vous voulez|transf[ée]r|recharger|activer|payer|تعبئة|تحويل|سيتم خصم/i
const AGREE = /confirm|^ok$|oui|تأكيد|للتأكيد/i
const NEXT = /^(plus|suivant|more|next|التالي|المزيد)$/i

/**
 * The reply's choices: [{ value, label, money, duplicate }], whether it asks for the PIN, and whether
 * the PIN is the money step. Unknown shapes give no choices: the page keeps the box.
 * On a Sama SIM the offer's index buys it at once, with no confirmation after (*665*): an offer line
 * (a name with a number) is the money step there.
 */
export function readReply (raw, simType = '') {
  const text = String(raw || '')
  const options = []
  const add = (value, label) => {
    label = label.trim()
    if (!LETTER.test(label) || options.some((o) => o.value === value && o.label === label)) return
    options.push({ value, label, next: NEXT.test(label) })
  }
  // Ooredoo glues lines («…YouTube)5-1000 DA…», 2026-10-29): the core's own split (585 splitLines)
  for (const line of text.replace(/\)\s*(\d{1,3})\s*-\s*/g, ')\n$1-').split(/\r?\n/)) {
    for (const m of line.matchAll(ITEM)) add(m[1], m[2])
  }
  for (const re of INLINE) for (const m of text.matchAll(re)) add(m[1], m[2])
  for (const m of text.matchAll(ARABIC)) add(m[2], m[1])
  const money = MONEY.test(text)
  const pin = PIN.test(text)
  const counts = options.reduce((c, o) => ({ ...c, [o.value]: (c[o.value] || 0) + 1 }), {})
  return {
    options: options.map((o) => ({
      ...o,
      money: (money && AGREE.test(o.label)) || (simType === 'mobilis-sama' && !o.next && /\d/.test(o.label)),
      duplicate: counts[o.value] > 1
    })),
    pin,
    pinIsMoney: pin && money
  }
}

/** A typed answer that looks like a PIN (4 to 8 digits) while the network asks for the PIN: never typed. */
export const typedPin = (value, asked) => asked && /^\s*\d{4,8}\s*$/.test(String(value || ''))
