import { defineStore } from 'pinia'
import { LocalStorage, Platform } from 'quasar'

const ACT_KEY = 'cs_last_activity'
const PREFS_KEY = 'cs_lock_prefs'   // { [accountKey]: { idleMin, bioId } } — per device

// Owner decision: lock after this long WITHOUT USE (not since opening): phone 3 h, computer 6 h
export const IDLE_OPTIONS = [
  { value: 15, label: '15 دقيقة' },
  { value: 60, label: 'ساعة' },
  { value: 180, label: '3 ساعات' },
  { value: 360, label: '6 ساعات' },
  { value: 900, label: '15 ساعة' }
]
const defaultIdle = () => (Platform.is.mobile ? 180 : 360)

export function markActive () {
  LocalStorage.set(ACT_KEY, Date.now())
}

export const useLockStore = defineStore('lock', {
  state: () => ({
    accountKey: null,
    hasPin: false,
    locked: false,
    idleMin: defaultIdle(),
    bioId: null
  }),

  getters: {
    enabled: (s) => s.hasPin
  },

  actions: {
    init (accountKey, hasPin) {
      this.accountKey = accountKey
      this.hasPin = !!hasPin
      const prefs = (LocalStorage.getItem(PREFS_KEY) || {})[accountKey] || {}
      this.idleMin = prefs.idleMin || defaultIdle()
      this.bioId = prefs.bioId || null
      this.locked = false
      if (!LocalStorage.getItem(ACT_KEY)) markActive()
      this.check()
    },

    savePrefs () {
      const all = LocalStorage.getItem(PREFS_KEY) || {}
      all[this.accountKey] = { idleMin: this.idleMin, bioId: this.bioId }
      LocalStorage.set(PREFS_KEY, all)
    },

    setIdle (min) { this.idleMin = min; this.savePrefs() },
    setBio (id) { this.bioId = id; this.savePrefs() },

    // called on a timer and when the app comes back to the screen
    check () {
      if (!this.enabled || this.locked) return
      const last = Number(LocalStorage.getItem(ACT_KEY) || 0)
      if (Date.now() - last > this.idleMin * 60000) this.locked = true
    },

    lock () { if (this.enabled) this.locked = true },
    unlock () { this.locked = false; markActive() },
    reset () { this.$reset() }
  }
})
