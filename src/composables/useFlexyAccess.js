import { ref } from 'vue'
import * as customerApi from 'src/api/customer'
import { useCustomerStore } from 'stores/customer'

// Is «فليكسي» enabled for the signed-in shop, and is sending open now? Shared by the menus and the page.
const enabled = ref(false)
const open = ref(false)
const maxAmount = ref(0)
const offers = ref(false)
// Prefixes whose ordinary credit this shop may send: Mobilis always, Djezzy/Ooredoo when the owner gave it a rate
const creditPrefixes = ref(['06'])
// Prefixes whose offers it may buy: Mobilis when it has the offers' rate, Ooredoo when it has its offers (v1.55)
const offerPrefixes = ref(['06'])
// What has a ready SIM now (store s185, owner 2026-11-01: «اربط العنوان بالهاردوير»): null = not known (before s185)
const supply = ref(null)
// The operators this shop may use, each with «available now» (shown on its page)
const operators = ref([])

export function useFlexyAccess () {
  const customer = useCustomerStore()
  async function refresh () {
    if (!customer.token) { enabled.value = false; return }
    try {
      const [s, sup] = await Promise.all([customerApi.flexyStatus(customer.token), customerApi.flexySupply(customer.token).catch(() => null)])
      supply.value = sup && typeof sup === 'object' ? sup : null
      // An operator with no ready SIM is greyed («غير متوفر حاليًا»); unknown supply changes nothing
      const has = (k) => supply.value == null || supply.value[k] !== false
      enabled.value = !!s.enabled
      open.value = !!s.open
      maxAmount.value = s.max_amount || 0
      offers.value = !!s.offers
      creditPrefixes.value = [...(s.mobilis && has('mobilis') ? ['06'] : []), ...(s.djezzy && has('djezzy') ? ['07'] : []), ...(s.ooredoo && has('ooredoo') ? ['05'] : [])]
      offerPrefixes.value = [...(s.offers && (has('sama') || has('mobilis')) ? ['06'] : []), ...(s.offers_ooredoo && has('ooredoo') ? ['05'] : []), ...(s.offers_djezzy && has('djezzy') ? ['07'] : [])]
      operators.value = [
        { key: 'mobilis', name: 'موبيليس', on: has('mobilis') || has('sama'), allowed: !!(s.mobilis || s.offers) },
        { key: 'ooredoo', name: 'أوريدو', on: has('ooredoo'), allowed: !!(s.ooredoo || s.offers_ooredoo) },
        { key: 'djezzy', name: 'جيزي', on: has('djezzy'), allowed: !!(s.djezzy || s.offers_djezzy) }
      ].filter((o) => o.allowed)
    } catch { /* keep the last value; the page shows its own errors */ }
  }
  return { enabled, open, maxAmount, offers, creditPrefixes, offerPrefixes, supply, operators, refresh }
}
