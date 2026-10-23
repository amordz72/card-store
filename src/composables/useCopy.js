import { Notify, copyToClipboard } from 'quasar'

export async function copyText (text) {
  try {
    await copyToClipboard(text)
    Notify.create({ type: 'positive', message: 'نُسخ ✓', timeout: 1200 })
    return true
  } catch {
    Notify.create({ type: 'negative', message: 'تعذّر النسخ' })
    return false
  }
}
