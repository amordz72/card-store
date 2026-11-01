// «server-4» → «💻 4», a phone → «📱 4» (owner 2026-11-01: «استبدل server بأيقونة كمبيوتر وقربه رقم»).
// Display only: the names stay as they are in the system.
export function stationTag (code, phone = false) {
  if (!code) return ''
  const n = (String(code).match(/\d+/) || [])[0]
  return (phone ? '📱 ' : '💻 ') + (n ?? code)
}
/** A phone station is named «هاتف … · <model>» (agent phone-*) */
export const isPhoneName = (name) => /هاتف|phone/i.test(String(name || ''))
