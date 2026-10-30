// «انسخ بيانات الدخول» (owner 2026-10-30): a ready WhatsApp message with the site, the phone and the password. The
// password is stored hashed, so it exists in clear only right when it is set: a new account, or a new password.
import { Dialog } from 'quasar'
import { copyText } from 'src/composables/useCopy'
import { normPhone } from 'src/api/format'

/** 8 digits, easy to type on a phone */
export function easyPassword () {
  const a = new Uint32Array(8)
  crypto.getRandomValues(a)
  return Array.from(a, (x) => x % 10).join('')
}

export const siteLink = () => window.location.origin + window.location.pathname

export function loginMessage (name, phone, password) {
  return `السلام عليكم ${name}\nرابط الموقع: ${siteLink()}\nرقم الهاتف: ${normPhone(phone)}\nكلمة السر: ${password}`
}

/** The message shown once, with «انسخ» (a fresh tap: the copy works on every phone) */
export function showLoginCopy (name, phone, password) {
  const text = loginMessage(name, phone, password)
  Dialog.create({ title: 'بيانات الدخول', message: text, style: 'white-space: pre-line', cancel: 'إغلاق', ok: { label: 'انسخ', icon: 'content_copy' }, persistent: true })
    .onOk(() => copyText(text))
}
