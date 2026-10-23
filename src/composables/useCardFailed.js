import { Dialog } from 'quasar'
import { newRequestId } from 'src/api/rpc'
import * as api from 'src/api/admin'

// «لم تعمل» on one of the shop's own cards (v1.29). Success needs no record: testing a card uses it.
// A failure voids that card and returns its cost to the shop balance; the rest of the order is unchanged.
export function askCardFailed (run, card, onDone) {
  const requestId = newRequestId()   // one id per confirmed report; a retry refunds once
  Dialog.create({
    title: 'البطاقة لم تعمل',
    message: `****${String(card.code).slice(-4)}: تصبح ملغاة ويعود سعر شرائها لرصيد المحل. ما كان رد الشبكة؟`,
    options: {
      type: 'radio',
      model: 'used',
      items: [
        { label: 'مستعملة (is used)', value: 'used' },
        { label: 'غير موجودة (does not exist)', value: 'not_found' },
        { label: 'رد آخر', value: 'other' }
      ]
    },
    cancel: 'رجوع',
    ok: { label: 'لم تعمل', color: 'negative' }
  }).onOk(async (result) => {
    const r = await run(() => api.cardFailed(card.id, result, requestId),
      { success: 'سُجّلت البطاقة «لم تعمل» وعاد سعرها لرصيد المحل.' })
    if (r) onDone()
  })
}
