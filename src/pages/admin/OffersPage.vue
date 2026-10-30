<template>
  <!-- The offers screen (Flexy Core 0062, owner 2026-10-29): operator → group → two modes of the same offers.
       الأصل: each offer where the network puts it (page, code, network name), its activation, audience and price;
       the approved version «المعتمدة · النسخة N», the network's changes in «جديدة» (with «ماذا تغيّر» and «اعتماد»),
       older versions as rows at the bottom («رفع»). المشاهدة: the opened offers as the send page shows them, in the
       owner's order (drag ⠿), with their display text, details, section and a temporary hide; filter الكل / زبون. -->
  <q-page class="q-pa-md column q-gutter-sm page">
    <SectionTabs :tabs="ADMIN_TABS" :links="ADMIN_LINKS" />
    <div class="row items-center q-gutter-xs">
      <q-btn v-for="o in OPERATORS" :key="o.key" dense no-caps rounded :unelevated="operator === o.key" :outline="operator !== o.key"
        :color="operator === o.key ? 'primary' : 'grey-7'" :label="o.label" @click="operator = o.key" />
      <q-space />
      <q-btn v-if="group" dense no-caps :unelevated="editing" :outline="!editing" color="deep-orange" size="sm"
        :icon="editing ? 'check' : 'edit'" label="تعديل" @click="editing = !editing" />
    </div>
    <div v-if="groupNames.length" class="row q-gutter-xs">
      <q-btn v-for="g in groupNames" :key="g" dense no-caps rounded size="sm" :unelevated="group === g" :outline="group !== g"
        :color="group === g ? 'deep-orange' : 'grey-7'" @click="group = g">
        {{ chipLabel(g) }}<span v-if="infoOf(g).draft_source" class="dot">●</span>
      </q-btn>
    </div>
    <div v-if="group" class="modes row no-wrap">
      <div class="col" :class="{ on: mode === 'origin' }" role="button" tabindex="0" @click="mode = 'origin'">الأصل</div>
      <div class="col dv" :class="{ on: mode === 'display' }" role="button" tabindex="0" @click="mode = 'display'">المشاهدة</div>
    </div>

    <div v-if="error" class="small text-negative">{{ error }}</div>
    <div v-if="loading" class="row justify-center q-pa-lg"><q-spinner color="primary" size="28px" /></div>
    <div v-else-if="operator === 'mobilis'" class="card text-center muted q-pa-lg">عروض هذا المتعامل تُضاف لاحقًا بنفس الطريقة.</div>
    <div v-else-if="!group" class="card text-center muted q-pa-lg">لا مجموعة بعد: افتح رقمًا في «إرسال فليكسي» لتُستكشف قائمته.</div>

    <!-- الأصل -->
    <template v-else-if="mode === 'origin'">
      <div class="tabs row no-wrap">
        <div class="col tab" :class="{ on: tab === 'approved' }" role="button" tabindex="0" @click="tab = 'approved'">
          المعتمدة<span v-if="approved.length"> · النسخة {{ info.version }}</span>
        </div>
        <div v-if="hasDraft" class="col tab" :class="{ on: tab === 'draft' }" role="button" tabindex="0" @click="tab = 'draft'">
          جديدة <span class="dot">●</span>
        </div>
      </div>

      <template v-if="tab === 'approved' || !hasDraft">
        <!-- «إلغاء النسخة» on top, under the tabs (owner 2026-10-29: it was below the long list) -->
        <q-btn v-if="editing && approved.length" outline no-caps color="negative" icon="block" :label="'إلغاء النسخة ' + info.version"
          :disable="acting" @click="withdraw" />
        <div v-if="!approved.length" class="card muted small q-pa-md">
          لا نسخة معتمدة لهذه المجموعة بعد: لا يُباع منها شيء إلا ما تستكشفه أنت.
          افتح رقمًا منها في «إرسال فليكسي» لتُقرأ قائمته، أو ارفع نسخة قديمة من الأسفل.
        </div>
        <div v-else class="card">
          <!-- Edit mode: tick several offers, then one bar changes their audience or activation (owner 2026-10-29) -->
          <div v-if="editing" class="pg row items-center q-gutter-xs">
            <q-checkbox :model-value="allPicked" dense size="sm" color="deep-orange" :label="'تحديد الكل (' + pickable.length + ')'" @update:model-value="pickAll" />
          </div>
          <template v-for="p in pagesOf(approved)" :key="p.key">
            <div class="pg">{{ p.label }}</div>
            <div v-for="o in p.rows" :key="o.id" class="orow" :class="{ off: !o.active || o.status === 'doubt', picked: picked.has(o.id) }">
              <q-checkbox v-if="editing" :model-value="picked.has(o.id)" dense size="sm" color="deep-orange" :disable="!canPick(o)"
                @update:model-value="(v) => pick(o, v)" />
              <div class="col">
                <div class="nm"><span class="code">{{ o.code }}</span> · <bdi dir="auto">{{ o.nameNetwork }}</bdi></div>
                <div class="meta">
                  يظهر: «<bdi dir="auto">{{ o.nameDisplay }}</bdi>»<span v-if="o.hidden"> · مخفي مؤقتًا</span><span v-if="o.status === 'tested'"> · مجرّب ✓</span>
                  <span v-if="o.status === 'doubt'" class="text-negative"> · الرمز ظهر مرتين في القائمة: لا يُرسل</span>
                </div>
                <div v-if="o.probe" class="meta" :class="o.probe.price === o.price ? 'text-positive' : 'text-negative'">{{ probeText(o) }}</div>
                <!-- «اعتماد الرمز» (Flexy Core 0065): the probe named this offer's price for its code shown twice -->
                <q-btn v-if="canApproveProbe(o)" dense unelevated no-caps size="sm" color="positive" class="q-mt-xs"
                  :label="'اعتماد الرمز ' + o.code + ' لهذا العرض'" :loading="busy === o.id" @click="approveProbe(o)" />
              </div>
              <div v-if="!editing" class="row items-center no-wrap q-gutter-xs">
                <span class="price">{{ o.price ? num(o.price) : '—' }}</span>
                <span class="tag" :class="tagOf(o).cls">{{ tagOf(o).label }}</span>
              </div>
              <div v-else class="row items-center no-wrap q-gutter-xs">
                <span class="pchip" role="button" tabindex="0" @click="editPrice(o)">{{ o.price ? num(o.price) : 'سعر؟' }}</span>
                <q-toggle :model-value="o.active" dense color="positive" :disable="busy === o.id" @update:model-value="(v) => save(o, { active: v })" />
                <q-btn-toggle :model-value="o.audience" dense no-caps unelevated size="sm" toggle-color="deep-orange" :disable="busy === o.id"
                  :options="AUDIENCE" @update:model-value="(v) => save(o, { audience: v })" />
              </div>
            </div>
          </template>
        </div>
        <div v-if="editing && approved.length" class="help small muted q-px-sm">لا يتغير هنا اسم ولا ترتيب: مكانهما في المشاهدة.</div>
        <!-- «صيغ»: how many numbers are decided on this variant; whether an exact menu match sells by itself -->
        <div v-if="approved.length" class="card q-pa-sm column q-gutter-xs">
          <div class="small muted">{{ info.numbers ? info.numbers + ' رقمًا على هذه الصيغة' : 'لا رقم محسوم على هذه الصيغة بعد' }}<span v-if="(info.label || group) !== group"> · الاسم: {{ info.label }}</span></div>
          <q-checkbox v-if="editing" :model-value="info.auto_exact !== false" dense size="sm" color="positive" :disable="acting"
            label="البيع تلقائيًا عند المطابقة التامة (مطفأ: يسألني أولًا لكل رقم)" @update:model-value="(v) => act('auto_exact', v ? 'on' : 'off')" />
        </div>
      </template>

      <!-- جديدة: the network's new shape (or a raised version) beside what changed; the approved one goes on selling -->
      <template v-else>
        <div v-if="raised" class="small text-purple-8 q-px-sm">النسخة {{ raised }} مرفوعة من الأرشيف كما كانت. لا يتغير شيء حتى تضغط «اعتماد».</div>
        <div v-else-if="approved.length" class="help small muted q-px-sm">هذا ما تُظهره الشبكة الآن. المعتمدة تبقى تُباع حتى تعتمد هذه.</div>
        <div v-else class="small muted q-px-sm">{{ variantNo ? 'صيغة جديدة حُفظت وحدها' : 'مجموعة جديدة' }}: {{ draft.length }} عرضًا من الشبكة. تراها أنت (الإدارة) وحدك حتى تفتحها.</div>
        <div v-if="approved.length && !raised" class="card chg">
          <div class="chg-h">ماذا تغيّر عن المعتمدة</div>
          <div v-if="!changeCount" class="chg-r muted">لا فرق بعد.</div>
          <div v-for="a in changes.added" :key="'a' + a.name" class="chg-r"><span class="plus">+ جديد</span><span><bdi dir="auto">{{ a.name }}</bdi> (الصفحة {{ a.page }}{{ a.price ? ' · ' + num(a.price) : '' }})</span></div>
          <div v-for="g in changes.gone" :key="'g' + g.name" class="chg-r"><span class="minus">− اختفى</span><span><bdi dir="auto">{{ g.name }}</bdi></span></div>
          <div v-for="c in changes.changed" :key="'c' + c.name" class="chg-r"><span class="mod">≠ تغيّر</span><span><bdi dir="auto">{{ c.name }}</bdi>: {{ diffText(c) }}</span></div>
        </div>
        <div class="row q-gutter-sm">
          <q-btn class="col" unelevated no-caps color="positive" icon="check" :label="'اعتماد النسخة ' + nextVersion" :loading="acting" @click="approve" />
          <q-btn outline no-caps color="grey-8" label="إلغاء" :disable="acting" @click="discard" />
        </div>
        <!-- «افتح للمحلات كما هي» (Flexy Core 0074): a quick approval, the network's names and prices, from the smallest -->
        <q-btn v-if="!approved.length && !raised" unelevated no-caps color="cyan-9" icon="storefront" label="افتح للمحلات كما هي"
          :loading="acting" @click="openAll" />
        <div class="small muted q-px-sm">
          قراراتك (التفعيل، من يراه، النص الظاهر، الترتيب) تبقى للعروض التي بقيت؛ العرض الجديد يُفتح للإدارة إن كان له سعر.
        </div>
        <div class="card">
          <template v-for="p in pagesOf(draft)" :key="p.key">
            <div class="pg">{{ p.label }}</div>
            <div v-for="o in p.rows" :key="o.id" class="orow">
              <div class="col">
                <div class="nm"><span class="code">{{ o.code }}</span> · <bdi dir="auto">{{ o.nameNetwork }}</bdi>
                  <span v-if="markOf(o)" class="tag" :class="markOf(o).cls">{{ markOf(o).label }}</span>
                </div>
                <div class="meta">
                  يظهر: «<bdi dir="auto">{{ shownNameOf(o) }}</bdi>»
                  <span v-if="o.status === 'doubt'" class="text-negative"> · الرمز ظهر مرتين في القائمة: لا يُرسل</span>
                </div>
                <div v-if="o.probe" class="meta" :class="o.probe.price === o.price ? 'text-positive' : 'text-negative'">{{ probeText(o) }}</div>
              </div>
              <div class="row items-center no-wrap q-gutter-xs">
                <span class="price">{{ (o.priceSeen ?? o.price) ? num(o.priceSeen ?? o.price) : '—' }}</span>
                <span class="tag" :class="decisionOf(o).cls">{{ decisionOf(o).label }}</span>
              </div>
            </div>
          </template>
        </div>
      </template>

    </template>

    <!-- المشاهدة: as the send page shows them -->
    <template v-else>
      <div class="row q-gutter-xs">
        <q-btn v-for="f in FILTERS" :key="f.value" dense no-caps rounded size="sm" :unelevated="filter === f.value" :outline="filter !== f.value"
          :color="filter === f.value ? 'deep-orange' : 'grey-7'" :label="f.label" @click="filter = f.value" />
      </div>
      <div v-if="editing" class="hint">⠿ اسحب لتنقل العرض · اضغط على العرض لتعديله</div>
      <div v-if="!opened.length" class="card text-center muted q-pa-lg">لا عروض مفعّلة بعد. فعّلها من «الأصل» في وضع التعديل.</div>
      <template v-else>
        <div v-for="s in SECTIONS" v-show="editing || sections[s.key].length" :key="s.key" class="card" :class="{ net: s.key === 'internet' }" :data-sec="s.key">
          <div class="sec" :class="{ 'net-t': s.key === 'internet' }">{{ s.label }}</div>
          <div v-if="editing && !sections[s.key].length" class="slot">أفلت هنا</div>
          <div v-for="o in sections[s.key]" :key="o.id" class="drow" :class="{ off: o.hidden, dragging: drag?.id === o.id }" :data-row="o.id"
            role="button" tabindex="0" @click="editing && openSheet(o)">
            <div class="row items-center no-wrap q-gutter-sm">
              <span v-if="editing" class="hd" @pointerdown="startDrag($event, o)" @click.stop>⠿</span>
              <div class="column">
                <span class="text-weight-bold"><bdi dir="auto">{{ o.nameDisplay }}</bdi>
                  <span v-if="o.audience === 'admin'" class="tag t-adm">إدارة</span></span>
                <span v-if="o.hidden" class="meta">🚫 مخفي مؤقتًا</span>
                <span v-else-if="o.details" class="meta"><bdi dir="auto">{{ o.details }}</bdi></span>
              </div>
            </div>
            <span class="price" :class="{ 'net-p': s.key === 'internet' }">{{ money(o.price) }}</span>
          </div>
        </div>
      </template>
    </template>

    <!-- Old versions: at the bottom in both modes (owner 2026-10-29) -->
    <div v-if="!loading && operator !== 'mobilis' && group && info.versions?.length" class="card">
      <div class="pg">النسخ القديمة</div>
      <div v-for="v in info.versions" :key="v.version" class="orow">
        <span class="small">النسخة {{ v.version }} · {{ clock(v.archived_at) }} · {{ v.count }} عرضًا</span>
        <q-btn dense outline no-caps size="sm" color="purple-7" icon="upload" label="رفع" :disable="acting" @click="raise(v)" />
      </div>
    </div>

    <!-- The picked offers' bar: audience or activation for all of them, one confirmation -->
    <div v-if="editing && picked.size" class="bulkbar row items-center no-wrap q-gutter-xs">
      <span class="text-weight-bold">{{ picked.size }} محدد</span>
      <q-space />
      <q-btn dense unelevated no-caps size="sm" color="positive" label="للزبائن" :loading="bulkBusy" @click="applyBulk({ audience: 'all' })" />
      <q-btn dense outline no-caps size="sm" color="amber-9" label="إدارة فقط" :disable="bulkBusy" @click="applyBulk({ audience: 'admin' })" />
      <q-btn dense outline no-caps size="sm" color="positive" label="تفعيل" :disable="bulkBusy" @click="applyBulk({ active: true })" />
      <q-btn dense outline no-caps size="sm" color="grey-8" label="إيقاف" :disable="bulkBusy" @click="applyBulk({ active: false })" />
      <q-btn flat dense round size="sm" icon="close" aria-label="إلغاء التحديد" @click="picked = new Set()" />
    </div>

    <!-- An offer of the display mode: its display text, details, section and temporary hide -->
    <q-dialog v-model="sheetOpen" position="bottom">
      <q-card v-if="sheet" class="sheet">
        <q-card-section class="q-pb-none">
          <div class="text-h6"><bdi dir="auto">{{ sheet.row.nameDisplay }}</bdi></div>
          <div class="meta">في الشبكة: {{ sheet.row.code }} · <bdi dir="auto">{{ sheet.row.nameNetwork }}</bdi> · السعر {{ num(sheet.row.price) }} · {{ sheet.row.audience === 'all' ? 'الكل' : 'إدارة' }}</div>
        </q-card-section>
        <q-card-section class="column q-gutter-sm">
          <q-input v-model="sheet.name" dense outlined label="النص الظاهر (يراه الجميع)" maxlength="80" />
          <q-input v-model="sheet.details" dense outlined label="التفاصيل" maxlength="200" />
          <div class="row items-center q-gutter-sm">
            <span class="small muted">القسم</span>
            <q-btn-toggle v-model="sheet.category" dense no-caps unelevated toggle-color="cyan-9" :options="SECTIONS.map((s) => ({ label: s.label, value: s.key }))" />
            <!-- A suggestion from the network's name, never applied by itself (owner 2026-10-29) -->
            <q-btn v-if="sheet.category !== 'internet' && /\d+\s*go\b/i.test(sheet.row?.nameNetwork || '')" flat dense no-caps size="sm"
              color="cyan-9" label="مقترح: إنترنت" @click="sheet.category = 'internet'" />
          </div>
          <q-toggle v-model="sheet.hidden" label="إخفاء مؤقت (يبقى مفعّلًا في الأصل)" color="deep-orange" />
        </q-card-section>
        <q-card-actions>
          <q-btn class="col" unelevated no-caps color="cyan-9" label="حفظ" :loading="busy === sheet.row.id" @click="saveSheet" />
          <q-btn class="col" flat no-caps label="إلغاء" v-close-popup />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import SectionTabs from 'src/components/SectionTabs.vue'
import { ADMIN_TABS, ADMIN_LINKS } from 'src/api/sections'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { Dialog, Notify } from 'quasar'
import * as flexy from 'src/api/flexy'
import { money } from 'src/api/format'

const OPERATORS = [{ key: 'mobilis', label: 'موبيليس' }, { key: 'djezzy', label: 'جيزي' }, { key: 'ooredoo', label: 'أوريدو' }]
const AUDIENCE = [{ label: 'إدارة', value: 'admin' }, { label: 'الكل', value: 'all' }]
const FILTERS = [{ label: 'الكل', value: 'all' }, { label: 'زبون', value: 'customer' }]
const SECTIONS = [{ key: 'bundle', label: 'باقات' }, { key: 'internet', label: 'إنترنت' }]
const ERRORS = {
  CATALOG_PRICE_REQUIRED: 'اكتب سعر العرض أولًا، ثم فعّله.',
  CATALOG_OFFER_IN_DOUBT: 'رمز هذا العرض ظهر مرتين في القائمة: لا يُفعّل حتى نفهمه.',
  CATALOG_NOT_FOUND: 'العرض لم يعد موجودًا: حدّث الصفحة.',
  CATALOG_BAD_REQUEST: 'قيمة غير صحيحة.',
  NOTHING_TO_APPROVE: 'لا نسخة جديدة لتعتمدها.',
  NOTHING_APPROVED: 'لا نسخة معتمدة لتلغيها.',
  VERSION_NOT_FOUND: 'النسخة غير موجودة.',
  PROBE_NOT_MATCHING: 'آخر كشف لا يطابق سعر هذا العرض: اكشف من جديد.'
}

const operator = ref('ooredoo')
const group = ref('')
const mode = ref('origin')
const tab = ref('approved')
const filter = ref('all')
const editing = ref(false)
const rows = ref([])
const groupInfo = ref([])
const loading = ref(false)
const busy = ref(null)
const acting = ref(false)
const error = ref('')

const num = (n) => (n ? Number(n).toLocaleString('en-US') : '—')
const clock = (v) => (v ? new Date(v).toLocaleString('ar-DZ') : '—')
const infoOf = (g) => groupInfo.value.find((x) => x.grp === g) || {}
// «صيغ» (Flexy Core 0067): variants of a label are keyed «GOLD», «GOLD 2»…; the chip shows the label and the variant
const chipLabel = (g) => {
  const i = infoOf(g)
  const label = i.label || g
  const suffix = g.startsWith(label) ? g.slice(label.length).trim() : g
  return suffix && suffix !== g ? label + ' · صيغة ' + suffix : label === g ? g : label + ' · ' + g
}
const groupNames = computed(() => [...new Set([...groupInfo.value.map((g) => g.grp), ...rows.value.map((o) => o.group)])])
const info = computed(() => infoOf(group.value))
const approved = computed(() => rows.value.filter((o) => o.group === group.value && !o.draft))
const draft = computed(() => rows.value.filter((o) => o.group === group.value && o.draft))
const hasDraft = computed(() => Boolean(info.value.draft_source) || draft.value.length > 0)
const raised = computed(() => /^version:(\d+)$/.exec(info.value.draft_source || '')?.[1] || '')
const changes = computed(() => info.value.changes || { added: [], gone: [], changed: [] })
const changeCount = computed(() => changes.value.added.length + changes.value.gone.length + changes.value.changed.length)
// The number «اعتماد» gives (as the core does): after the approved one and every archived one
const nextVersion = computed(() => {
  const top = Math.max(0, ...(info.value.versions || []).map((v) => v.version))
  const at = Math.max(info.value.version || 1, top + 1)
  return approved.value.length ? at + 1 : at
})

// The network's order: page by page (its path), then the offer's place in the page
const pathText = (p) => (p || []).map((x) => (x === '0' ? 'المزيد' : x)).join(' ثم ')
function pagesOf (list) {
  const sorted = [...list].sort((a, b) => a.page - b.page || pathText(a.execPath).localeCompare(pathText(b.execPath)) || a.pos - b.pos || a.id - b.id)
  const out = []
  for (const o of sorted) {
    const key = o.page + '|' + (o.execPath || []).join(',')
    let p = out.find((x) => x.key === key)
    if (!p) out.push(p = { key, label: 'الصفحة ' + o.page + (o.execPath?.length ? ' (' + pathText(o.execPath) + ')' : ''), rows: [] })
    p.rows.push(o)
  }
  return out
}
// A code shown twice, resolved by an approved probe of this code and price (Flexy Core 0065)
const resolved = (o) => o.probeOk && o.probe && o.probe.code === o.code && o.probe.price === o.price
const canApproveProbe = (o) => !o.draft && o.status === 'doubt' && !resolved(o) && o.probe && o.probe.code === o.code && o.probe.price === o.price
const tagOf = (o) => (o.status === 'doubt' && !resolved(o) ? { label: 'مشكوك', cls: 't-off' }
  : !o.active ? { label: 'غير مفعّل', cls: 't-off' }
    : o.audience === 'all' ? { label: 'الكل', cls: 't-all' } : { label: 'إدارة', cls: 't-adm' })
// In «جديدة»: the decision the offer will keep after «اعتماد» (the approved row's, or the raised version's own)
const approvedOf = (o) => approved.value.find((a) => a.nameNetwork === o.nameNetwork)
function decisionOf (o) {
  if (raised.value) return tagOf(o)
  const a = approvedOf(o)
  if (a) return tagOf(a)
  return (o.priceSeen ?? o.price) && o.status !== 'doubt' ? { label: 'إدارة', cls: 't-adm' } : { label: 'غير مفعّل', cls: 't-off' }
}
const shownNameOf = (o) => (raised.value ? o.nameDisplay : approvedOf(o)?.nameDisplay || o.nameNetwork)
function markOf (o) {
  if (raised.value || !approved.value.length) return null
  if (changes.value.added.some((a) => a.name === o.nameNetwork)) return { label: '+ جديد', cls: 't-new' }
  if (changes.value.changed.some((c) => c.name === o.nameNetwork)) return { label: '≠ تغيّر', cls: 't-chg' }
  return null
}
// «اكشف» on a code shown twice (Flexy Core 0064): the network's price, kept beside the offer as evidence
const probeText = (o) => 'كشف ' + clock(o.probe.at) + ': الرمز ' + o.probe.code + ' = ' + num(o.probe.price) + ' دج' +
  (o.probe.price === o.price ? ' ✓ يطابق هذا العرض' : ' ✗ لا يطابق هذا العرض') + (resolved(o) ? ' · معتمد: يُباع بحراسة السعر' : '')
async function approveProbe (o) {
  Dialog.create({
    title: 'اعتماد الرمز ' + o.code + ' لـ' + o.nameNetwork,
    message: 'الكشف قال إن الرمز ' + o.code + ' يعطي ' + num(o.probe.price) + ' دج = هذا العرض. يُفتح لك أنت فقط (الإدارة)، والـPIN لا يُرسل إلا إذا قالت الشبكة نفس السعر. العرض الآخر بنفس الرمز يبقى موقوفًا.',
    cancel: 'رجوع',
    ok: 'اعتمد'
  }).onOk(async () => {
    busy.value = o.id
    try {
      const r = await flexy.ownerOfferProbeApprove(o.id)
      if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
      await load()
    } catch (e) {
      Notify.create({ message: e.message, color: 'negative', position: 'top' })
    } finally {
      busy.value = null
    }
  })
}
function diffText (c) {
  const out = []
  if (c.from.code !== c.to.code) out.push('الرمز ' + c.from.code + ' ← ' + c.to.code)
  if (c.from.page !== c.to.page) out.push('الصفحة ' + c.from.page + ' ← ' + c.to.page)
  if (c.from.price !== c.to.price) out.push('السعر ' + num(c.from.price) + ' ← ' + num(c.to.price))
  return out.join('، ') || 'تغيّر مكانه في القائمة'
}

// المشاهدة: the opened offers (priced, not in doubt), one order for everybody, by section
const opened = computed(() => approved.value.filter((o) => o.active && o.price && o.status !== 'doubt').sort((a, b) => a.viewIndex - b.viewIndex || a.id - b.id))
const shown = computed(() => opened.value.filter((o) => (filter.value === 'customer' ? o.audience === 'all' && !o.hidden : editing.value || !o.hidden)))
const drag = ref(null)
const sections = computed(() => {
  if (drag.value) {
    const byId = (id) => shown.value.find((o) => o.id === id)
    return { bundle: drag.value.order.bundle.map(byId).filter(Boolean), internet: drag.value.order.internet.map(byId).filter(Boolean) }
  }
  return { bundle: shown.value.filter((o) => o.category !== 'internet'), internet: shown.value.filter((o) => o.category === 'internet') }
})

async function load () {
  loading.value = true
  error.value = ''
  try {
    const [r, gr] = await Promise.all([flexy.ownerOfferCatalog(operator.value), flexy.ownerOfferGroups(operator.value)])
    if (r.status !== 200 || !r.body?.ok) throw new Error(r.body?.error || 'FLEXY_CORE')
    rows.value = r.body.offers || []
    groupInfo.value = gr.body?.groups || []
    if (!groupNames.value.includes(group.value)) {
      group.value = groupInfo.value.find((g) => g.draft_source)?.grp || groupNames.value[0] || ''
    }
    if (tab.value === 'draft' && !hasDraft.value) tab.value = 'approved'
  } catch (e) {
    error.value = 'تعذّرت قراءة العروض: ' + (e.message || '')
  } finally {
    loading.value = false
  }
}

const EDITABLE = ['active', 'audience', 'price', 'priceSource', 'nameDisplay', 'details', 'category', 'hidden', 'status', 'viewIndex']
const fresh = (offer) => Object.fromEntries(EDITABLE.map((k) => [k, offer[k]]))

// «تحديد متعدد» (edit mode of الأصل): a doubtful offer (its code shown twice) cannot be picked, it opens for nobody
const picked = ref(new Set())
const bulkBusy = ref(false)
const canPick = (o) => o.status !== 'doubt' || resolved(o)
const pickable = computed(() => approved.value.filter(canPick))
const allPicked = computed(() => pickable.value.length > 0 && pickable.value.every((o) => picked.value.has(o.id)))
function pick (o, on) { const n = new Set(picked.value); if (on) n.add(o.id); else n.delete(o.id); picked.value = n }
function pickAll (on) { picked.value = on ? new Set(pickable.value.map((o) => o.id)) : new Set() }
const BULK_TEXT = { 'audience:all': 'للزبائن (الكل)', 'audience:admin': 'للإدارة فقط', 'active:true': 'مفعّلة', 'active:false': 'موقوفة' }
function applyBulk (patch) {
  const ids = [...picked.value]
  const what = BULK_TEXT[Object.entries(patch).map(([k, v]) => k + ':' + v)[0]]
  Dialog.create({
    title: 'تطبيق على ' + ids.length + ' عرضًا',
    message: 'تجعل ' + ids.length + ' عرضًا ' + what + '؟ العرض بلا سعر أو المشكوك يُتخطّى ويُسمّى.',
    cancel: 'رجوع',
    ok: 'نعم'
  }).onOk(async () => {
    bulkBusy.value = true
    try {
      const r = await flexy.ownerOfferBulk(ids, patch)
      if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
      const byId = new Map((r.body.offers || []).map((x) => [x.id, fresh(x)]))
      rows.value = rows.value.map((x) => (byId.has(x.id) ? { ...x, ...byId.get(x.id) } : x))
      const skipped = r.body.skipped || []
      if (skipped.length) {
        const names = skipped.map((s) => rows.value.find((x) => x.id === s.id)?.nameNetwork || s.id).join('، ')
        Notify.create({ message: 'تُخطّي ' + skipped.length + ': ' + names + ' (' + (ERRORS[skipped[0].error] || skipped[0].error) + ')', color: 'warning', position: 'top', timeout: 6000 })
      } else {
        Notify.create({ message: 'تم على ' + byId.size + ' عرضًا', color: 'positive', position: 'top' })
      }
      picked.value = new Set()
    } catch (e) {
      Notify.create({ message: e.message, color: 'negative', position: 'top' })
    } finally {
      bulkBusy.value = false
    }
  })
}
async function save (o, patch) {
  busy.value = o.id
  try {
    const r = await flexy.ownerOfferCatalogSet(o.id, patch)
    if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
    const f = fresh(r.body.offer)
    rows.value = rows.value.map((x) => (x.id === o.id ? { ...x, ...f } : x))
    return true
  } catch (e) {
    Notify.create({ message: e.message, color: 'negative', position: 'top' })
    return false
  } finally {
    busy.value = null
  }
}

function editPrice (o) {
  Dialog.create({
    title: o.nameNetwork,
    message: 'سعر العرض بالدينار (ما يُخصم من رصيد الشريحة). الـPIN لا يُرسل إلا إذا قالت الشبكة نفس السعر.',
    prompt: { model: o.price ? String(o.price) : '', type: 'number', inputmode: 'numeric' },
    cancel: 'رجوع',
    ok: 'حفظ'
  }).onOk((v) => {
    const price = Number(v)
    if (!Number.isInteger(price) || price <= 0) return Notify.create({ message: 'سعر غير صحيح', color: 'negative', position: 'top' })
    save(o, { price })
  })
}

async function act (action, value = null) {
  acting.value = true
  try {
    const r = await flexy.ownerOfferGroupAction(operator.value, group.value, action, value)
    if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
    await load()
    tab.value = action === 'raise' ? 'draft' : 'approved'
  } catch (e) {
    Notify.create({ message: e.message, color: 'negative', position: 'top' })
  } finally {
    acting.value = false
  }
}
function approve () {
  Dialog.create({
    title: 'اعتماد النسخة ' + nextVersion.value + ' من ' + group.value,
    message: (approved.value.length ? 'تُحفظ المعتمدة الحالية في النسخ القديمة، و' : '') + 'تصير هذه هي التي تُباع.',
    cancel: 'رجوع',
    ok: 'اعتمد'
  }).onOk(() => act('approve'))
}
// «GOLD 2»…: a variant saved by itself (Flexy Core 0067, 0074)
const variantNo = computed(() => /\s\d+$/.test(group.value || ''))
function openAll () {
  Dialog.create({
    title: 'افتح ' + group.value + ' للمحلات كما هي',
    message: 'يرى المحل عروض ' + group.value + ' بأسماء الشبكة وأسعارها، مرتبة من الأصغر، بلا وصف ولا قسم. تضيف الوصف والقسم لاحقًا بالتعديل.',
    cancel: 'رجوع',
    ok: 'افتح'
  }).onOk(() => act('open_all'))
}
// «إلغاء» of «جديدة»: a raised version goes back to the archive; a network reading is dropped (a real change comes back)
function discard () {
  Dialog.create({
    title: 'إلغاء «جديدة» من ' + group.value,
    message: raised.value ? 'ترجع النسخة ' + raised.value + ' إلى النسخ القديمة كما هي.'
      : 'تُحذف هذه القراءة. إن كانت الشبكة فعلًا هكذا، تعود مع أول رقم من هذه المجموعة.',
    cancel: 'رجوع',
    ok: 'ألغِ'
  }).onOk(() => act('discard'))
}
// «إلغاء النسخة»: kept whole among the old versions («رفع» brings it back); nothing of the group sells meanwhile
function withdraw () {
  Dialog.create({
    title: 'إلغاء النسخة ' + info.value.version + ' من ' + group.value,
    message: 'تُحفظ كاملة بقراراتها في «النسخ القديمة» (ترجعها بـ«رفع» ثم «اعتماد»)، ولا يُباع شيء من ' + group.value +
      ' حتى تعتمد نسخة. أول رقم منها تفتحه تُقرأ قائمته في «جديدة».',
    cancel: 'رجوع',
    ok: { label: 'ألغِ النسخة', color: 'negative', unelevated: true }
  }).onOk(() => act('withdraw'))
}
function raise (v) {
  Dialog.create({
    title: 'رفع النسخة ' + v.version + ' من ' + group.value,
    message: 'تظهر في تبويب «جديدة» كما كانت (' + v.count + ' عرضًا)' + (hasDraft.value ? ' مكان ما فيه الآن' : '') +
      '. لا يتغير شيء حتى تضغط «اعتماد».',
    cancel: 'رجوع',
    ok: 'ارفع'
  }).onOk(() => act('raise', String(v.version)))
}

// The offer's sheet (display mode)
const sheetOpen = ref(false)
const sheet = ref(null)
function openSheet (o) {
  sheet.value = { row: o, name: o.nameDisplay, details: o.details || '', category: o.category, hidden: o.hidden }
  sheetOpen.value = true
}
async function saveSheet () {
  const s = sheet.value
  const patch = {}
  if (s.name.trim() !== s.row.nameDisplay) patch.name_display = s.name.trim()
  if (s.details.trim() !== (s.row.details || '')) patch.details = s.details.trim()
  if (s.category !== s.row.category) patch.category = s.category
  if (s.hidden !== s.row.hidden) patch.hidden = s.hidden
  if (!s.name.trim()) return Notify.create({ message: 'اكتب النص الظاهر.', color: 'negative', position: 'top' })
  if (!Object.keys(patch).length || await save(s.row, patch)) sheetOpen.value = false
}

// Drag ⠿ (touch and mouse): the row moves live under the finger, inside its section or into the other one;
// on release, every opened offer of the group gets its new place (those the filter hides keep theirs).
// The window follows the pointer: a row moved into the other section is a new element there.
function startDrag (e, o) {
  if (busy.value || drag.value) return
  e.preventDefault()
  drag.value = { id: o.id, moved: false, order: { bundle: sections.value.bundle.map((x) => x.id), internet: sections.value.internet.map((x) => x.id) } }
  window.addEventListener('pointermove', moveDrag, { passive: false })
  window.addEventListener('pointerup', endDrag)
  window.addEventListener('pointercancel', endDrag)
}
function moveDrag (e) {
  const d = drag.value
  if (!d) return
  e.preventDefault()
  const y = e.clientY
  if (y < 80) window.scrollBy(0, -12)
  else if (y > window.innerHeight - 80) window.scrollBy(0, 12)
  const boxes = [...document.querySelectorAll('[data-sec]')].map((el) => ({ el, r: el.getBoundingClientRect() }))
  const target = boxes.find((b) => y >= b.r.top && y <= b.r.bottom) ||
    boxes.reduce((best, b) => {
      const dist = y < b.r.top ? b.r.top - y : y - b.r.bottom
      return !best || dist < best.dist ? { ...b, dist } : best
    }, null)
  if (!target) return
  const sec = target.el.dataset.sec
  const others = [...target.el.querySelectorAll('[data-row]')].filter((el) => Number(el.dataset.row) !== d.id)
  const index = others.filter((el) => { const r = el.getBoundingClientRect(); return r.top + r.height / 2 < y }).length
  const from = d.order.bundle.includes(d.id) ? 'bundle' : 'internet'
  if (from === sec && d.order[sec].indexOf(d.id) === index) return
  const list = d.order[sec].filter((id) => id !== d.id)
  list.splice(index, 0, d.id)
  d.order[from] = d.order[from].filter((id) => id !== d.id)
  d.order[sec] = list
  d.moved = true
}
async function endDrag () {
  window.removeEventListener('pointermove', moveDrag)
  window.removeEventListener('pointerup', endDrag)
  window.removeEventListener('pointercancel', endDrag)
  const d = drag.value
  if (!d) return
  if (!d.moved) { drag.value = null; return }
  // The full order: the filter's hidden offers keep their places, the shown ones take the new order
  const shownIds = new Set([...d.order.bundle, ...d.order.internet])
  const items = []
  for (const s of SECTIONS) {
    const want = d.order[s.key]
    const out = []
    let k = 0
    let last = -1
    for (const o of opened.value.filter((x) => (x.category === 'internet' ? 'internet' : 'bundle') === s.key)) {
      if (!shownIds.has(o.id)) out.push(o.id)
      else if (k < want.length) { out.push(want[k++]); last = out.length - 1 }
    }
    out.splice(last >= 0 ? last + 1 : out.length, 0, ...want.slice(k))
    for (const id of out) items.push({ id, category: s.key })
  }
  const place = new Map(items.map((x, i) => [x.id, { viewIndex: i + 1, category: x.category }]))
  rows.value = rows.value.map((o) => (place.has(o.id) ? { ...o, ...place.get(o.id) } : o))
  drag.value = null
  busy.value = 'arrange'
  try {
    const r = await flexy.ownerOfferArrange(operator.value, group.value, items)
    if (r.status !== 200 || !r.body?.ok) throw new Error(ERRORS[r.body?.error] || r.body?.error || 'FLEXY_CORE')
  } catch (e) {
    Notify.create({ message: 'لم يُحفظ الترتيب: ' + e.message, color: 'negative', position: 'top' })
    await load()
  } finally {
    busy.value = null
  }
}

watch(operator, () => { group.value = ''; load() })
onBeforeUnmount(() => { if (drag.value) { drag.value.moved = false; endDrag() } })
watch(group, () => { tab.value = approved.value.length || !hasDraft.value ? 'approved' : 'draft'; picked.value = new Set() })
watch(editing, (on) => { if (!on) picked.value = new Set() })
onMounted(load)
</script>

<style scoped>
.page { max-width: 760px; margin: 0 auto; }
.card { background: #fff; border: 1px solid #ECEEF3; border-radius: 12px; overflow: hidden; }
.dot { color: #7C3AED; margin-inline-start: 3px; font-size: 10px; }
.modes { border: 2px solid #1F2937; border-radius: 10px; overflow: hidden; font-weight: 800; text-align: center; }
.modes > div { padding: 6px 0; cursor: pointer; background: #fff; color: #1F2937; }
.modes > div.on { background: #1F2937; color: #fff; }
.modes > div.dv.on { background: #0E7490; }
.tabs { background: #E5E7EB; border-radius: 9px; }
.tab { text-align: center; padding: 7px 0; font-weight: 700; color: #6B7280; cursor: pointer; font-size: 13px; }
.tab.on { color: #C2410C; background: #fff; border-bottom: 3px solid #C2410C; border-radius: 9px 9px 0 0; }
.pg { padding: 4px 14px; font-size: 11px; color: #6B7280; background: #F8FAFC; border-top: 1px solid #ECEEF3; }
.pg:first-child { border-top: 0; }
.orow.picked { background: #FFF7ED; }
.bulkbar { position: sticky; bottom: 72px; z-index: 5; background: #fff; border: 2px solid #C2410C; border-radius: 12px; padding: 8px 12px; box-shadow: 0 6px 18px rgba(0, 0, 0, 0.15); }
.orow { display: flex; gap: 8px; align-items: center; justify-content: space-between; padding: 8px 14px; border-top: 1px solid #ECEEF3; }
.off { opacity: 0.5; }
.nm { font-weight: 700; }
.code { font-weight: 800; }
.meta { font-size: 11.5px; color: #6B7280; margin-top: 2px; }
.price { font-weight: 700; white-space: nowrap; }
.tag { font-size: 10.5px; border-radius: 5px; padding: 0 6px; font-weight: 800; white-space: nowrap; margin-inline-start: 4px; }
.t-all { background: #DCFCE7; color: #166534; }
.t-adm { background: #FEF3C7; color: #92400E; }
.t-off { background: #F3F4F6; color: #6B7280; }
.t-new { background: #EDE9FE; color: #6D28D9; }
.t-chg { background: #FFEDD5; color: #9A3412; }
.pchip { border: 1px dashed #C2410C; border-radius: 6px; padding: 1px 7px; font-weight: 800; color: #C2410C; cursor: pointer; white-space: nowrap; }
.chg { background: #FFF7ED; border-color: #FDBA74; }
.chg-h { padding: 8px 14px; font-weight: 800; color: #9A3412; }
.chg-r { display: flex; justify-content: space-between; gap: 8px; padding: 6px 14px; border-top: 1px solid #FED7AA; font-size: 12.5px; }
.plus { color: #166534; font-weight: 800; white-space: nowrap; }
.minus { color: #B91C1C; font-weight: 800; white-space: nowrap; }
.mod { color: #9A3412; font-weight: 800; white-space: nowrap; }
.hint { font-size: 12px; color: #0E7490; font-weight: 700; background: #ECFEFF; border-radius: 8px; padding: 5px 10px; }
.sec { padding: 9px 14px; font-weight: 800; }
.net { border-inline-start: 4px solid #0E7490; }
.net-t, .net-p { color: #0E7490; }
.drow { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 9px 14px; border-top: 1px solid #ECEEF3; background: #fff; }
.drow.dragging { border: 2px solid #0E7490; border-radius: 9px; box-shadow: 0 8px 18px rgba(0, 0, 0, 0.2); position: relative; z-index: 2; }
.hd { color: #9CA3AF; font-size: 18px; font-weight: 900; cursor: grab; touch-action: none; user-select: none; padding: 4px 2px; }
.dragging .hd { color: #0E7490; }
.slot { margin: 4px 10px 10px; border: 2px dashed #0E7490; border-radius: 8px; height: 38px; display: flex; align-items: center; justify-content: center;
  font-size: 12px; color: #0E7490; font-weight: 700; background: #F0FDFA; }
.sheet { width: 100%; max-width: 560px; border-radius: 16px 16px 0 0; }
.small { font-size: 12px; }
.muted { color: #6B7280; }
</style>
