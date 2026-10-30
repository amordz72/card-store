import { defineStore } from 'pinia'
import { supabase } from 'boot/supabase'
import { LocalStorage } from 'quasar'
import * as api from 'src/api/admin'

// The last email confirmed admin on this device (owner 2026-10-30: «ينقطع الإنترنت فأخرج من الجلسة»): with no internet
// on opening, the session stays the admin's instead of the login page. Only the screens trust it; every action
// is checked again by the server.
const OK_KEY = 'cs_admin_ok'

export const useAdminStore = defineStore('admin', {
  state: () => ({
    checked: false,
    isAdmin: false,
    email: null
  }),

  actions: {
    // Called by the router guard; caches the result for the session
    async check () {
      if (this.checked) return this.isAdmin
      const { data } = await supabase.auth.getSession()
      this.email = data.session?.user?.email || null
      if (!data.session) this.isAdmin = false
      else {
        try {
          this.isAdmin = !!(await api.isAdmin())
          if (this.isAdmin) LocalStorage.set(OK_KEY, this.email)
          else LocalStorage.remove(OK_KEY)
        } catch (e) {
          // No answer (no internet, a slow network): the last confirmed answer on this device
          this.isAdmin = (e?.code === 'NETWORK' || !navigator.onLine) && LocalStorage.getItem(OK_KEY) === this.email
        }
      }
      this.checked = true
      return this.isAdmin
    },

    async login (email, password) {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) return false
      this.checked = false
      return this.check()
    },

    async logout () {
      await supabase.auth.signOut()
      LocalStorage.remove(OK_KEY)
      this.$reset()
    }
  }
})
