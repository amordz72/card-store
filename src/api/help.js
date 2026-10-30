import { ref } from 'vue'

// «أظهر الشروح» (owner 2026-10-30: «أستعمل البرنامج أكثر مما أبرمجه؛ القواعد تحت الأزرار تربكني»): every explanation of how
// the program works carries class «help» and is hidden; this switch on «حسابي» shows them again, on this device.
const KEY = 'cs_show_help'
const read = () => { try { return localStorage.getItem(KEY) === '1' } catch { return false } }
export const showHelp = ref(read())
export function applyHelp () { document.body.classList.toggle('show-help', showHelp.value) }
export function setShowHelp (on) {
  showHelp.value = on
  try { localStorage.setItem(KEY, on ? '1' : '0') } catch { /* private mode */ }
  applyHelp()
}
