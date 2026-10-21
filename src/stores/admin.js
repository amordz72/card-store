import { defineStore } from 'pinia'
import { supabase } from 'boot/supabase'
import * as api from 'src/api/admin'

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
      this.isAdmin = data.session ? await api.isAdmin().catch(() => false) : false
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
      this.$reset()
    }
  }
})
