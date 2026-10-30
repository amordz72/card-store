import { defineBoot } from '#q-app/wrappers'
import { perfNote } from 'src/api/perfLog'
import { weakFrom, weakHomeOn, isWeak } from 'src/api/weakHome'

// The start of the program (owner 2026-10-30):
//  * the «جاري التحميل» screen of index.html goes when the first page shows; how long it took is kept («سجل البطء»);
//  * after an update, a page file of the old version is gone: the page reloads itself once instead of staying white;
//  * weak internet on opening a heavy page: the light home page first, with «ارجع إلى …» (switch: weakHome.js).
const RELOAD_KEY = 'cs_chunk_reload'
function reloadOnce (why) {
  let last = 0
  try { last = Number(sessionStorage.getItem(RELOAD_KEY) || 0) } catch { /* private mode */ }
  // Once in a minute at most: a second failure shows the error screen instead of a loop
  if (Date.now() - last < 60000) {
    window.__bootFail?.(why)
    return
  }
  try { sessionStorage.setItem(RELOAD_KEY, String(Date.now())) } catch { /* private mode */ }
  location.reload()
}
const isChunkError = (e) => /dynamically imported module|Importing a module script failed|Loading chunk|Failed to fetch dynamically/i.test(String(e?.message || e))

export default defineBoot(({ router }) => {
  window.addEventListener('vite:preloadError', (e) => { e.preventDefault(); reloadOnce('vite:preloadError ' + (e.payload?.message || '')) })
  router.onError((err) => { if (isChunkError(err)) reloadOnce(String(err?.message || err)) })

  let first = true
  router.beforeEach((to) => {
    if (!first) return true
    first = false
    if (to.meta.heavy && weakHomeOn() && isWeak()) {
      weakFrom.value = { path: to.fullPath, title: to.meta.title || '' }
      return '/'
    }
    return true
  })
  router.isReady().then(() => {
    requestAnimationFrame(() => {
      const t0 = window.__bootT0
      if (t0) perfNote({ what: 'تحميل البرنامج', ms: Date.now() - t0, ok: true, status: 200 })
      document.getElementById('boot')?.remove()
    })
  }).catch((err) => window.__bootFail?.('الصفحة الأولى: ' + String(err?.message || err)))
})
