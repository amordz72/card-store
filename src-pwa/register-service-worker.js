import { register } from 'register-service-worker'
import { Notify } from 'quasar'

// The new service worker takes over at once (skipWaiting + clientsClaim), but the open page still runs
// the old code until it reloads. Tell the user instead of leaving an old version on screen; reloading is
// his choice so nothing typed is lost. A long-open app also checks for a new version every hour and on return.

register(process.env.SERVICE_WORKER_FILE, {
  registered (registration) {
    const check = () => registration.update().catch(() => {})
    setInterval(check, 60 * 60 * 1000)
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') check() })
  },

  updated () {
    Notify.create({
      message: 'يوجد تحديث للتطبيق',
      icon: 'system_update',
      color: 'primary',
      timeout: 0,
      position: 'bottom',
      actions: [
        { label: 'تحديث الآن', color: 'white', handler: () => window.location.reload() },
        { label: 'لاحقًا', color: 'white' }
      ]
    })
  }
})
