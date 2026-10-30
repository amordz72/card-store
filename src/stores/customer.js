import { defineStore } from 'pinia'
import { LocalStorage } from 'quasar'
import * as api from 'src/api/customer'
import { asciiDigits, normPhone } from 'src/api/format'

const TOKEN_KEY = 'cs_token'
const HIDE_KEY = 'cs_hide_amounts'

export const useCustomerStore = defineStore('customer', {
  state: () => ({
    token: LocalStorage.getItem(TOKEN_KEY) || null,
    profile: null,
    hideAmounts: LocalStorage.getItem(HIDE_KEY) === true
  }),

  getters: {
    signedIn: (s) => !!s.token
  },

  actions: {
    async login (phone, password) {
      // spaces, +213, Arabic digits: all accepted (owner 2026-10-30)
      const row = await api.login(normPhone(phone), asciiDigits(password))
      if (!row) return false
      this.token = row.session_token
      LocalStorage.set(TOKEN_KEY, this.token)
      await this.refresh()
      return true
    },

    async refresh () {
      this.profile = await api.me(this.token)
      return this.profile
    },

    async logout () {
      const t = this.token
      this.clear()
      if (t) await api.logout(t).catch(() => {})
    },

    clear () {
      this.token = null
      this.profile = null
      LocalStorage.remove(TOKEN_KEY)
    },

    toggleHide () {
      this.hideAmounts = !this.hideAmounts
      LocalStorage.set(HIDE_KEY, this.hideAmounts)
    }
  }
})
