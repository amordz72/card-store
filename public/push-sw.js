// Phone notifications (owner 2026-10-30, Flexy Core 0111): shown with the app closed; a tap opens its page.
// Loaded by the generated service worker (quasar.config: importScripts). Plain JS, no imports.
/* eslint-disable no-restricted-globals */
self.addEventListener('push', (event) => {
  let data = {}
  try { data = event.data ? event.data.json() : {} } catch { data = { title: 'Flexy', body: event.data ? event.data.text() : '' } }
  const base = self.registration.scope
  event.waitUntil(self.registration.showNotification(data.title || 'Flexy', {
    body: data.body || '',
    tag: data.key || undefined,
    dir: 'rtl',
    lang: 'ar',
    icon: base + 'icons/icon-192x192.png',
    badge: base + 'icons/icon-128x128.png',
    data: { url: data.url || '/' }
  }))
})
self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const base = self.registration.scope
  const target = base + '#' + ((event.notification.data && event.notification.data.url) || '/')
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) if (c.url.startsWith(base) && 'focus' in c) { c.navigate(target).catch(() => {}); return c.focus() }
    return self.clients.openWindow(target)
  }))
})
