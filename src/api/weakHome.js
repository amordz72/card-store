import { ref } from 'vue'

// Weak internet on opening a heavy page (owner 2026-10-30: «انقلني إلى صفحة بلا حمل، ثم أرجع أنا»): the home page
// first, and a line «ارجع إلى …». On by default ('auto'); «لا تفعل هذا» turns it off on this device, and the account
// page turns it back on.
const KEY = 'cs_weak_home'
export const weakFrom = ref(null)
export function weakHomeOn () {
  try { return localStorage.getItem(KEY) !== 'off' } catch { return true }
}
export function setWeakHome (on) {
  try { localStorage.setItem(KEY, on ? 'auto' : 'off') } catch { /* private mode */ }
}
/** Weak: the phone says 2G or under 0.5 Mbps, or the program itself took more than 8 s to arrive. */
export function isWeak () {
  const c = navigator.connection
  if (c && (['slow-2g', '2g'].includes(c.effectiveType) || (c.downlink && c.downlink < 0.5))) return true
  const t0 = window.__bootT0
  return !!t0 && Date.now() - t0 > 8000
}
