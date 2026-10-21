import { Notify, copyToClipboard } from 'quasar'

export function copyText (text) {
  copyToClipboard(text)
    .then(() => Notify.create({ type: 'positive', message: 'نُسخ ✓', timeout: 1200 }))
    .catch(() => Notify.create({ type: 'negative', message: 'تعذّر النسخ' }))
}
