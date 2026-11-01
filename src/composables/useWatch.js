// «لوحة المراقبة» (owner 2026-11-01): one reading of the computers, phones, SIMs and the card stock, shared by the
// home card and the dashboard. Read only (Flexy Core «devices» + store «تكاد تنفد»); refreshed every `every` ms.
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import * as flexy from 'src/api/flexy'
import * as admin from 'src/api/admin'
import { supabase } from 'boot/supabase'

export const MIN_BALANCE = 1000
const SNOOZE_KEY = 'watch.snooze'
export const isPhone = (st) => !!st?.phone || String(st?.agent_version || '').startsWith('phone-')
export const isOff = (st) => (typeof st?.off === 'boolean' ? st.off : !!st?.absent_minutes)
export const stNo = (st) => Number((String(st?.code || '').match(/\d+/) || [])[0] ?? 999)

const readSnooze = () => { try { return JSON.parse(localStorage.getItem(SNOOZE_KEY) || '{}') } catch { return {} } }

const BY_TYPE = [['mobilis-sama', 'سما'], ['mobilis-arsselli', 'أرسلي'], ['ooredoo-flexy', 'أوريدو'], ['djezzy-flexy', 'جيزي']]

export function useWatch (every = 20000) {
  const tree = ref(null)
  const low = ref(null)
  const error = ref('')
  const loading = ref(false)
  const at = ref(null)
  const snooze = ref(readSnooze())

  // «🐢» (owner 2026-11-01: «هل هو ثقل من الإنترنت أو من السيرفر؟ لماذا لا يذكره البرنامج؟»): a tiny database call against a
  // tiny file of the site, both timed; only the database slow = the server, both slow = the internet
  const speed = ref(null)
  async function probe () {
    const t = (f) => { const a = performance.now(); return f().then(() => performance.now() - a, () => Infinity) }
    const [db, web] = await Promise.all([
      t(() => supabase.rpc('store_site_links').then((r) => { if (r.error) throw r.error })),
      t(() => fetch(location.href.split('#')[0] + (location.href.includes('?') ? '&' : '?') + 'ping=' + Date.now(), { method: 'HEAD', cache: 'no-store' }))
    ])
    const level = db > 3000 && web < 1500 ? 'server' : db > 2500 && web > 2000 ? 'internet' : db > 3000 ? 'server' : null
    speed.value = { db: Math.round(db), web: Math.round(web), level }
  }

  async function load () {
    probe()
    if (loading.value) return
    loading.value = true
    try {
      const [d, l] = await Promise.all([flexy.ownerDevices(), admin.lowStock().catch(() => null)])
      if (d.status === 200 && d.body?.ok) { tree.value = d.body; error.value = '' } else error.value = d.body?.error || 'FLEXY_CORE'
      if (l) low.value = l
      at.value = Date.now()
    } catch (e) {
      error.value = e.message || 'NETWORK'
    } finally {
      loading.value = false
    }
  }

  const labels = computed(() => tree.value?.modem_labels || {})
  const limits = computed(() => tree.value?.sim_limits?.limits || {})
  const minOf = (sim) => limits.value[sim?.sim_uuid]?.min_balance ?? MIN_BALANCE
  // Every live computer and phone, by number (phones after computers), each with its SIMs
  const stations = computed(() => (tree.value?.stations || []).filter((s) => s.level !== 'old')
    .map((st) => ({
      st, phone: isPhone(st), off: isOff(st),
      sims: (st.modems || []).filter((m) => m.sim && m.level !== 'old').map((m) => {
        const sim = m.sim
        const ready = (m.sim_state || (isOff(st) ? 'station_off' : m.level === 'down' ? 'needs_action' : 'ready')) === 'ready'
        // A phone's slot is the app's own (Rech-Doom 0.9.3: SIM 1 = 127.0.0.3, SIM 2 = 127.0.0.2), never a typed label
        const slot = isPhone(st) ? (m.ip === '127.0.0.3' ? 'SIM-1' : 'SIM-2') : 'USB-' + ((m.modem_uuid && labels.value[m.modem_uuid]) || m.usb || '?')
        const lowBal = sim.balance != null && sim.balance <= minOf(sim)
        return { st, m, sim, ready, slot, lowBal, why: (m.reasons || []).map((r) => r.text).join(' · ') }
      }).sort((a, b) => (Number(String(a.slot).replace(/\D/g, '')) || 999) - (Number(String(b.slot).replace(/\D/g, '')) || 999))
    }))
    .sort((a, b) => (a.phone - b.phone) || stNo(a.st) - stNo(b.st)))
  const sims = computed(() => stations.value.flatMap((s) => s.sims))
  const lowItems = computed(() => low.value?.items || [])

  // What needs the owner now; a snoozed one comes back by itself when its time is over
  const problems = computed(() => {
    const out = []
    for (const s of stations.value) {
      if (s.off) out.push({ key: 'pc:' + s.st.station_uuid, level: 'down', icon: s.phone ? '📱' : '💻', text: (s.phone ? '📱' : '💻') + stNo(s.st) + ' مطفأ', to: '/flexy/devices?station=' + encodeURIComponent(s.st.code || '') })
    }
    for (const x of sims.value) {
      if (!x.ready && !x.st.off) out.push({ key: 'sim:' + x.sim.sim_uuid + ':down', level: 'down', text: (x.phone ? '📱' : '💻') + stNo(x.st) + ' / ' + x.slot + ' / ' + (x.sim.code || 'شريحة') + (x.why ? ': ' + x.why : ''), to: '/flexy/devices?sim=' + encodeURIComponent(x.sim.code || '') })
      if (x.lowBal) out.push({ key: 'sim:' + x.sim.sim_uuid + ':low', level: 'warn', text: (x.sim.code || 'شريحة') + ': رصيد ' + Math.round(x.sim.balance).toLocaleString('en-US') + ' دج (الحد ' + minOf(x.sim).toLocaleString('en-US') + ')', to: '/flexy/devices?sim=' + encodeURIComponent(x.sim.code || '') })
    }
    for (const it of lowItems.value) out.push({ key: 'stock:' + it.product_id, level: 'warn', text: '🃏 ' + (it.brand ? it.brand + ' · ' : '') + it.name + ': بقي ' + it.left, to: '/stock?tab=low' })
    const now = Date.now()
    return out.filter((p) => !(snooze.value[p.key] > now))
  })
  const counts = computed(() => ({
    pcOn: stations.value.filter((s) => !s.off).length,
    pcAll: stations.value.length,
    simReady: sims.value.filter((x) => x.ready).length,
    simAll: sims.value.length,
    lowBal: sims.value.filter((x) => x.lowBal).length,
    lowStock: lowItems.value.length,
    // Per kind of SIM (owner 2026-11-01: «ستة متاحة… أين نعرف العدد كل متعامل؟»): ready/all and under its floor
    byType: BY_TYPE.map(([t, name]) => {
      const of = sims.value.filter((x) => x.sim.sim_type === t)
      return { t, name, ready: of.filter((x) => x.ready).length, all: of.length, low: of.filter((x) => x.lowBal).length }
    }).filter((x) => x.all > 0)
  }))
  function hide (key, minutes) {
    snooze.value = { ...snooze.value, [key]: Date.now() + minutes * 60000 }
    try { localStorage.setItem(SNOOZE_KEY, JSON.stringify(snooze.value)) } catch { /* private mode */ }
  }

  let timer = null
  onMounted(() => { load(); timer = setInterval(() => { if (document.visibilityState === 'visible') load() }, every) })
  onBeforeUnmount(() => clearInterval(timer))
  return { tree, low, error, loading, at, load, stations, sims, lowItems, problems, counts, hide, minOf, speed }
}
