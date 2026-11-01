<template>
  <q-page class="page">
    <SectionTabs :tabs="MONITOR_TABS" />
    <!-- The admin phone (owner 2026-10-26): Rech-Doom on his phone asks to be linked; he approves it here -->
    <div v-for="p in pendingPhones" :key="p.station_uuid" class="card row items-center q-gutter-sm">
      <q-icon name="smartphone" color="primary" size="24px" />
      <div class="col">
        <div class="text-weight-bold">هاتف ينتظر الاعتماد: {{ p.computer_name }}</div>
        <div class="small muted">يصبح «هاتف الإدارة»: يرسل فقط ما ترسله أنت بـ«العروض من هاتفي»، والبرنامج لا يختاره وحده.</div>
      </div>
      <q-btn unelevated no-caps color="primary" label="اعتماد" :loading="busy" @click="approvePhone(p)" />
    </div>
    <!-- The admin phone running without its protection (Rech-Doom 0.8.2 health): it can look «offline» while in use -->
    <div v-for="p in unprotectedPhones" :key="'u' + p.station_uuid" class="card row items-center q-gutter-sm">
      <q-icon name="warning" color="negative" size="24px" />
      <div class="col small text-negative">
        <b>{{ p.label }}</b> يعمل بلا حماية من التجميد: افتح Rech-Doom مرة ووافق على «تجاهل تحسين البطارية»، وإلا بدا الهاتف «غير متصل» وأنت تستعمله.
      </div>
    </div>
    <!-- Stopped SIMs (Flexy Core 0039): the reason recorded only; «تم» hides them for today, they come back tomorrow if still stopped -->
    <div v-if="simAlerts.length" class="card q-gutter-xs">
      <div class="row items-center">
        <div class="text-weight-bold text-negative col">شرائح متوقفة</div>
        <q-btn flat dense color="primary" label="تم" :loading="simAlertsBusy" @click="simAlertsSeen" />
      </div>
      <!-- With its computer (owner 2026-10-30: «من أي كمبيوتر؟ لا نخمّن») -->
      <div v-for="a in simAlerts" :key="a.sim_uuid + a.code" class="small">{{ a.text }}<b v-if="stationOfSim(a.sim_uuid)"> · على {{ stationOfSim(a.sim_uuid) }}</b></div>
    </div>
    <!-- A failed delete on a connected SIM stays in sight; the rest of «مخزن الرسائل» is folded at the end -->
    <div v-for="w in wipeErrors" :key="w.sim_uuid" class="card small text-negative">
      مخزن الرسائل · {{ w.label || w.sim_code || 'شريحة' }}: فشل الحذف: {{ w.last_error }}
    </div>
    <!-- One request to Flexy Core; refreshed every 30 seconds while this page is open and visible -->
    <div class="card column q-gutter-sm">
      <div class="row items-center q-gutter-sm">
        <div class="col section-title">الحالة الآن</div>
        <q-btn flat round dense icon="refresh" aria-label="تحديث" :loading="busy" @click="load" />
      </div>
      <!-- What is connected now, counted for the owner (owner 2026-10-25): zero shows red -->
      <!-- A type's tile filters the SIMs table (funnel icon); the computers tile only counts -->
      <div v-if="tree" class="sum">
        <component :is="t.type ? 'button' : 'div'" v-for="t in summary" :key="t.label" :type="t.type ? 'button' : undefined" class="tile"
          :class="{ zero: !t.n, picked: t.type && typeFilter === t.type }" @click="t.type && pickType(t.type)">
          <q-icon v-if="t.type" name="filter_alt" size="14px" class="funnel" />
          <div class="n">{{ t.n }}</div><div class="small">{{ t.label }}</div>
        </component>
      </div>
      <!-- The state only (owner 2026-10-30: the program's rules beside «متصل» read as «مطفأ»); the rules are numbers on «المفاتيح» -->
      <div v-if="tree" class="small muted">آخر تحديث {{ clock(tree.checked_at) }}<template v-if="typeFilter"> · <button type="button" class="link" @click="typeFilter = null">مفلتر: {{ typeName(typeFilter) }} ✕</button></template></div>
      <div v-if="error" class="small text-negative">{{ error }}</div>
      <!-- The phones as a Sama backup (owner 2026-11-01, Flexy Core 0130): here, not on «المفاتيح». Never ordinary credit. -->
      <div v-if="tree" class="row items-center q-gutter-x-md">
        <template v-if="phoneSwitches">
          <q-toggle :model-value="phoneSwitches.discover" :disable="!!switching" label="الاستكشاف من الهاتف" @update:model-value="(v) => setPhoneSwitch('discover', v)" />
          <q-toggle :model-value="phoneSwitches.execute" :disable="!!switching" label="التنفيذ من الهاتف" @update:model-value="(v) => setPhoneSwitch('execute', v)" />
          <div class="small muted full-width">عروض سما فقط، وبعد شرائح الكمبيوترات حين لا تكون واحدة جاهزة. شريحة الهاتف «للكل» وحدها تأخذ عمليات المحلات.</div>
        </template>
        <div v-else class="small muted">مفتاحا الهاتف (الاستكشاف والتنفيذ) وحالة كل شريحة: بعد تطبيق 0130 من «ينتظر تطبيقك».</div>
      </div>
    </div>

    <!-- One part at a time (owner 2026-10-30: «اجعل الكمبيوترات في تبويب آخر، التنقل للأسفل مزعج»); the last one kept -->
    <q-btn-toggle v-if="tree" v-model="pageTab" spread unelevated no-caps toggle-color="primary" color="white" text-color="dark" class="page-tabs"
      :options="[{ label: 'الشرائح', value: 'sims' }, { label: `إضافة كمبيوتر (${presentCount} متصل)`, value: 'computers' }]" />

    <!-- SIMs (owner 2026-10-25, agreed on a picture): the computer first, then active or not inside it.
         Active = its computer present and its modem connected. Gone 7+ days = «قديمة» at the end. -->
    <div v-if="tree" v-show="pageTab === 'sims'" class="card q-pa-none">
      <div class="section-title q-pa-sm">الشرائح</div>
      <div class="row q-gutter-xs q-px-sm">
        <q-btn v-for="c in stationChips" :key="c.value" dense unelevated rounded no-caps size="md" :label="c.label"
          :color="simStation === c.value ? 'primary' : 'white'" :text-color="simStation === c.value ? 'white' : c.muted ? 'grey-6' : 'dark'"
          class="chip" @click="simStation = c.value" />
      </div>
      <!-- The device picked (owner 2026-11-01): its state in one line -->
      <div v-if="pickedStation" class="small q-px-sm q-pt-xs" :class="isAbsent(pickedStation) ? 'text-deep-orange' : 'text-positive'">
        {{ stName(pickedStation) }}: {{ isAbsent(pickedStation) ? 'مطفأ' : 'متصل' }}<template v-if="pickedStation.last_seen_at"> · آخر ظهور منذ {{ since(pickedStation.last_seen_at) }}</template>
        <template v-if="isAbsent(pickedStation) && pickedStation.reasons?.[0]?.text"> · {{ pickedStation.reasons[0].text }}</template>
        <template v-if="pickedStation.agent_version"> · {{ pickedStation.agent_version }}</template>
      </div>
      <!-- «الكل:» applies one audience to the SIMs shown (owner 2026-11-01) -->
      <div v-if="audiences && simTab !== 'missing' && shownSims.length" class="row items-center q-gutter-xs q-px-sm q-pt-sm">
        <span class="small text-weight-bold">الكل ({{ shownSims.length }}):</span>
        <q-btn v-for="a in AUDIENCES" :key="a.value" dense outline no-caps size="sm" :color="a.color" :label="a.label"
          :loading="audienceBusy === 'all:' + a.value" :disable="!!audienceBusy" @click="askAudienceAll(a)" />
      </div>
      <div class="sub">
        <!-- One word per SIM from the top layer down (owner 2026-10-28): its computer off is not its problem;
             «تحتاج تدخلًا» holds only what needs the owner now, even with its computer off (a PIN, an approval) -->
        <q-btn-toggle v-model="simTab" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ label: `الكل (${simRows.all.length})`, value: 'all' }, { label: `جاهزة (${simRows.ready.length})`, value: 'ready' }, { label: `كمبيوترها مطفأ (${simRows.station_off.length})`, value: 'station_off' }, { label: `تحتاج تدخلًا (${simRows.needs_action.length})`, value: 'needs_action' }, ...(missingSims.length ? [{ label: `غائبة (${missingSims.filter((x) => !x.retired).length})`, value: 'missing' }] : [])]" />
      </div>
      <!-- Owner 2026-10-30: «المراقبة» named a SIM this page did not show. An approved SIM no modem holds now: where it was
           last, and «ألغِ تتبّعها» (owner's word: «إخراج من الخدمة» is something else) when it was taken out on purpose (it comes back by itself when seen again). -->
      <div v-if="simTab === 'missing'" class="column">
        <div v-for="x in missingSims" :key="x.sim_uuid" class="missing-row" :class="{ focus: focusSim === x.code, retired: x.retired }">
          <div class="row items-center no-wrap q-gutter-sm">
            <span class="col text-weight-bold">{{ x.code || 'شريحة' }} <span class="small muted">· {{ typeName(x.sim_type) }}</span></span>
            <span class="small">{{ x.balance == null ? '—' : money(x.balance) }}</span>
          </div>
          <div class="small" :class="x.retired ? 'muted' : 'text-deep-orange'">
            {{ x.retired ? 'تتبّعها ملغى' : 'غائبة' }}{{ x.last_seen_at ? ' منذ ' + since(x.last_seen_at) : '' }}
            · آخر مكان: {{ x.station_code ? stationTag(x.station_code) : '—' }}{{ x.usb != null ? ' · USB ' + x.usb : '' }}{{ stationOffText(x) }}
          </div>
          <q-btn dense flat no-caps size="sm" :color="x.retired ? 'primary' : 'grey-8'" class="self-start" :loading="retiring === x.sim_uuid"
            :label="x.retired ? 'أرجع تتبّعها' : 'ألغِ تتبّعها على ' + (x.station_code || 'هذا الكمبيوتر')" @click="retire(x, !x.retired)" />
        </div>
        <div class="small muted q-pa-sm">«ألغِ تتبّعها»: تُخفى من التنبيهات ولا يُحسب رصيدها، وتعود وحدها ويُصفَّر هذا إذا ظهرت في أي كمبيوتر (أو رجع كمبيوترها).</div>
      </div>
      <div v-if="simTab !== 'missing'" class="table-wrap">
        <table class="sims">
          <thead><tr><th>الشريحة</th><th>الرقم</th><th>الرصيد</th><th>الحالة</th><th v-if="audiences">لمن</th></tr></thead>
          <tbody>
            <!-- By computer (owner 2026-11-01): a big «💻 1» heading, then its SIMs «USB-9 / djezzy-1» -->
            <template v-for="g in simGroups" :key="g.st.station_uuid">
              <tr class="pc-head static" :class="{ 'sim-down': g.down }">
                <td :colspan="audiences ? 5 : 4">
                  <span class="pc-icon">{{ isPhone(g.st) || g.st.phone ? '📱' : '💻' }}</span>
                  <span class="pc-no" :class="{ struck: g.down }">{{ stNo(g.st) }}</span><b v-if="g.down" class="text-negative"> ✗</b>
                  <span class="small muted q-ml-sm">{{ g.rows.length }} {{ g.rows.length === 1 ? 'شريحة' : 'شرائح' }}<template v-if="g.down"> · مطفأ</template></span>
                </td>
              </tr>
              <template v-for="r in g.rows" :key="r.m.sim.sim_uuid">
                <tr :class="{ 'sim-down': simState(r) !== 'ready' }" @click="open(r.st, r.m)">
                  <td>
                    <!-- «USB-9 / djezzy-1», the broken part struck through with ✗; one name, not twice -->
                    <div class="place ltr text-left">
                      <span class="dot" :class="simState(r) === 'ready' ? 'on' : 'off'" :title="simState(r) === 'ready' ? 'جاهزة' : (STATE[simState(r)]?.label || '')"></span>
                      <span :class="{ struck: placeDown(r) === 'usb' }">{{ slotOf(r) }}<b v-if="placeDown(r) === 'usb'"> ✗</b></span> /
                      <span :class="{ struck: placeDown(r) === 'sim' }">{{ r.m.sim.code || 'sim' }}<b v-if="placeDown(r) === 'sim'"> ✗</b></span>
                      <span v-if="isPreferred(r.m.sim)" class="text-amber-8" title="مفضّلة: يرسل منها أولًا"> ⭐</span>
                    </div>
                    <div v-if="r.m.sim.label" class="small muted">{{ r.m.sim.label }}</div>
                  </td>
                  <td><bdi class="ltr">{{ r.m.sim.msisdn || (r.m.sim.msisdn_tail ? '…' + r.m.sim.msisdn_tail : '—') }}</bdi></td>
                  <!-- The balance as a badge (owner 2026-11-01): red at or under the minimum, green above, orange unread -->
                  <td><q-badge class="bal" :color="r.m.sim.balance == null ? 'orange-8' : r.m.sim.balance <= minOf(r.m.sim) ? 'negative' : 'positive'"
                    :label="r.m.sim.balance == null ? 'غير مقروء' : money(r.m.sim.balance)" />
                    <div v-if="limitOf(r.m.sim).max_per_day" class="small" :class="limitOf(r.m.sim).today >= limitOf(r.m.sim).max_per_day ? 'text-negative text-weight-bold' : 'muted'">
                      اليوم {{ limitOf(r.m.sim).today }}/{{ limitOf(r.m.sim).max_per_day }}</div></td>
                  <td @click.stop>
                    <!-- Only a problem is written; a ready SIM is its green dot -->
                    <div v-if="simState(r) !== 'ready' && statusText(r)" class="small" :class="statusClass(r)"><q-spinner v-if="isReading(r.m.sim) && !modemGone(r)" size="12px" class="q-mr-xs" />{{ statusText(r) }}
                      <q-btn flat round dense size="sm" icon="smart_toy" aria-label="نسخ لـClaude" @click.stop="copySimForClaude(r)" /></div>
                    <!-- In the card (owner 2026-11-01): «الرصيد» and a USSD field, without opening the window -->
                    <div class="row q-gutter-xs no-wrap">
                      <q-btn dense outline no-caps size="sm" color="primary" :label="isPhone(r.st) ? 'اكتشاف الرصيد' : 'الرصيد'"
                        :loading="rowReading === r.m.sim.sim_uuid" :disable="!!rowReading" @click.stop="readRowBalance(r.m.sim)" />
                      <q-btn dense :outline="ussdOpen !== r.m.sim.sim_uuid" :unelevated="ussdOpen === r.m.sim.sim_uuid" no-caps size="sm" color="primary" label="USSD"
                        @click.stop="openUssd(r.m.sim, '')" />
                      <!-- «رقمي» (owner 2026-11-01): one tap, the SIM asks its own number (Sama *222#) -->
                      <q-btn dense outline no-caps size="sm" color="primary" label="رقمي" @click.stop="myNumber(r.m.sim)" />
                      <q-btn dense flat round size="sm" icon="settings" :color="setOpen === r.m.sim.sim_uuid ? 'primary' : 'grey-7'" aria-label="إعدادات الشريحة"
                        @click.stop="openSettings(r)" />
                    </div>
                    <div v-if="rowRead[r.m.sim.sim_uuid]" class="small muted">{{ rowRead[r.m.sim.sim_uuid] }}</div>
                  </td>
                  <!-- للكل / للإدارة / موقوفة (owner 2026-11-01, Flexy Core 0130), like the offers -->
                  <td v-if="audiences" @click.stop>
                    <q-btn-toggle :model-value="audienceOf(r.m.sim)" dense unelevated no-caps size="sm" color="grey-3" text-color="dark"
                      :toggle-color="AUDIENCES.find((a) => a.value === audienceOf(r.m.sim))?.color || 'primary'" :disable="!!audienceBusy"
                      :options="AUDIENCES.map((a) => ({ label: a.label, value: a.value }))" @update:model-value="(v) => setAudience([r.m.sim], v)" />
                    <!-- «الشريحة المفضّلة» (owner 2026-11-01, Flexy Core 0131): sent from first, to empty it -->
                    <q-btn v-if="preferredMap" flat dense no-caps size="sm" :icon="isPreferred(r.m.sim) ? 'star' : 'star_outline'"
                      :color="isPreferred(r.m.sim) ? 'amber-8' : 'grey-6'" round :title="isPreferred(r.m.sim) ? 'مفضّلة: يرسل منها أولًا' : 'اجعلها مفضّلة'"
                      :loading="preferBusy === r.m.sim.sim_uuid" :disable="!!preferBusy" @click="setPreferred(r.m.sim, !isPreferred(r.m.sim))" />
                  </td>
                </tr>
                <tr v-if="ussdOpen === r.m.sim.sim_uuid" class="static">
                  <td :colspan="audiences ? 5 : 4" @click.stop>
                    <ModemPanel :key="r.m.sim.sim_uuid + ussdCode" inline :start-code="ussdCode" :sim-uuid="r.m.sim.sim_uuid" :sim-type="r.m.sim.sim_type" :phone="isPhone(r.st)" :sim-name="r.m.sim.code || ''" />
                  </td>
                </tr>
                <!-- ⚙️ the SIM's settings in its card (owner 2026-11-01) -->
                <tr v-if="setOpen === r.m.sim.sim_uuid" class="static">
                  <td :colspan="audiences ? 5 : 4" @click.stop>
                    <div class="sim-set column q-gutter-sm">
                      <div class="row q-gutter-sm">
                        <q-input v-model.number="setForm.min" class="col" dense outlined type="number" inputmode="numeric" label="الحد الأدنى للرصيد (دج)" :placeholder="String(MIN_BALANCE)" />
                        <q-input v-model.number="setForm.max" class="col" dense outlined type="number" inputmode="numeric" label="أقصى عمليات في اليوم" placeholder="بلا حد" />
                      </div>
                      <div class="row q-gutter-sm items-center">
                        <q-input v-model.number="setForm.slot" class="col" dense outlined type="number" inputmode="numeric" :label="isPhone(r.st) ? 'رقم الخانة (SIM)' : 'رقم USB المكتوب على الجهاز'" />
                        <q-input v-model="setForm.code" class="col" dense outlined class-input="ltr" :label="'كود «رقمي» لـ' + (r.m.sim.sim_type_name || r.m.sim.sim_type)" placeholder="*222#" />
                      </div>
                      <div class="small muted">الحد الأقصى يُعرض الآن «اليوم 12/20» ويحمرّ عند بلوغه؛ إيقاف الإرسال عنده خطوة تالية. الاسم والملاحظة والـPIN في نافذة الشريحة (اضغط سطرها).</div>
                      <div class="row q-gutter-sm">
                        <q-btn unelevated no-caps color="primary" label="احفظ" :loading="setBusy" @click="saveSimSet(r)" />
                        <q-btn flat no-caps color="grey-8" label="إغلاق" @click="setOpen = null" />
                      </div>
                    </div>
                  </td>
                </tr>
              </template>
            </template>
            <tr v-if="!shownSims.length">
              <td :colspan="audiences ? 5 : 4" class="text-center muted">لا شرائح بهذا الفلتر
                <q-btn v-if="typeFilter || simStation !== 'all'" flat dense no-caps size="sm" color="primary" label="إلغاء الفلاتر" @click="clearFilters" /></td>
            </tr>
            <tr v-if="simTab === 'station_off' && simRows.old.length" class="static">
              <td :colspan="audiences ? 5 : 4"><button type="button" class="link" @click="showOldSims = !showOldSims">قديمة ({{ simRows.old.length }}) {{ showOldSims ? '▴' : '▾' }}</button></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <AddComputer v-show="pageTab === 'computers'" @approved="load" />
    <!-- Computers: connected first, one row each, the Agent's update and gateway buttons in the row -->
    <div v-if="tree" v-show="pageTab === 'computers'" class="card q-pa-none">
      <div class="section-title q-pa-sm">الكمبيوترات</div>
      <!-- A newer Agent on main (owner 2026-10-30): one button for all, one computer after the other -->
      <div v-if="updatable.length || updatingAll" class="sub row items-center q-gutter-sm bg-blue-1">
        <q-icon name="system_update" color="primary" />
        <span class="col">{{ updatingAll || (updatable[0].main_version + ' متاح لـ' + updatable.length + (updatable.length === 1 ? ' كمبيوتر' : ' كمبيوترات')) }}</span>
        <q-btn v-if="!updatingAll" unelevated dense no-caps color="primary" label="حدّث الكل" :loading="busy" @click="askUpdateAll" />
      </div>
      <div class="sub row items-center">
        <q-btn-toggle v-model="stationActive" dense unelevated no-caps toggle-color="primary" color="grey-3" text-color="dark"
          :options="[{ label: `تعمل (${presentCount})`, value: true }, { label: `مطفأة (${current.length - presentCount})`, value: false }]" />
        <q-space />
        <!-- Owner 2026-10-30: the rare buttons (pause, end, gateway) only here, or by themselves on a computer gone a while -->
        <q-btn flat dense no-caps :color="editStations ? 'primary' : 'grey-8'" :icon="editStations ? 'check' : 'edit'" :label="editStations ? 'تم' : 'تعديل'" @click="editStations = !editStations" />
      </div>
      <div class="table-wrap">
        <table class="sims">
          <thead><tr><th>الجهاز</th><th>الحالة</th><th>الشرائح</th><th>التحديث</th><th v-if="editStations">البوابة</th></tr></thead>
          <tbody>
            <tr v-for="st in stationRows" :key="st.station_uuid" class="static">
              <td><span class="text-weight-bold">{{ st.code || 'كمبيوتر' }}</span><span v-if="st.label" class="muted"> · {{ st.label }}</span>
                <div class="small muted">{{ isAbsent(st) ? 'آخر ظهور ' + clock(st.last_seen_at) : 'Agent ' + (st.agent_version || '—') }}</div>
                <q-badge v-if="updates && !isAbsent(st) && !active(st) && newInMain(st)" outline color="primary" :label="'⬆ ' + newInMain(st).main_version" />
                <!-- «صفحة الكمبيوتر» (owner 2026-10-30): its fixed actions from here, the same as its local page -->
                <!-- Where its program is (Agent 0.9.1, Flexy Core 0100): said once, known from then on -->
                <div v-if="places[st.station_uuid]" class="small muted ltr place">📁 {{ places[st.station_uuid].dir }}</div>
                <!-- Asks for a press only when something is needed (owner 2026-10-30: «زر يدعوني ولا شيء فيه»): then it says
                     what; otherwise a faint gear, for a problem the page cannot see -->
                <div v-if="!isPhone(st) && st.approved">
                  <q-btn v-if="neededFor(st).length" unelevated dense no-caps size="sm" color="deep-orange" icon="build" :label="neededFor(st)[0].label" @click="openActions(st)" />
                  <q-btn v-else flat round dense size="sm" color="grey-5" icon="settings" aria-label="أوامر عند مشكلة لا تظهر هنا" @click="openActions(st)" />
                </div></td>
              <td><q-badge :color="isAbsent(st) ? 'grey-6' : LEVEL[st.level].color" :label="isAbsent(st) ? 'مطفأ' : '✅ متصل'" />
                <div v-if="isAbsent(st)" class="small muted">{{ st.reasons[0]?.text }}</div>
                <div v-for="r in isAbsent(st) ? [] : st.reasons" :key="r.code" class="small" :class="r.level === 'down' ? 'text-negative' : 'text-deep-orange'">{{ r.text }}</div>
                <!-- «سجلّ الشبكة» (Flexy Core 0115, Agent 0.9.6): what the computer itself saw of its internet, by the second -->
                <div v-if="netOf(st).length" class="small q-mt-xs net-log">
                  <button type="button" class="link" @click="netOpen = netOpen === st.station_uuid ? null : st.station_uuid">🌐 سجلّ الشبكة ({{ netOf(st).length }}) {{ netOpen === st.station_uuid ? '▴' : '▾' }}</button>
                  <template v-if="netOpen === st.station_uuid">
                    <div v-for="(e, n) in netOf(st)" :key="n" :class="e.kind === 'server' ? 'text-primary' : ''"><span class="muted ltr">{{ clock(e.at) }}</span> · {{ e.text }}</div>
                  </template>
                  <div v-else class="muted"><span class="ltr">{{ clock(netOf(st)[0].at) }}</span> · {{ netOf(st)[0].text }}</div>
                </div>
                <!-- A new computer not let in from «إضافة كمبيوتر» (owner 2026-10-27); the phone has its own approval above -->
                <q-btn v-if="!st.approved && !isPhone(st) && (!st.status || st.status === 'pending')" unelevated dense no-caps color="primary" class="q-mt-xs" label="اعتماد الكمبيوتر"
                  :loading="busy" @click="approveComputer(st)" />
                <!-- Owner 2026-10-29: stop a computer for a while, or end it (stolen, sold); the phone has its own page -->
                <div v-if="st.status === 'suspended'" class="small text-deep-orange-9 text-weight-bold">⏸ موقوفة: لا يُرسل منها شيء</div>
                <div v-if="st.status === 'revoked'" class="small text-negative text-weight-bold">⛔ ملغاة: لإرجاعها احذف هويتها على الكمبيوتر واربطها من جديد</div>
                <div v-if="!isPhone(st) && (st.status === 'approved' || st.status === 'suspended') && (editStations || st.status === 'suspended' || longGone(st))" class="row q-gutter-xs q-mt-xs">
                  <q-btn v-if="st.status === 'approved'" outline dense no-caps size="sm" color="deep-orange" icon="pause" label="إيقاف مؤقت"
                    :loading="busy" @click="stationStatus(st, 'suspended')" />
                  <q-btn v-else outline dense no-caps size="sm" color="positive" icon="play_arrow" label="تشغيل" :loading="busy" @click="stationStatus(st, 'approved')" />
                  <q-btn flat dense no-caps size="sm" color="negative" icon="block" label="إلغاء المحطة" :loading="busy" @click="stationStatus(st, 'revoked')" />
                </div></td>
              <td>{{ isAbsent(st) ? '—' : simSummary(st) }}</td>
              <td>
                <template v-if="updates && active(st)">
                  <q-badge color="info" :label="UPDATE_STATUS[active(st).status]" />
                  <div class="small muted">{{ updateLabel(active(st)) }}</div>
                  <q-btn v-if="active(st).status === 'pending'" flat dense no-caps size="sm" color="negative" label="إلغاء" :loading="busy" @click="cancel(active(st))" />
                </template>
                <template v-else-if="updates && !isAbsent(st)">
                  <q-btn v-if="newInMain(st)" outline dense no-caps size="sm" color="primary" :label="'حدّث إلى ' + newInMain(st).main_version" :loading="busy" @click="askRelease(st)" />
                  <!-- GitHub refused this computer's key: a new one saved in «إضافة كمبيوتر» reaches it within the hour (updater 1.3.0) -->
                  <span v-else-if="mainOf(st)?.main_error && keyRefused(mainOf(st).main_error)" class="small text-deep-orange">GitHub رفض مفتاح هذا الكمبيوتر (انتهى أو حُذف).
                    <a :href="GITHUB_KEYS" target="_blank" rel="noopener noreferrer">مفاتيحي ↗</a>: Regenerate، ثم احفظه في «إضافة كمبيوتر»؛ يصل الكمبيوتر خلال ساعة.</span>
                  <span v-else-if="mainOf(st)?.main_error && offline(mainOf(st).main_error)" class="small muted">لا يصل إلى GitHub الآن، يعيد المحاولة كل دقيقة</span>
                  <span v-else-if="mainOf(st)?.main_error" class="small text-deep-orange">لا يمكن التحديث: {{ MAIN_ERRORS[mainOf(st).main_error] || mainOf(st).main_error }}
                    <a v-if="mainOf(st).main_error === 'GIT_LOCAL_CHANGES'" href="#" @click.prevent="openActions(st)">← كيف أصلحه</a></span>
                  <span v-else-if="mainOf(st)" class="small muted">على آخر main</span>
                  <div v-if="editStations">
                    <q-btn v-if="st.gateway === 'old'" flat dense no-caps size="sm" color="primary" label="انقل إلى بوابة النواة" :loading="busy" @click="askGateway(st, 'flexy-gateway')" />
                    <q-btn v-if="st.gateway === 'core'" flat dense no-caps size="sm" color="grey-8" label="أرجع إلى القديمة" :loading="busy" @click="askGateway(st, 'station-gateway')" />
                  </div>
                </template>
                <span v-else class="small muted">—</span>
                <div v-if="last(st) && !active(st)" class="small" :class="last(st).status === 'succeeded' ? 'text-positive' : last(st).status === 'cancelled' ? 'muted' : 'text-deep-orange'">
                  آخر تحديث: {{ UPDATE_STATUS[last(st).status] }}<span v-if="last(st).error"> ({{ keyRefused(last(st).error) ? 'GitHub رفض المفتاح' : offline(last(st).error) ? 'لم يصل الكمبيوتر إلى GitHub' : last(st).error }})</span>
                </div>
              </td>
              <td v-if="editStations">{{ st.gateway === 'core' ? 'النواة' : st.gateway === 'old' ? 'القديمة' : '—' }}</td>
            </tr>
            <tr v-if="!stationRows.length"><td colspan="5" class="text-center muted">لا كمبيوترات بهذا الفلتر</td></tr>
            <tr v-if="!stationActive && gone.length" class="static">
              <td colspan="5"><button type="button" class="link" @click="showOldStations = !showOldStations">قديمة ({{ gone.length }}) {{ showOldStations ? '▴' : '▾' }}</button></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <RechDoomPhones v-show="pageTab === 'sims'" />
    <!-- Never a full message store (Flexy Core 0040): «تصفير» empties every modem's store once the server saved each
         message. Rarely used (owner 2026-10-30): folded at the end; SIMs not connected are not listed, their request waits. -->
    <q-expansion-item v-show="pageTab === 'sims'" class="card q-pa-none" dense icon="sms" label="مخزن الرسائل" header-class="text-weight-bold">
      <div class="column q-gutter-xs q-pa-sm">
        <div class="help small muted">كل رسالة تُحفظ في السيرفر أولًا ثم تُحذف من الشريحة. لا شيء يُحذف قرب عملية مالية.</div>
        <q-btn outline no-caps color="negative" class="self-start" :label="`تصفير كل الشرائح (${wipeCount})`" :loading="wipeBusy" @click="askWipe(null)" />
        <div v-for="w in wipeShown" :key="w.sim_uuid" class="small" :class="w.pending ? 'text-deep-orange' : 'muted'">
          {{ w.label || w.sim_code || 'شريحة' }}:
          <span v-if="w.pending">في الانتظار (الكمبيوتر ينفّذ خلال دقيقة)</span>
          <span v-else>{{ w.store ? w.store.used + '/' + w.store.max : '—' }}</span>
        </div>
      </div>
    </q-expansion-item>
    <q-dialog v-model="details">
      <!-- On a phone the window never grows past the screen: long numbers and the tabs wrap or scroll inside it -->
      <q-card v-if="picked" class="sim-dialog">
        <q-card-section class="row items-center q-gutter-sm">
          <span class="col text-weight-bold"><bdi class="ltr">{{ picked.m.ip || '—' }}</bdi> · {{ stName(picked.st) }}</span>
          <q-badge :color="LEVEL[picked.m.level].color" :label="LEVEL[picked.m.level].label" />
        </q-card-section>
        <q-card-section class="column q-gutter-xs q-pt-none">
          <div v-for="r in picked.m.reasons" :key="r.code" :class="r.level === 'down' ? 'text-negative' : 'text-deep-orange'">{{ r.text }}</div>
          <div v-if="!picked.m.reasons.length" class="text-positive">جاهز</div>
        </q-card-section>
        <q-separator />
        <q-card-section class="kv">
          <span class="muted">الموديم</span><span>{{ picked.m.model || '—' }} · USB {{ usbOf(picked.m) ?? '—' }}</span>
          <!-- «رقم USB» written on the device (owner 2026-11-01, 0138): follows it by IMEI / serial -->
          <span class="muted">رقم USB</span>
          <span class="row items-center no-wrap q-gutter-xs">
            <q-input v-model.number="usbEdit" dense outlined type="number" inputmode="numeric" min="1" max="999" style="width:90px"
              :placeholder="String(picked.m.usb ?? '')" />
            <q-btn dense unelevated no-caps color="primary" label="احفظ" :loading="usbBusy" :disable="!picked.m.modem_uuid || usbEdit === (labels[picked.m.modem_uuid] ?? null)" @click="saveUsb(picked.m)" />
          </span>
          <span class="muted">آخر ظهور</span><span>{{ picked.m.last_seen_at ? clock(picked.m.last_seen_at) : '—' }}</span>
          <template v-if="picked.m.sim">
            <span class="muted">الشريحة</span><span>{{ simName(picked.m.sim, picked.st) || 'بلا اسم' }}<template v-if="adminName(picked.m.sim)"> · {{ picked.m.sim.code }}</template><span v-if="picked.m.sim.label"> · {{ picked.m.sim.label }}</span></span>
            <span class="muted">النوع</span><span>{{ picked.m.sim.sim_type_name }} · {{ picked.m.sim.approved ? 'معتمدة' : 'غير معتمدة' }}</span>
            <span class="muted">PIN</span><span>{{ picked.m.sim.pin_present ? 'محفوظ' : 'غير محفوظ' }}</span>
            <span class="muted">ICCID</span><bdi class="ltr">…{{ picked.m.sim.iccid_tail || '—' }}</bdi>
            <span class="muted">الرقم</span><span><bdi class="ltr">{{ picked.m.sim.msisdn || (picked.m.sim.msisdn_tail ? '…' + picked.m.sim.msisdn_tail : '—') }}</bdi> · {{ numberText(picked.m.sim) }}</span>
            <span class="muted">الرصيد</span><span :class="balanceClass(picked.m.sim)"><q-spinner v-if="isReading(picked.m.sim) || reading.busy" size="14px" class="q-mr-xs" color="primary" />{{ balanceText(picked.m.sim) }}<span v-if="picked.m.sim.balance_checked_at" class="muted"> · قُرئ {{ clock(picked.m.sim.balance_checked_at) }}</span></span>
            <template v-if="onboardingText(picked.m.sim)">
              <span class="muted">الاكتشاف الآلي</span><span :class="onboardingClass(picked.m.sim)">{{ onboardingText(picked.m.sim) }}</span>
            </template>
            <template v-if="noteOf(picked.m.sim)">
              <span class="muted">ملاحظة</span><span>{{ noteOf(picked.m.sim) }}</span>
            </template>
          </template>
          <template v-else>
            <span class="muted">الشريحة</span><span>لا شريحة</span>
          </template>
          <span class="muted">آخر نجاح USSD</span><span>{{ picked.m.ussd.lastSuccessAt ? clock(picked.m.ussd.lastSuccessAt) : 'لا يوجد' }}</span>
          <span class="muted">آخر محاولة</span><span>{{ picked.m.ussd.lastAttemptAt ? clock(picked.m.ussd.lastAttemptAt) : 'لا يوجد' }}</span>
          <span class="muted">مهل متتالية</span><span>{{ picked.m.ussd.timeoutsInRow }}</span>
        </q-card-section>
        <template v-if="picked.m.sim">
          <q-separator />
          <!-- The SIM's settings: a name beside the fixed code, a free note, and the PIN (never shown) -->
          <q-card-section class="column q-gutter-sm">
            <div class="text-weight-bold">إعدادات الشريحة</div>
            <q-input v-model="form.label" dense outlined maxlength="80" label="اسم خاص" :hint="'يظهر بجانب ' + (picked.m.sim.code || 'الاسم الثابت')" />
            <q-input v-model="form.note" dense outlined autogrow maxlength="500" label="ملاحظة" />
            <q-input v-model="form.pin" dense outlined type="password" inputmode="numeric" maxlength="8" autocomplete="off"
              :label="picked.m.sim.pin_present ? 'PIN جديد (اتركه فارغًا لإبقاء المحفوظ)' : 'PIN'" :error="!!form.pin && !/^[0-9]{4,8}$/.test(form.pin)" error-message="4 إلى 8 أرقام" />
            <div v-if="form.error" class="small text-negative">{{ form.error }}</div>
            <div v-if="form.saved" class="small text-positive">حُفظ</div>
            <div v-if="reading.text" class="small" :class="reading.ok ? 'text-positive' : 'text-negative'">{{ reading.text }}</div>
          </q-card-section>
        </template>
        <template v-if="picked.m.sim">
          <q-separator />
          <q-card-section class="q-pt-sm"><ModemPanel :sim-uuid="picked.m.sim.sim_uuid" :sim-type="picked.m.sim.sim_type" :phone="String(picked.st.agent_version || '').startsWith('phone-')"
            :sim-name="(simName(picked.m.sim, picked.st) || '') + (picked.st.code ? ' · ' + picked.st.code : '')" /></q-card-section>
        </template>
        <q-card-actions align="right" class="wrap">
          <!-- The admin phone (Flexy Core 0037): «اكتشاف الرصيد» = one *222# from the phone; its reply is the
               starting point of the phone's cumulative, which the send from the phone is checked against -->
          <q-btn v-if="picked.m.sim?.approved || canRetryFirstBalance(picked.m.sim) || (picked.m.sim && isPhone(picked.st))" outline no-caps color="primary"
            :label="picked.m.sim && isPhone(picked.st) ? 'اكتشاف الرصيد' : 'اقرأ الرصيد'" :loading="reading.busy" @click="readBalance" />
          <q-btn v-if="picked.m.sim && !isPhone(picked.st)" flat no-caps color="negative" label="أفرغ المخزن" :loading="wipeBusy" @click="askWipe(picked.m.sim)" />
          <q-btn v-if="picked.m.sim" unelevated no-caps color="primary" label="حفظ" :loading="form.busy" :disable="!!form.pin && !/^[0-9]{4,8}$/.test(form.pin)" @click="saveSettings" />
          <q-btn flat no-caps label="إغلاق" v-close-popup />
        </q-card-actions>
      </q-card>
    </q-dialog>
    <!-- «صفحة الكمبيوتر»: the computer runs one of its fixed actions with its next heartbeat (about 20 s) -->
    <q-dialog v-model="actionsOpen">
      <q-card style="width:100%;max-width:520px">
        <q-card-section class="column q-gutter-sm">
          <div class="row items-center no-wrap">
            <div class="col text-weight-bold">أوامر {{ actionsSt?.code || 'الكمبيوتر' }}</div>
            <q-btn flat round dense icon="close" v-close-popup />
          </div>
          <!-- Before 0.9.0 the computer cannot take them: the one line by hand, once (or through AnyDesk) -->
          <div v-if="actionsSt && !agentAtLeast(actionsSt, '0.9.0')" class="column q-gutter-xs warn-box">
            <div class="small text-weight-bold">هذا الكمبيوتر على نسخة قديمة ({{ actionsSt.agent_version || '؟' }}): لا يأخذ الأوامر من هنا بعد.</div>
            <div class="small">مرة واحدة أمامه أو عبر AnyDesk: اضغط زر النافذة التي تفتحها، والصق فيها (Enter معه)، ثم اضغط «حدّث» هنا.</div>
            <div v-if="places[actionsSt.station_uuid]" class="small">مكانه: <b class="ltr">{{ places[actionsSt.station_uuid].dir }}</b></div>
            <code class="ltr fix-line">{{ FIX_LINE }}</code>
            <!-- One button per window (owner 2026-10-30: «أريد أن ألصق من الموقع»): the line with its Enter, and DONE when it ran -->
            <!-- A file to carry (owner 2026-10-30): downloaded on the phone, moved by cable or AnyDesk, double-clicked: no typing, no Enter -->
            <q-btn unelevated no-caps color="positive" icon="download" :label="'نزّل حزمة الإصلاح (الإصدار ' + FIX_VERSION + ')'" @click="downloadFix" />
            <div class="small muted">انقلها إلى الكمبيوتر بالكابل أو بنقل الملفات في AnyDesk، وفكّ ضغطها. فيها: ملف تشغّله بضغطتين، وآخر بصلاحية المدير، وملف PowerShell، وأوامر cmd وPowerShell وGit Bash لتنسخها بيدك، و«اقرأني» بالعربية.</div>
            <div class="row q-gutter-xs">
              <q-btn v-for="sh in SHELLS" :key="sh.key" unelevated dense no-caps size="sm" color="primary" icon="content_copy" :label="sh.label" @click="copyFix(sh)" />
            </div>
            <div class="small muted">cmd: زر Windows ← اكتب cmd ← Enter · PowerShell: النافذة الزرقاء · Git Bash: عنوانها MINGW64. بعد اللصق يظهر DONE إن نجح.</div>
          </div>
          <div v-if="actionsSt?.gateway === 'old'" class="small text-deep-orange">هذا الكمبيوتر على البوابة القديمة: الأوامر تصل عبر بوابة النواة فقط (تعديل ← انقل إلى بوابة النواة).</div>
          <!-- Only what this computer needs now (owner 2026-10-30: «زر لا حاجة له يختفي»); the rest folded, for a problem
               the page cannot see -->
          <!-- Agent 0.9.3 repairs a modem gone by itself (restart, then its USB port): no button to press for it -->
          <div v-if="actionsSt && agentAtLeast(actionsSt, '0.9.3')" class="help small text-primary">🔧 الإصلاح الذاتي يعمل: إذا اختفى مودم، يعيد البرنامج تشغيل نفسه بعد دقيقتين، ثم منفذ USB الخاص به، ثم ينبّهك إن لم يرجع.</div>
          <!-- «افحص الإنترنت» (Flexy Core 0114, Agent 0.9.4): read only, the cut layer and each layer's line -->
          <div v-if="actionsSt" class="row items-start no-wrap q-gutter-sm act-row">
            <div class="col"><div class="text-weight-bold">{{ NET_CHECK.label }}</div><div class="small muted">{{ NET_CHECK.note }}</div>
              <div v-if="!agentAtLeast(actionsSt, '0.9.4')" class="small text-deep-orange">يحتاج تحديث البرنامج إلى 0.9.4 على هذا الكمبيوتر أولًا.</div>
              <div v-else-if="lastAction('net_check')" class="small" style="white-space: pre-line" :class="lastAction('net_check').done_at ? (lastAction('net_check').ok ? 'text-positive' : 'text-negative') : 'text-primary'">
                {{ lastAction('net_check').done_at ? (lastAction('net_check').ok ? '✓ ' : '✗ ') + (lastAction('net_check').message || '') : (lastAction('net_check').sent_at ? 'وصل الكمبيوتر، يفحص (حتى دقيقة)…' : 'ينتظر نبضة الكمبيوتر…') }}
                <span class="muted"> · {{ clock(lastAction('net_check').done_at || lastAction('net_check').asked_at) }}{{ lastAction('net_check').source === 'local' ? ' · ضُغط على الكمبيوتر نفسه' : '' }}</span>
                <q-btn v-if="lastAction('net_check').done_at" flat dense no-caps size="sm" color="primary" icon="smart_toy" label="انسخ لـClaude"
                  @click="copyToClipboard(`فحص الإنترنت · ${actionsSt.code || ''} · ${clock(lastAction('net_check').done_at)}\n${lastAction('net_check').message || ''}`).then(() => Notify.create({ type: 'positive', message: 'نُسخ.' }))" />
              </div>
            </div>
            <q-btn unelevated dense no-caps color="primary" label="افحص" :disable="!agentAtLeast(actionsSt, '0.9.4')" :loading="busy" @click="askAction(NET_CHECK)" />
          </div>
          <div v-if="actionsSt && !neededActions.length" class="small text-positive">✓ لا يحتاج هذا الكمبيوتر شيئًا الآن.</div>
          <div v-for="a in neededActions" :key="a.key" class="row items-center no-wrap q-gutter-sm act-row">
            <div class="col"><div class="text-weight-bold">{{ a.label }}</div><div class="small muted">{{ a.note }}</div>
              <div v-if="lastAction(a.key)" class="small" :class="lastAction(a.key).done_at ? (lastAction(a.key).ok ? 'text-positive' : 'text-negative') : 'text-primary'">
                {{ lastAction(a.key).done_at ? (lastAction(a.key).ok ? '✓ ' : '✗ ') + (lastAction(a.key).message || '') : (lastAction(a.key).sent_at ? 'وصل الكمبيوتر، يُنفَّذ…' : 'ينتظر نبضة الكمبيوتر…') }}
                <span class="muted"> · {{ clock(lastAction(a.key).done_at || lastAction(a.key).asked_at) }}{{ lastAction(a.key).source === 'local' ? ' · ضُغط على الكمبيوتر نفسه' : '' }}</span></div>
            </div>
            <q-btn unelevated dense no-caps color="primary" label="نفّذ" :loading="busy" @click="askAction(a)" />
          </div>
          <q-expansion-item v-if="otherActions.length" dense dense-toggle switch-toggle-side label="أوامر أخرى (عند مشكلة لا تظهر هنا)" header-class="small text-grey-8 q-px-none">
            <div v-for="a in otherActions" :key="a.key" class="row items-center no-wrap q-gutter-sm act-row">
              <div class="col"><div>{{ a.label }}</div><div class="small muted">{{ a.note }}</div></div>
              <q-btn outline dense no-caps size="sm" color="grey-8" label="نفّذ" :loading="busy" @click="askAction(a)" />
            </div>
          </q-expansion-item>
        </q-card-section>
      </q-card>
    </q-dialog>
  </q-page>
</template>

<script setup>
import SectionTabs from 'src/components/SectionTabs.vue'
import { MONITOR_TABS } from 'src/api/sections'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { copyToClipboard, Dialog, Notify } from 'quasar'
import * as flexy from 'src/api/flexy'
import { makeZip } from 'src/api/zip'
import { copyForClaude } from 'src/composables/useClaudeCopy'
import { money } from 'src/api/format'
import { stationTag } from 'src/api/stationTag'
import { useBell } from 'src/composables/useBell'
import ModemPanel from 'src/components/ModemPanel.vue'
import AddComputer from 'src/components/AddComputer.vue'
import RechDoomPhones from 'src/components/RechDoomPhones.vue'

// Read only: Flexy Core answers from what the stations already report. No USSD, no money.
const LEVEL = {
  down: { label: '⛔ معطّل', color: 'negative' },
  warn: { label: '⚠️ تحذير', color: 'orange-8' },
  ok: { label: '✅ جاهز', color: 'positive' },
  old: { label: 'قديم', color: 'grey-6' }
}
// The bell's count follows this page without a second request
const { devicesDown, simAlerts: simAlertCount } = useBell()
// Stopped SIMs, again every day until solved (Flexy Core 0039)
const simAlerts = ref([])
const simAlertsBusy = ref(false)
async function loadSimAlerts () {
  const res = await flexy.ownerSimAlerts()
  if (res.status === 200 && res.body?.ok) { simAlerts.value = res.body.alerts || []; simAlertCount.value = simAlerts.value.length }
}
async function simAlertsSeen () {
  simAlertsBusy.value = true
  try {
    const res = await flexy.ownerSimAlertsSeen()
    if (res.status === 200 && res.body?.ok) { simAlerts.value = res.body.alerts || []; simAlertCount.value = simAlerts.value.length }
  } finally {
    simAlertsBusy.value = false
  }
}
const tree = ref(null)
const error = ref('')
const busy = ref(false)
// «صفحة الكمبيوتر» (Flexy Core 0099, Agent 0.9.0): the same three actions as the computer's local page
const STATION_ACTIONS = [
  { key: 'fix_update', label: 'أصلح ملفات التحديث', note: 'يعيد ملفات البرنامج إلى نسختها النظيفة، فيقبل التحديث بعدها.' },
  { key: 'restart_agent', label: 'أعد تشغيل البرنامج', note: 'حين لا يعمل شيء على المودمات (ثوانٍ).' },
  { key: 'reconnect_wifi', label: 'أعد الاتصال بالواي فاي', note: 'يقطع الواي فاي ويعيده إلى الشبكة نفسها.' }
]
const NET_CHECK = { key: 'net_check', label: 'افحص الإنترنت', note: 'يقرأ فقط: الراوتر، ثم الإنترنت، ثم الأسماء، ثم خادمنا، ويقول أي طبقة مقطوعة.' }
// Forward slashes: the same line works in cmd and in Git Bash (which eats backslashes, owner 2026-10-30)
const FIX_LINE = 'git -C C:/MyTool/station-connect checkout -- agent/src agent/package.json'
const actionsOpen = ref(false)
const actionsSt = ref(null)
const actionsList = ref([])
let actionsTimer = null
const agentAtLeast = (st, v) => {
  const a = String(st.agent_version || '0').split('.').map(Number)
  const b = v.split('.').map(Number)
  for (let i = 0; i < 3; i++) if ((a[i] || 0) !== b[i]) return (a[i] || 0) > b[i]
  return true
}
const places = ref({})
// «سجلّ الشبكة» (0115): newest first, from the devices answer
const netOpen = ref(null)
const netOf = (st) => tree.value?.net_events?.[st.station_uuid] || []
async function loadActions () {
  const r = await flexy.stationActions().catch(() => null)
  if (r?.status === 200 && r.body?.ok) {
    actionsList.value = r.body.actions || []
    places.value = r.body.places || {}
  }
}
// Needed now: the files when the update says they are not clean; a restart when its modems are not all connected
const needs = (st, key) => {
  if (!st) return false
  if (key === 'fix_update') return mainOf(st)?.main_error === 'GIT_LOCAL_CHANGES'
  // From 0.9.3 the program restarts itself for a modem gone: the button only when it is older
  if (key === 'restart_agent' && agentAtLeast(st, '0.9.3')) return false
  if (key === 'restart_agent') return live(st).some((m) => !isConnected(m)) || (st.reasons || []).some((r) => r.level === 'down')
  return false
}
const neededFor = (st) => STATION_ACTIONS.filter((a) => needs(st, a.key))
const neededActions = computed(() => STATION_ACTIONS.filter((a) => needs(actionsSt.value, a.key)))
const otherActions = computed(() => STATION_ACTIONS.filter((a) => !needs(actionsSt.value, a.key)))
const lastAction = (key) => actionsList.value.find((x) => x.station_uuid === actionsSt.value?.station_uuid && x.key === key) || null
function openActions (st) {
  actionsSt.value = st
  actionsOpen.value = true
  loadActions()
  clearInterval(actionsTimer)
  // While open: the result shows when the computer says it (its heartbeat every 20 s)
  actionsTimer = setInterval(() => { if (actionsOpen.value) loadActions(); else clearInterval(actionsTimer) }, 5000)
}
function askAction (a) {
  Dialog.create({ title: a.label + '؟', message: `${actionsSt.value.code || 'الكمبيوتر'} ينفّذه مع نبضته التالية (نحو 20 ثانية).`, cancel: 'لا', ok: 'نعم' })
    .onOk(async () => {
      busy.value = true
      try {
        const r = await flexy.askStationAction(actionsSt.value.station_uuid, a.key)
        if (r.status !== 200 || r.body?.ok === false) throw new Error(r.body?.error === 'ACTIONS_NOT_READY' ? 'طبّق 0099 أولًا' : (r.body?.error || 'FLEXY_CORE'))
        await loadActions()
      } catch (e) {
        Notify.create({ type: 'negative', message: 'لم يُطلب: ' + (e.message || ''), position: 'top' })
      } finally {
        busy.value = false
      }
    })
}
const PS_FIX = "$r = Get-ChildItem C:\\ -Directory -Filter station-connect -Recurse -Depth 4 -ErrorAction SilentlyContinue | Where-Object { Test-Path ($_.FullName + '\\.git') } | Select-Object -First 1; " +
  "if ($r) { git -C $r.FullName checkout -- agent/src agent/package.json; if ($?) { echo ('DONE ' + $r.FullName) } } else { echo 'NOT FOUND' }"
// Each window's own way to say «then DONE», and a line end so the paste runs it (cmd and PowerShell run it at once)
const SHELLS = [
  { key: 'cmd', label: 'انسخ لـ cmd', text: FIX_LINE + ' && echo DONE\r\n' },
  // PowerShell finds the copy itself (owner 2026-10-30: one computer had it outside C:\\MyTool)
  { key: 'ps', label: 'انسخ لـ PowerShell', text: PS_FIX + '\r\n' },
  { key: 'bash', label: 'انسخ لـ Git Bash', text: FIX_LINE + ' && echo DONE\n' }
]
// The fix as a file: finds the station program by what runs (node …\agent\src\index.js), else by its files on C:, D:, E:
// (not by a folder name: one computer had another), then «git checkout» of its own files only
// The fix package's own number: raised whenever what is inside changes
const FIX_VERSION = 4
const FIX_PS = [
  '$dirs = @()',
  "Get-CimInstance Win32_Process -Filter \"name='node.exe'\" | ForEach-Object { if ($_.CommandLine -match '([A-Za-z]:\\\\[^\"]*?)\\\\agent\\\\(src|updater)\\\\') { $dirs += $Matches[1] } }",
  "if (-not $dirs) { foreach ($d in 'C:\\','D:\\','E:\\') { if (Test-Path $d) { Get-ChildItem $d -Directory -Recurse -Depth 5 -ErrorAction SilentlyContinue | Where-Object { (Test-Path ($_.FullName + '\\.git')) -and (Test-Path ($_.FullName + '\\agent\\src\\index.js')) } | ForEach-Object { $dirs += $_.FullName } } } }",
  '$dirs = @($dirs | Select-Object -Unique)',
  "if ($dirs.Count -eq 0) { Write-Host 'NOT FOUND: the station program is not on this computer'; exit 1 }",
  "foreach ($r in $dirs) { git -C $r checkout -- agent/src agent/package.json; if ($?) { Write-Host ('DONE ' + $r) } else { Write-Host ('FAILED ' + $r) } }"
].join('\n')
// Every way in one package (owner 2026-10-30: «لا تحكمني بملف واحد»): run it, run it as admin, run the .ps1, or copy a
// line into cmd, PowerShell or Git Bash. The station's own folder first when it is known (Agent 0.9.1).
const GIT_BASH_FIX = "r=$(for d in /c /d /e; do find \"$d\" -maxdepth 6 -path '*/agent/src/index.js' 2>/dev/null | head -1; done | head -1); r=${r%/agent/src/index.js}; " +
  'if [ -n "$r" ]; then git -C "$r" checkout -- agent/src agent/package.json && echo "DONE $r"; else echo "NOT FOUND"; fi'
function downloadFix () {
  // -EncodedCommand: UTF-16LE in base64, so no quote of the script can break cmd or the .bat
  const bytes = new Uint8Array(FIX_PS.length * 2)
  for (let i = 0; i < FIX_PS.length; i++) { const c = FIX_PS.charCodeAt(i); bytes[2 * i] = c & 255; bytes[2 * i + 1] = c >> 8 }
  let bin = ''
  bytes.forEach((b) => { bin += String.fromCharCode(b) })
  const encoded = 'powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + btoa(bin)
  const dir = places.value[actionsSt.value?.station_uuid]?.dir
  const known = dir ? `git -C "${dir.replace(/\\/g, '/')}" checkout -- agent/src agent/package.json` : ''
  const crlf = (lines) => lines.join('\r\n') + '\r\n'
  const bat = crlf(['@echo off', 'echo Flexy: fixing the station program files...', encoded, 'echo.', 'echo Now press "update" on the devices page.', 'pause'])
  const admin = crlf(['@echo off', 'rem Runs 1-run-me.bat as administrator (Windows asks Yes / No)',
    'powershell -NoProfile -Command "Start-Process -FilePath \'%~dp01-run-me.bat\' -Verb RunAs"'])
  // Only commands, nothing else (owner 2026-10-30: he pasted the whole file, its titles ran as commands): the direct
  // line when the folder is known, else the searching one; then a line so the paste runs the first
  const lines = (_title, direct, search) => crlf([known ? direct : search, 'echo FIN'])
  const readme = '\uFEFF' + crlf([
    'حزمة إصلاح برنامج المحطة (Flexy) — الإصدار ' + FIX_VERSION + ' · ' + new Date().toLocaleString('ar-DZ', { timeZone: 'Africa/Algiers' }),
    '',
    'الطريقة 1: اضغط مرتين على 1-run-me.bat ، وانتظر حتى يظهر DONE.',
    'الطريقة 2: إن لم ينجح، اضغط مرتين على 2-run-as-admin.bat ثم اختر «نعم».',
    'الطريقة 3: زر يمين على 3-Flexy-fix.ps1 ← Run with PowerShell.',
    'الطريقة 4: افتح cmd أو PowerShell أو Git Bash، وانسخ السطر من الملف الذي باسمها (4 أو 5 أو 6)، ثم Enter.',
    'الطريقة 5: من داخل مجلد البرنامج نفسه (فيه agent وserver وstart-agent.bat): اضغط شريط العنوان، اكتب cmd، Enter، والصق الملف 7.',
    'كل ملف أوامر فيه الأمر وحده: انسخه كله والصقه.',
    '',
    'DONE مع مكان البرنامج = نجح: ارجع إلى صفحة الأجهزة واضغط «حدّث».',
    'NOT FOUND = البرنامج ليس على هذا الكمبيوتر.',
    ...(dir ? ['', 'مكان البرنامج على هذا الكمبيوتر: ' + dir] : [])
  ])
  const zip = makeZip([
    { name: '0-README-اقرأني.txt', text: readme },
    { name: '1-run-me.bat', text: bat },
    { name: '2-run-as-admin.bat', text: admin },
    { name: '3-Flexy-fix.ps1', text: '\uFEFF' + FIX_PS + '\r\nRead-Host "Press Enter to close"\r\n' },
    { name: '4-cmd.txt', text: lines('cmd:', known + ' && echo DONE', encoded) },
    { name: '5-powershell.txt', text: lines('PowerShell:', known + '; if ($?) { echo DONE }', FIX_PS.split('\n').join('; ')) },
    { name: '6-git-bash.txt', text: lines('Git Bash:', known + ' && echo DONE', GIT_BASH_FIX) },
    // Standing inside the program's folder (owner 2026-10-30): the plain line, no search
    { name: '7-inside-the-folder.txt', text: crlf(['git checkout -- agent/src agent/package.json && echo DONE', 'echo FIN']) }
  ])
  const a = document.createElement('a')
  a.href = URL.createObjectURL(zip)
  // A number on everything given (owner 2026-10-30: «أي ملف تعطيه له ترقيم»): the package's version and the minute it was
  // made, so an old download is never taken for the new one
  const d = new Date()
  const p2 = (x) => String(x).padStart(2, '0')
  const stamp = `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}_${p2(d.getHours())}-${p2(d.getMinutes())}`
  a.download = `Flexy-fix-v${FIX_VERSION}` + (actionsSt.value?.code ? '-' + actionsSt.value.code : '') + '-' + stamp + '.zip'
  a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 5000)
}
async function copyFix (sh) {
  // Its real folder when known (0.9.1): no guess, no search
  const dir = places.value[actionsSt.value?.station_uuid]?.dir
  const line = dir ? `git -C "${dir.replace(/\\/g, '/')}" checkout -- agent/src agent/package.json` : null
  const text = !line ? sh.text : sh.key === 'cmd' ? line + ' && echo DONE\r\n' : sh.key === 'ps' ? line + '; if ($?) { echo DONE }\r\n' : line + ' && echo DONE\n'
  await copyToClipboard(text)
  Notify.create({ type: 'positive', message: 'نُسخ السطر', position: 'top', timeout: 1200 })
}
const clock = (t) => new Date(t).toLocaleString('ar-DZ', { timeZone: 'Africa/Algiers', dateStyle: 'short', timeStyle: 'short' })

// The phone is apart (owner 2026-10-28): computers only in the counts, the tables and the SIMs.
const computers = computed(() => (tree.value?.stations || []).filter((s) => !s.phone && !isPhone(s)))
// Names the owner reads (owner 2026-10-29): the admin phone is «هاتف الإدارة», not a «server-N»; its SIMs are
// «إدارة-1», «إدارة-2»… (by their codes, as on «المراقبة»). Display only: Station Connect's codes do not change.
const adminNames = computed(() => {
  const sims = (tree.value?.stations || []).filter((s) => s.phone || isPhone(s)).flatMap((s) => s.modems || []).map((m) => m.sim).filter(Boolean)
  return Object.fromEntries([...sims].sort((a, b) => String(a.code).localeCompare(String(b.code))).map((x, i) => [x.sim_uuid, `إدارة-${i + 1}`]))
})
const adminName = (sim) => (sim ? adminNames.value[sim.sim_uuid] || '' : '')
// 0130: a phone may serve the shops too, so it is «📱 الهاتف» (its name on the phone), no longer «هاتف الإدارة»
const stName = (st) => (st && (st.phone || isPhone(st)) ? stationTag(st.code, true) + (st.computer_name ? ' · ' + String(st.computer_name).replace(/^هاتف[^·]*·\s*/, '') : '') : (st?.code ? stationTag(st.code) : 'كمبيوتر'))
const simName = (sim, st) => (sim ? adminName(sim) || (st && (st.phone || isPhone(st)) ? 'إدارة' : sim.code) : '')
const phones = computed(() => (tree.value?.stations || []).filter((s) => (s.phone || isPhone(s)) && s.level !== 'old'))
const current = computed(() => computers.value.filter((s) => s.level !== 'old'))
const gone = computed(() => computers.value.filter((s) => s.level === 'old'))
const live = (st) => st.modems.filter((m) => m.level !== 'old')
// «مطفأ»: silent past the core's off limit (a minute); older cores only say absent_minutes
const isAbsent = (st) => (typeof st.off === 'boolean' ? st.off : !!st.absent_minutes)
const presentCount = computed(() => current.value.filter((s) => !isAbsent(s)).length)
// Connected = the modem answers and holds a SIM (ready or with a warning); otherwise not.
const isConnected = (m) => !!m.sim && m.level !== 'down'
// Computers table: active (present) first; «غير النشطة» = absent; gone 7+ days only under «قديمة».
const stationActive = ref(true)
const showOldStations = ref(false)
const stationRows = computed(() => stationActive.value
  ? current.value.filter((st) => !isAbsent(st))
  : [...current.value.filter(isAbsent), ...(showOldStations.value ? gone.value : [])])

// SIMs: the computer first, then active or not inside it; a type tile narrows it further.
// Filters stay as chosen across the 30-second refresh.
const SUMMARY_TYPES = [['mobilis-arsselli', 'أرسلي'], ['mobilis-sama', 'Sama'], ['djezzy-flexy', 'جيزي'], ['ooredoo-flexy', 'أوريدو']]
const typeName = (type) => SUMMARY_TYPES.find(([t]) => t === type)?.[1] || type
const typeFilter = ref(null)
const simStation = ref('all')
const simTab = ref('all')
// «هاتف الإدارة» is gone (owner 2026-11-01): its phones are in «الشرائح»
const readTab = () => { try { return localStorage.getItem('devices.tab') === 'computers' ? 'computers' : 'sims' } catch { return 'sims' } }
const pageTab = ref(readTab())
watch(pageTab, (v) => { try { localStorage.setItem('devices.tab', v) } catch { /* private window */ } })
const route = useRoute()
const showOldSims = ref(false)
const pickType = (type) => { typeFilter.value = typeFilter.value === type ? null : type }
function clearFilters () { typeFilter.value = null; simStation.value = 'all' }
// The phones 📱 in the same row as server-N (owner 2026-11-01)
const stationChips = computed(() => [
  { value: 'all', label: 'الكل' },
  ...current.value.filter((st) => !isAbsent(st)).map((st) => ({ value: st.station_uuid, label: st.code || 'كمبيوتر' })),
  ...phones.value.filter((st) => !isAbsent(st)).map((st) => ({ value: st.station_uuid, label: stName(st) })),
  ...current.value.filter(isAbsent).map((st) => ({ value: st.station_uuid, label: (st.code || 'كمبيوتر') + ' (مطفأ)', muted: true })),
  ...phones.value.filter(isAbsent).map((st) => ({ value: st.station_uuid, label: stName(st) + ' (مطفأ)', muted: true }))
])
const pickedStation = computed(() => (simStation.value === 'all' ? null
  : [...current.value, ...phones.value].find((st) => st.station_uuid === simStation.value) || null))
// Every SIM with its computer; old = its modem or its computer gone for longer than old_days.
const everySim = computed(() => [...current.value, ...phones.value, ...gone.value].flatMap((st) =>
  st.modems.filter((m) => m.sim).map((m) => ({ st, m, old: st.level === 'old' || m.level === 'old' }))))
const isActive = (r) => !r.old && !isAbsent(r.st) && isConnected(r.m)
// The core's one word; an older core without it: the old rule
const simState = (r) => r.m.sim_state || (isActive(r) ? 'ready' : isAbsent(r.st) ? 'station_off' : 'needs_action')
const STATE = {
  ready: null,
  station_off: { label: 'كمبيوترها مطفأ', color: 'grey-6' },
  needs_action: { label: 'تحتاج تدخلًا', color: 'negative' }
}
// By computer number, then USB number (owner 2026-11-01); «الكل»: the ready ones first
const stNo = (st) => Number((String(st?.code || '').match(/\d+/) || [])[0] ?? 999)
const byPlace = (a, b) => stNo(a.st) - stNo(b.st) || (Number(usbOf(a.m)) || 999) - (Number(usbOf(b.m)) || 999)
// The part that is down: the computer off, the modem gone from its USB, else the SIM itself
// Grouped by computer: the computers on first (by number), then the ones off; in each, the ready SIMs first
const simGroups = computed(() => {
  const m = new Map()
  for (const r of shownSims.value) {
    if (!m.has(r.st.station_uuid)) m.set(r.st.station_uuid, { st: r.st, rows: [], down: isAbsent(r.st) })
    m.get(r.st.station_uuid).rows.push(r)
  }
  const ready = (r) => (simState(r) === 'ready' ? 0 : 1)
  return [...m.values()].map((g) => ({ ...g, rows: g.rows.sort((a, b) => ready(a) - ready(b) || byPlace(a, b)) }))
    .sort((a, b) => (a.down - b.down) || stNo(a.st) - stNo(b.st))
})
// A phone's SIM is «SIM-1 / SIM-2» (its slot), a computer's modem «USB-N» (owner 2026-11-01)
const slotOf = (r) => (isPhone(r.st) || r.st.phone ? 'SIM-' + ((r.m.modem_uuid && labels.value[r.m.modem_uuid]) || 1) : 'USB-' + (usbOf(r.m) ?? '?'))
// «الرصيد» / «USSD» in the card itself
// The minimum before a SIM's balance turns red (owner 2026-11-01: «إذا وصل إلى الحد الأدنى»)
const MIN_BALANCE = 1000
const ussdOpen = ref(null)
const ussdCode = ref('')
function openUssd (sim, code) {
  if (ussdOpen.value === sim.sim_uuid && ussdCode.value === code) { ussdOpen.value = null; return }
  ussdCode.value = code
  ussdOpen.value = sim.sim_uuid
}
// 0139: per-SIM minimum / daily maximum (today's count) and the «رقمي» codes; Sama's *222# known (owner 2026-11-01)
const limitsView = computed(() => tree.value?.sim_limits || { limits: {}, number_codes: {} })
const limitOf = (sim) => limitsView.value.limits?.[sim?.sim_uuid] || {}
const minOf = (sim) => limitOf(sim).min_balance ?? MIN_BALANCE
const NUMBER_CODES = { 'mobilis-sama': '*222#' }
const numberCode = (sim) => limitsView.value.number_codes?.[sim.sim_type] || NUMBER_CODES[sim.sim_type] || ''
function myNumber (sim) {
  const c = numberCode(sim)
  if (!c) return Notify.create({ message: 'اكتب كود «رقمي» لهذا النوع مرة واحدة في ⚙️، ثم اضغط «رقمي».', timeout: 3500 })
  openUssd(sim, c)
}
const setOpen = ref(null)
const setBusy = ref(false)
const setForm = ref({ min: null, max: null, slot: null, code: '' })
function openSettings (r) {
  if (setOpen.value === r.m.sim.sim_uuid) { setOpen.value = null; return }
  const l = limitOf(r.m.sim)
  setForm.value = { min: l.min_balance ?? null, max: l.max_per_day ?? null, slot: (r.m.modem_uuid && labels.value[r.m.modem_uuid]) ?? null, code: limitsView.value.number_codes?.[r.m.sim.sim_type] || NUMBER_CODES[r.m.sim.sim_type] || '' }
  setOpen.value = r.m.sim.sim_uuid
}
const blank = (v) => (v === '' || v === null || v === undefined ? null : Number(v))
async function saveSimSet (r) {
  setBusy.value = true
  try {
    const f = setForm.value
    const res = await flexy.ownerSimLimits(r.m.sim.sim_uuid, blank(f.min), blank(f.max))
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error === 'MIGRATION_0139_PENDING' ? 'طبّق 0139 من «ينتظر تطبيقك» أولًا.' : (res.body?.error || 'FLEXY_CORE'))
    if (r.m.modem_uuid && blank(f.slot) !== ((labels.value[r.m.modem_uuid]) ?? null)) {
      const m = await flexy.ownerModemLabel(r.m.modem_uuid, blank(f.slot))
      if (m.status !== 200 || !m.body?.ok) throw new Error(m.body?.error || 'FLEXY_CORE')
    }
    const saved = limitsView.value.number_codes?.[r.m.sim.sim_type] || ''
    if ((f.code || '').trim() !== saved && (f.code || '').trim() !== (NUMBER_CODES[r.m.sim.sim_type] || '')) {
      const c = await flexy.ownerNumberCode(r.m.sim.sim_type, (f.code || '').trim())
      if (c.status !== 200 || !c.body?.ok) throw new Error(c.body?.error === 'CODE_INVALID' ? 'الكود يبدأ بـ * أو # وينتهي بـ #' : (c.body?.error || 'FLEXY_CORE'))
    }
    Notify.create({ type: 'positive', message: 'حُفظت إعدادات ' + (r.m.sim.code || 'الشريحة'), position: 'top', timeout: 1500 })
    setOpen.value = null
    await load()
  } catch (e) {
    Notify.create({ type: 'negative', message: e.message })
  } finally {
    setBusy.value = false
  }
}
const rowReading = ref(null)
const rowRead = ref({})
async function readRowBalance (sim) {
  rowReading.value = sim.sim_uuid
  try {
    const res = await flexy.readSimBalance(sim.sim_uuid)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    rowRead.value[sim.sim_uuid] = res.body.sent ? 'أُرسل كود الرصيد، والرد يظهر خلال دقيقة' : 'سيُرسل عند اتصال الشريحة'
    setTimeout(load, 20000)
  } catch (e) {
    rowRead.value[sim.sim_uuid] = 'لم يُرسل: ' + (READ_ERRORS[e.message] || e.message || 'FLEXY_CORE')
  } finally {
    rowReading.value = null
  }
}
const placeDown = (r) => (simState(r) === 'ready' ? null : isAbsent(r.st) ? 'pc' : modemGone(r) ? 'usb' : 'sim')
const simRows = computed(() => {
  const rows = everySim.value.filter((r) =>
    (simStation.value === 'all' || r.st.station_uuid === simStation.value) && (!typeFilter.value || r.m.sim.sim_type === typeFilter.value))
    .sort(byPlace)
  const now = rows.filter((r) => !r.old)
  return {
    all: [...now.filter((r) => simState(r) === 'ready'), ...now.filter((r) => simState(r) !== 'ready')],
    ready: now.filter((r) => simState(r) === 'ready'),
    station_off: now.filter((r) => simState(r) === 'station_off'),
    needs_action: now.filter((r) => simState(r) === 'needs_action'),
    old: rows.filter((r) => r.old)
  }
})
// 0113: approved SIMs held by no modem now (Flexy Core)
const missingSims = computed(() => tree.value?.missing_sims || [])
const retiring = ref(null)
const stationOffText = (x) => {
  const st = current.value.find((s) => s.code === x.station_code)
  return st && isAbsent(st) ? ' (الكمبيوتر مطفأ)' : ''
}
async function retire (x, on) {
  retiring.value = x.sim_uuid
  try {
    const res = await flexy.ownerSimRetire(x.sim_uuid, on)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error === 'MIGRATION_0113_PENDING' ? 'طبّق 0113 من «ينتظر تطبيقك» أولًا.' : (res.body?.error || 'FLEXY_CORE'))
    Notify.create({ type: 'positive', message: on ? `أُلغي تتبّع ${x.code}: لا تنبيه عنها حتى تظهر.` : `رجع تتبّع ${x.code}.` })
    await load()
  } catch (e) {
    Notify.create({ type: 'negative', message: e.message })
  } finally {
    retiring.value = null
  }
}
// From an alert (owner 2026-10-30: «الضغط على التنبيه يفتح الشريحة نفسها»): ?sim=code or ?station=code
const focusSim = ref(null)
function focusFromRoute () {
  const q = route.query
  if (q.sim || q.station) pageTab.value = 'sims'
  if (q.station) {
    const st = current.value.find((x) => x.code === q.station)
    if (st) { simStation.value = st.station_uuid; simTab.value = isAbsent(st) ? 'station_off' : 'ready' }
    return
  }
  if (!q.sim) return
  focusSim.value = String(q.sim)
  const r = everySim.value.find((x) => x.m.sim.code === q.sim)
  if (r) { simTab.value = simState(r); open(r.st, r.m); return }
  if (missingSims.value.some((x) => x.code === q.sim)) simTab.value = 'missing'
}
const shownSims = computed(() => simTab.value === 'station_off'
  ? [...simRows.value.station_off, ...(showOldSims.value ? simRows.value.old : [])]
  : simRows.value[simTab.value])
// The summary counts every active SIM of each type, whatever the filters (owner 2026-10-25); since 0130 only the ones
// «للكل» (owner 2026-11-01: the available SIMs), and the phones' SIMs on their own tile, never in a type's count.
const summary = computed(() => {
  const ready = everySim.value.filter((r) => !r.old && simState(r) === 'ready')
  const forAll = (r) => !audiences.value || audienceOf(r.m.sim) === 'all'
  return [
    { label: 'كمبيوتر', n: presentCount.value },
    ...SUMMARY_TYPES.map(([type, label]) => ({ type, label, n: ready.filter((r) => !isPhone(r.st) && forAll(r) && r.m.sim.sim_type === type).length })),
    ...(phones.value.length ? [{ label: '📱 هاتف', n: ready.filter((r) => isPhone(r.st)).length }] : [])
  ]
})

// Each SIM's audience (owner 2026-11-01, Flexy Core 0130): null before 0130 (no column, no line)
const AUDIENCES = [
  { value: 'all', label: 'للكل', color: 'positive' },
  { value: 'admin', label: 'للإدارة', color: 'primary' },
  { value: 'off', label: 'موقوفة', color: 'negative' }
]
const audiences = computed(() => tree.value?.sim_audiences || null)
const audienceOf = (sim) => audiences.value?.[sim?.sim_uuid]?.audience || 'all'
const audienceBusy = ref(null)
async function setAudience (sims, audience, tag = null) {
  audienceBusy.value = tag || sims[0]?.sim_uuid || 'x'
  try {
    const res = await flexy.ownerSimAudience(sims.map((x) => x.sim_uuid), audience)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error === 'MIGRATION_0130_PENDING' ? 'طبّق 0130 من «ينتظر تطبيقك» أولًا.' : (res.body?.error || 'FLEXY_CORE'))
    for (const x of sims) if (tree.value?.sim_audiences) tree.value.sim_audiences[x.sim_uuid] = { ...(tree.value.sim_audiences[x.sim_uuid] || {}), audience, set: true }
    const word = AUDIENCES.find((a) => a.value === audience)?.label
    Notify.create({ type: 'positive', message: sims.length === 1 ? `${simName(sims[0]) || 'الشريحة'}: ${word}` : `${sims.length} شرائح: ${word}`, position: 'top', timeout: 1500 })
  } catch (e) {
    Notify.create({ type: 'negative', message: e.message })
  } finally {
    audienceBusy.value = null
  }
}
function askAudienceAll (a) {
  const sims = shownSims.value.map((r) => r.m.sim)
  Dialog.create({ title: `الكل: ${a.label}`, message: `${sims.length} شريحة ظاهرة الآن تصبح «${a.label}».`, cancel: { label: 'إلغاء', flat: true }, ok: { label: 'نعم', color: a.color } })
    .onOk(() => setAudience(sims, a.value, 'all:' + a.value))
}
// «رقم USB» (owner 2026-11-01, Flexy Core 0138): the number written on the modem; Station Connect's own number when none
const labels = computed(() => tree.value?.modem_labels || {})
const usbOf = (m) => (m?.modem_uuid && labels.value[m.modem_uuid]) || m?.usb
const usbEdit = ref(null)
const usbBusy = ref(false)
async function saveUsb (m) {
  const v = usbEdit.value === '' || usbEdit.value === null ? null : Number(usbEdit.value)
  if (v !== null && (!Number.isInteger(v) || v < 1 || v > 999)) return Notify.create({ type: 'negative', message: 'رقم USB من 1 إلى 999' })
  usbBusy.value = true
  try {
    const res = await flexy.ownerModemLabel(m.modem_uuid, v)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error === 'MIGRATION_0138_PENDING' ? 'طبّق 0138 من «ينتظر تطبيقك» أولًا.' : (res.body?.error || 'FLEXY_CORE'))
    if (!tree.value.modem_labels) tree.value.modem_labels = {}
    if (v === null) delete tree.value.modem_labels[m.modem_uuid]
    else tree.value.modem_labels[m.modem_uuid] = v
    Notify.create({ type: 'positive', message: v === null ? 'حُذف رقم USB.' : 'رقم USB: ' + v, position: 'top', timeout: 1500 })
  } catch (e) {
    Notify.create({ type: 'negative', message: e.message })
  } finally {
    usbBusy.value = false
  }
}
// «الشريحة المفضّلة» (owner 2026-11-01, Flexy Core 0131): the program sends from it first, to empty it; null before 0131
const preferredMap = computed(() => tree.value?.sim_preferred || null)
const isPreferred = (sim) => !!preferredMap.value?.[sim?.sim_uuid]
const preferBusy = ref(null)
async function setPreferred (sim, on) {
  preferBusy.value = sim.sim_uuid
  try {
    const res = await flexy.ownerSimPreferred(sim.sim_uuid, on)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error === 'MIGRATION_0131_PENDING' ? 'طبّق 0131 من «ينتظر تطبيقك» أولًا.' : (res.body?.error || 'FLEXY_CORE'))
    if (tree.value?.sim_preferred) {
      if (on) tree.value.sim_preferred[sim.sim_uuid] = new Date().toISOString()
      else delete tree.value.sim_preferred[sim.sim_uuid]
    }
    Notify.create({ type: 'positive', message: on ? `${simName(sim) || 'الشريحة'}: مفضّلة، يرسل منها أولًا حتى تفرغ` : `${simName(sim) || 'الشريحة'}: لم تعد مفضّلة`, position: 'top', timeout: 1800 })
  } catch (e) {
    Notify.create({ type: 'negative', message: e.message })
  } finally {
    preferBusy.value = null
  }
}
// «الاستكشاف من الهاتف» / «التنفيذ من الهاتف» (0130): null before 0130
const phoneSwitches = computed(() => tree.value?.phone_switches || null)
const switching = ref(null)
async function setPhoneSwitch (which, on) {
  switching.value = which
  try {
    const res = await flexy.ownerPhoneSwitch(which, on)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error === 'MIGRATION_0130_PENDING' ? 'طبّق 0130 من «ينتظر تطبيقك» أولًا.' : (res.body?.error || 'FLEXY_CORE'))
    if (tree.value) tree.value.phone_switches = res.body.phone_switches
  } catch (e) {
    Notify.create({ type: 'negative', message: e.message })
  } finally {
    switching.value = null
  }
}
// «إصلاح الغائبة» (owner 2026-10-31): the computer is on but this SIM's modem is not seen: said as it is, never «يُقرأ»
const ABSENT_MS = 3 * 60_000
const modemGone = (r) => !isAbsent(r.st) && !isPhone(r.st) && !r.old && r.m.last_seen_at && Date.now() - Date.parse(r.m.last_seen_at) >= ABSENT_MS
const goneText = (r) => 'غائبة منذ ' + clock(r.m.last_seen_at) + ': المودم' + (r.m.model ? ' ' + r.m.model : '') + ' لا يظهر على ' + stName(r.st) + ' (أعد وصله بالـUSB)'
// The SIM's own problem first; «كمبيوترها مطفأ» beside it when that is also true
function statusText (r) {
  if (modemGone(r)) return goneText(r)
  if (onboardingText(r.m.sim)) return onboardingText(r.m.sim)
  if (r.old) return ''
  const own = r.m.reasons.find((x) => x.code !== 'STATION_ABSENT')?.text
  const off = r.m.reasons.find((x) => x.code === 'STATION_ABSENT')?.text || (isAbsent(r.st) ? 'كمبيوترها مطفأ' : '')
  if (simState(r) === 'station_off') return off
  return [own, off].filter(Boolean).join(' · ')
}
const statusClass = (r) => modemGone(r) ? 'text-negative' : onboardingText(r.m.sim) ? onboardingClass(r.m.sim) : simState(r) === 'station_off' ? 'muted' : r.m.level === 'down' || simState(r) === 'needs_action' ? 'text-negative' : 'text-deep-orange'
// Balance: one total the SIM can execute now, with how old the reading is. Old = past the
// core's refresh window (6 h), when a send would first ask for a fresh 632.
const BALANCE_FRESH_MS = 6 * 3600 * 1000
function balanceText (sim) {
  if (sim.balance == null) return 'الرصيد غير مقروء'
  const age = sim.balance_checked_at ? Date.now() - Date.parse(sim.balance_checked_at) : null
  const when = age == null ? '' : age < 3600 * 1000 ? ` · قبل ${Math.max(1, Math.round(age / 60000))} دقيقة` : age < 48 * 3600 * 1000 ? ` · قبل ${Math.round(age / 3600000)} ساعة` : ` · قبل ${Math.round(age / 86400000)} يوم`
  return money(sim.balance) + when
}
function balanceClass (sim) {
  if (sim.balance == null) return 'text-deep-orange'
  const age = sim.balance_checked_at ? Date.now() - Date.parse(sim.balance_checked_at) : Infinity
  return age > BALANCE_FRESH_MS ? 'text-deep-orange' : sim.balance <= 0 ? 'text-negative' : ''
}
const numberText = (sim) => sim.msisdn_source === 'ussd' ? 'الرقم من الشبكة' : sim.msisdn_source === 'manual' ? 'الرقم مكتوب يدويًا' : 'الرقم غير معروف'
function simSummary (st) {
  const ms = live(st)
  const connected = ms.filter(isConnected).length
  const off = ms.length - connected
  if (!ms.length) return 'لا موديمات'
  return `${connected} متصلة` + (off ? ` · ${off} غير متصلة` : '')
}

// Agent updates (owner 2026-10-25): one request per computer at a time
const UPDATE_STATUS = {
  pending: 'في الانتظار',
  claimed: 'جارٍ على الكمبيوتر',
  succeeded: 'تم',
  failed: 'فشل، لم يتغيّر شيء',
  rolled_back: 'رجع وحده إلى السابق',
  cancelled: 'أُلغي'
}
const GATEWAYS = { 'flexy-gateway': 'بوابة النواة', 'station-gateway': 'البوابة القديمة' }
const FUNCTIONS = 'https://wqyebqzbbpohbnznqdjj.supabase.co/functions/v1/'
const updates = ref(null)
// What each computer's updater last reported: the version and commit it runs, and main's
const mainOf = (st) => (updates.value?.main || []).find((m) => m.station_uuid === st.station_uuid) || null
// A newer version on main, or the same version at another commit (a fix merged without a bump)
// Only a newer version than the one running now (owner 2026-10-30: «زر لا عمل له يظهر»): the live heartbeat version wins
// over the updater's last report, and a commit that does not change the version is not an update to press
const newerThan = (a, b) => {
  const x = String(a || '0').split('.').map(Number)
  const y = String(b || '0').split('.').map(Number)
  for (let i = 0; i < 3; i++) if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0)
  return false
}
const newInMain = (st) => {
  const m = mainOf(st)
  if (!m || !m.main_version || m.main_error) return null
  return newerThan(m.main_version, st.agent_version || m.agent_version) ? m : null
}
const MAIN_ERRORS = {
  GIT_LOCAL_CHANGES: 'ملفات معدّلة يدويًا على الكمبيوتر',
  GIT_NOT_ON_MAIN: 'الكمبيوتر ليس على فرع main',
  GIT_NOT_AGENT_REPOSITORY: 'المجلد ليس نسخة من المستودع',
  GIT_REMOTE_VERSION_UNREADABLE: 'تعذّرت قراءة الإصدار من main'
}
// The updater sends «GIT_FETCH_FAILED:» + git's own first line: a computer that cannot reach GitHub
// at the moment is not a fault, it fetches again every minute by itself.
// GitHub refused the key (same words as the updater's GIT_AUTH_REFUSED): not «offline», the owner acts
const keyRefused = (e) => /GIT_FETCH_FAILED:.*(authentication failed|invalid username|could not read username|403|401|repository not found|terminal prompts disabled)/i.test(e || '')
const GITHUB_KEYS = 'https://github.com/settings/personal-access-tokens'
const offline = (e) => /GIT_FETCH_FAILED|unable to access|Failed to connect|Could not resolve/i.test(e || '')
const last = (st) => (updates.value?.stations || []).find((x) => x.station_uuid === st.station_uuid) || null
const active = (st) => { const u = last(st); return u && (u.status === 'pending' || u.status === 'claimed') ? u : null }
function updateLabel (u) {
  if (u.kind === 'release') return 'إصدار ' + u.release
  const url = u.config?.SERVER_URL || ''
  return 'نقل إلى ' + (GATEWAYS[url.slice(FUNCTIONS.length)] || 'عنوان آخر')
}
async function loadUpdates () {
  const res = await flexy.ownerUpdates()
  if (res.status === 200 && res.body?.ok) updates.value = res.body
}
async function send (fn) {
  busy.value = true
  try {
    const res = await fn()
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    await loadUpdates()
  } catch (e) {
    error.value = 'لم يُقبل الطلب (' + (e.message || 'FLEXY_CORE') + ').'
  } finally {
    busy.value = false
  }
}
const confirm = (title, message, fn) => Dialog.create({ title, message, cancel: 'لا', ok: 'نعم' }).onOk(() => send(fn))
function askRelease (st) {
  const m = newInMain(st)
  confirm('تحديث ' + (st.code || 'الكمبيوتر'), `يسحب الكمبيوتر main من GitHub (الإصدار ${m.main_version}) حين لا يكون عليه أي USSD. إن لم يتصل الـAgent الجديد خلال 3 دقائق يرجع وحده إلى السابق.`,
    () => flexy.requestUpdate(st.station_uuid, 'release', m.main_version))
}
function askGateway (st, gateway) {
  confirm('نقل ' + (st.code || 'الكمبيوتر'), `يكلّم الـAgent ${GATEWAYS[gateway]} بعد إعادة تشغيله. إن لم يتصل خلال 3 دقائق يرجع وحده إلى العنوان السابق.`,
    () => flexy.requestUpdate(st.station_uuid, 'config', { SERVER_URL: FUNCTIONS + gateway }))
}
const cancel = (u) => send(() => flexy.cancelUpdate(u.deployment_id))

// «تعديل» (owner 2026-10-30): pause, end and gateway shown on demand; alone on a computer gone longer than the alert
const editStations = ref(false)
const longGone = (st) => isAbsent(st) && st.last_seen_at && Date.now() - Date.parse(st.last_seen_at) >= (tree.value?.limits?.absentMinutes || 3) * 60_000
// «حدّث الكل»: the connected computers with a newer main, updated one after the other while this page stays open
const updatable = computed(() => current.value.filter((st) => !isPhone(st) && !isAbsent(st) && updates.value && !active(st) && newInMain(st)).map((st) => ({ st, ...newInMain(st) })))
const updatingAll = ref('')
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
function askUpdateAll () {
  const list = updatable.value
  Dialog.create({
    title: 'تحديث الكل',
    message: `${list.map((x) => x.st.code).join('، ')} إلى ${list[0].main_version}، كمبيوتر بعد كمبيوتر. كل واحد ينتظر حتى لا يبقى عليه USSD، ويرجع وحده إلى السابق إن لم يتصل خلال 3 دقائق. أبقِ الصفحة مفتوحة حتى ينتهي.`,
    cancel: 'لا', ok: 'حدّث'
  }).onOk(async () => {
    for (const [i, x] of list.entries()) {
      updatingAll.value = `يحدّث ${x.st.code} (${i + 1} من ${list.length})…`
      await send(() => flexy.requestUpdate(x.st.station_uuid, 'release', x.main_version))
      // Wait for this computer's update to end (at most 6 minutes) before the next one
      for (let t = 0; t < 72 && active(x.st); t++) { await pause(5000); await loadUpdates() }
    }
    updatingAll.value = ''
    load()
  })
}

// A phone app waiting to be linked as the admin phone (Flexy Core 0033)
const pendingPhones = ref([])
const unprotectedPhones = ref([])
async function loadPhones () {
  const res = await flexy.ownerPhone()
  pendingPhones.value = res.status === 200 ? (res.body.pending || []) : []
  unprotectedPhones.value = res.status === 200
    ? (res.body.phones || []).filter((p) => p.live && p.health && p.health.protected === false) : []
}
function approvePhone (p) {
  Dialog.create({
    title: 'اعتماد هاتف الإدارة',
    message: 'هذا هاتفك أنت؟ بعد الاعتماد ينفّذ العروض التي ترسلها له فقط.',
    cancel: 'لا', ok: 'نعم، اعتمد'
  }).onOk(async () => {
    busy.value = true
    try {
      const res = await flexy.approvePhone(p.station_uuid, 'هاتف الإدارة')
      if (res.status !== 200) throw new Error(res.body?.error || 'FLEXY_CORE')
      pendingPhones.value = res.body.pending || []
    } catch (e) {
      Dialog.create({ title: 'لم يُعتمد', message: e.message || 'FLEXY_CORE', ok: 'حسنًا' })
    } finally { busy.value = false }
    load()
  })
}

// «إيقاف مؤقت» / «تشغيل» / «إلغاء المحطة» (owner 2026-10-29): the last one asked twice, it is for good
function stationStatus (st, status) {
  const name = st.code || st.computer_name || 'هذا الكمبيوتر'
  const apply = async () => {
    busy.value = true
    try {
      const res = await flexy.ownerStationStatus(st.station_uuid, status)
      if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    } catch (e) {
      error.value = 'لم يُقبل (' + (e.message || 'FLEXY_CORE') + ').'
    } finally {
      busy.value = false
    }
    load()
  }
  if (status === 'approved') return apply()
  if (status === 'suspended') {
    return Dialog.create({ title: 'إيقاف مؤقت', message: `يتوقف ${name} عن الإرسال حتى تضغط «تشغيل». العمليات الجارية عليه تكمل.`, cancel: 'لا', ok: 'أوقف' }).onOk(apply)
  }
  Dialog.create({ title: 'إلغاء المحطة', message: `${name}: يرفضه الخادم نهائيًا (كمبيوتر مسروق أو مبيوع). لإرجاعه لاحقًا يجب ربطه من جديد. متأكد؟`, cancel: 'لا', ok: 'نعم' })
    .onOk(() => Dialog.create({ title: 'تأكيد أخير', message: `اكتب نعم للتأكيد: إلغاء ${name} نهائيًا.`, prompt: { model: '', type: 'text' }, cancel: 'تراجع', ok: 'ألغِ' })
      .onOk((v) => { if (String(v).trim() === 'نعم') apply() }))
}

// A new station computer (owner 2026-10-27): approved from here, through Flexy API
function approveComputer (st) {
  Dialog.create({
    title: 'اعتماد كمبيوتر جديد',
    message: `اعتماد ${st.computer_name || st.code || 'هذا الكمبيوتر'}؟ بعدها يستقبل الأوامر والعمليات مثل باقي الكمبيوترات.`,
    cancel: 'لا', ok: 'نعم، اعتمد'
  }).onOk(async () => {
    busy.value = true
    try {
      const res = await flexy.ownerApproveComputer(st.station_uuid)
      if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    } catch (e) {
      error.value = 'لم يُقبل الاعتماد (' + (e.message || 'FLEXY_CORE') + ').'
    } finally {
      busy.value = false
    }
    load()
  })
}

// «تصفير» (Flexy Core 0040)
const wipes = ref([])
const wipeBusy = ref(false)
async function loadWipes () {
  const res = await flexy.ownerSmsWipes()
  if (res.status === 200 && res.body?.ok) wipes.value = res.body.wipes || []
}
const wipeCount = computed(() => everySim.value.filter((r) => !r.old).length)
// Only the SIMs connected now (owner 2026-10-30: a SIM gone since days, waiting forever, is noise)
const connectedSims = computed(() => new Set(everySim.value.filter(isActive).map((r) => r.m.sim.sim_uuid)))
const wipeShown = computed(() => wipes.value.filter((w) => connectedSims.value.has(w.sim_uuid)))
const wipeErrors = computed(() => wipeShown.value.filter((w) => w.last_error && (!w.last_clean_at || w.last_error_at > w.last_clean_at)))
// «كل الشرائح» = every SIM seen in the last 7 days (Flexy Core 0040): say how many, by operator (owner 2026-10-27)
function wipeScope () {
  const rows = everySim.value.filter((r) => !r.old)
  const by = SUMMARY_TYPES.map(([type, label]) => [label, rows.filter((r) => r.m.sim.sim_type === type).length]).filter(([, n]) => n)
  const off = rows.filter((r) => isAbsent(r.st)).length
  return `${rows.length} شريحة (${by.map(([l, n]) => l + ' ' + n).join('، ')})` + (off ? `، منها ${off} كمبيوترها مطفأ فتُصفَّر حين يعود` : '')
}
function askWipe (sim) {
  const who = sim ? 'الشريحة ' + (sim.label || sim.code || '') : 'كل الشرائح: ' + wipeScope() + '،'
  Dialog.create({
    title: 'تصفير مخزن الرسائل',
    message: `تُحفظ كل رسائل ${who} في السيرفر ثم تُحذف من الشريحة. تأكد أنه لا عمليات ولا تعبئات معلّقة. متابعة؟`,
    cancel: 'لا', ok: 'نعم، صفّر'
  }).onOk(async () => {
    wipeBusy.value = true
    try {
      const res = await flexy.ownerSmsWipe(sim ? sim.sim_uuid : null)
      if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
      wipes.value = res.body.wipes || []
    } catch (e) {
      error.value = 'لم يُقبل التصفير (' + (e.message || 'FLEXY_CORE') + ').'
    } finally {
      wipeBusy.value = false
    }
  })
}

async function load () {
  loadPhones().catch(() => null)
  loadWipes().catch(() => null)
  loadSimAlerts().catch(() => null)
  if (busy.value) return
  busy.value = true
  try {
    const res = await flexy.ownerDevices()
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    tree.value = res.body
    await loadUpdates().catch(() => {})
    error.value = ''
    devicesDown.value = Number(res.body.summary?.down) || 0
  } catch (e) {
    error.value = 'تعذّرت القراءة من Flexy Core (' + (e.message || 'FLEXY_CORE') + '). تُعرض آخر حالة مقروءة.'
  } finally {
    busy.value = false
  }
}

// New SIM onboarding (Flexy Core, owner decision 2026-10-25): number → type → first balance → approved.
const ALERTS = {
  NUMBER_NOT_FOUND: 'لم يُكتشف الرقم بعد 3 محاولات',
  PIN_REJECTED: 'الشبكة رفضت الـPIN: أدخل PIN جديدًا',
  TYPE_NOT_CONFIRMED: 'رد الشبكة لا يطابق النوع: حدّد النوع بنفسك',
  BALANCE_NOT_CONFIRMED: 'لم يُؤكَّد أول رصيد: اضغط «اقرأ الرصيد» أو احفظ الـPIN من جديد',
  BALANCE_READ_FAILED: 'تعذّرت قراءة الرصيد: افحص الموديم ثم اضغط «اقرأ الرصيد»',
  LAST_632_UNCONFIRMED: 'آخر طلب رصيد (632) لم يتأكد: تحقق من الـPIN واحفظه من جديد قبل طلب آخر'
}
const onboardingOf = (sim) => (tree.value?.onboarding || []).find((o) => o.sim_uuid === sim.sim_uuid) || null
// A SIM not approved yet that stopped on its first balance: the button asks once more (flexy-core 0028).
// A PIN refused is not among them: a new PIN does that.
const RETRY_ALERTS = ['BALANCE_NOT_CONFIRMED', 'TYPE_NOT_CONFIRMED', 'LAST_632_UNCONFIRMED']
const isPhone = (st) => String(st?.agent_version || '').startsWith('phone-')
const canRetryFirstBalance = (sim) => {
  const o = sim && onboardingOf(sim)
  return !!o && o.stage === 'alert' && RETRY_ALERTS.includes(o.alert_code)
}
// Why a read stopped after 30 minutes without its code leaving (Flexy Core 0101)
const READ_WHY = { CODE_NOT_SENT: 'لم يُرسل الكود: المودم مشغول أو الطلب رُفض', MODEM_NOT_READY: 'المودم أو كمبيوتره لا يرد',
  SMS_STORE_FULL: 'مخزن الرسائل ممتلئ', MODEM_BUSY: 'المودم مشغول', LAST_632_UNCONFIRMED: 'قراءة سابقة لم تُحسم',
  LAST_QUERY_RECENT: 'قُرئ قبل قليل', NOTHING_CHANGED: 'لا عملية منذ آخر قراءة', RUNNING: 'قراءة جارية',
  SIM_NOT_READY: 'الشريحة غير جاهزة', PIN_REJECTED: 'PIN مرفوض' }
const since = (t) => { const m = Math.max(0, Math.round((Date.now() - Date.parse(t)) / 60000)); return m < 60 ? m + ' دقيقة' : m < 2880 ? Math.round(m / 60) + ' ساعة' : Math.round(m / 1440) + ' يوم' }
const stationOfSim = (uuid) => { const r = everySim.value.find((x) => x.m.sim.sim_uuid === uuid); return r ? stName(r.st) : '' }
function copySimForClaude (r) {
  const o = onboardingOf(r.m.sim) || {}
  copyForClaude('شريحة ' + (r.m.sim.code || ''), {
    sim: r.m.sim.code, type: r.m.sim.sim_type, station: stName(r.st), agent: r.st.agent_version, state: simState(r), level: r.m.level,
    status: statusText(r), stage: o.stage, alert: o.alert_code, detail: o.alert_detail, since: o.updated_at,
    balance: r.m.sim.balance, balance_at: r.m.sim.balance_checked_at, online: isConnected(r.m)
  })
}
const noteOf = (sim) => onboardingOf(sim)?.note || ''
function onboardingText (sim) {
  const o = onboardingOf(sim)
  if (!o?.stage) return ''
  if (o.stage === 'number') return `يُكتشف الرقم (محاولة ${o.number_tries || 1} من 3)`
  if (o.stage === 'pin_wait') return 'ينتظر PIN منك قبل سؤال الرصيد'
  if (o.stage === 'balance') return 'يُسأل أول رصيد'
  // The last known balance stays in sight while the new one is read (owner 2026-10-28)
  // How long it has been reading (owner 2026-10-30: «يدور ساعات»): it stops by itself after 30 minutes (Flexy Core 0101)
  if (o.stage === 'read') return 'يُقرأ الرصيد…' + (o.alert_detail ? ' (رفض الكمبيوتر: ' + (READ_WHY[o.alert_detail] || o.alert_detail) + '؛ يُعاد حتى 30 دقيقة ثم يُغلق «ليس الآن»، لا يُحسب على الشريحة)' : '') + (o.updated_at ? ' منذ ' + since(o.updated_at) : '') + (sim.balance != null ? ' · السابق ' + money(sim.balance) : '')
  if (o.stage === 'approved') return 'اعتُمدت آليًا بعد أول رصيد'
  if (o.stage === 'balance_only') return 'الرصيد ' + (o.probe_amount != null ? money(o.probe_amount) : 'مقروء') + ' (بلا اعتماد)'
  if (o.stage === 'alert') return '⚠️ ' + (ALERTS[o.alert_code] || o.alert_code) + (o.alert_detail ? ' (' + (READ_WHY[o.alert_detail] || o.alert_detail) + ')' : '') + (o.alert_code === 'BALANCE_READ_FAILED' ? ' — يُعاد وحده بعد ' + ((o.read_fails || 1) <= 3 ? '3' : '15') + ' دقائق (فشل ' + (o.read_fails || 1) + ' مرة)' : '')
  return ''
}
// A balance code is on its way: the page turns a spinner beside it
const isReading = (sim) => ['read', 'balance'].includes(onboardingOf(sim)?.stage)
const onboardingClass = (sim) => {
  const stage = onboardingOf(sim)?.stage
  return stage === 'alert' ? 'text-negative' : stage === 'approved' ? 'text-positive' : 'text-deep-orange'
}

const details = ref(false)
const picked = ref(null)
// «رقم USB»: the field shows the modem's saved number when its window opens
watch(() => picked.value?.m?.modem_uuid, (id) => { usbEdit.value = id ? (labels.value[id] ?? null) : null })
const form = ref({ label: '', note: '', pin: '', busy: false, error: '', saved: false })
const reading = ref({ busy: false, ok: false, text: '' })
function open (st, m) {
  picked.value = { st, m }
  form.value = { label: m.sim?.label || '', note: m.sim ? noteOf(m.sim) : '', pin: '', busy: false, error: '', saved: false }
  reading.value = { busy: false, ok: false, text: '' }
  details.value = true
}
async function saveSettings () {
  const sim = picked.value?.m.sim
  if (!sim || form.value.busy) return
  form.value.busy = true
  form.value.error = ''
  form.value.saved = false
  try {
    const fields = { label: form.value.label, note: form.value.note }
    if (form.value.pin) fields.pin = form.value.pin
    const res = await flexy.saveSimSettings(sim.sim_uuid, fields)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    form.value.pin = ''
    form.value.saved = true
    await load()
  } catch (e) {
    form.value.error = 'لم يُحفظ (' + (e.message || 'FLEXY_CORE') + ')'
  } finally {
    form.value.busy = false
  }
}

// One balance code for an approved SIM, at once if it is connected and its modem free.
const READ_ERRORS = {
  SIM_NOT_APPROVED: 'الشريحة غير معتمدة',
  PROBE_RUNNING: 'كود آخر يعمل على الموديم الآن',
  // The 632 guard (one at a time, never again with a PIN refused or unconfirmed)
  PIN_REJECTED: 'الشبكة رفضت الـPIN: أدخل الـPIN الصحيح واحفظه أولًا',
  LAST_632_UNCONFIRMED: 'آخر طلب رصيد لم يتأكد: تحقق من الـPIN واحفظه من جديد أولًا',
  RUNNING: 'طلب رصيد آخر يعمل الآن',
  LAST_QUERY_RECENT: 'قُرئ الرصيد قبل قليل',
  NOTHING_CHANGED: 'الرصيد لم يتغير منذ آخر قراءة',
  MODEM_BUSY: 'الموديم مشغول الآن',
  SIM_NOT_FOUND: 'الشريحة غير موجودة'
}
async function readBalance () {
  const sim = picked.value?.m.sim
  if (!sim || reading.value.busy) return
  reading.value = { busy: true, ok: false, text: '' }
  try {
    const res = await flexy.readSimBalance(sim.sim_uuid)
    if (res.status !== 200 || !res.body?.ok) throw new Error(res.body?.error || 'FLEXY_CORE')
    reading.value.ok = true
    reading.value.text = res.body.sent ? 'أُرسل كود الرصيد، والرد يظهر هنا خلال دقيقة' : 'سيُرسل كود الرصيد عند اتصال الشريحة'
    await load()
  } catch (e) {
    reading.value.text = 'لم يُرسل: ' + (READ_ERRORS[e.message] || e.message || 'FLEXY_CORE')
  } finally {
    reading.value.busy = false
  }
}

// Only while the page is open, and not in a hidden tab
const timer = setInterval(() => { if (document.visibilityState === 'visible') load() }, 30000)
onBeforeUnmount(() => clearInterval(timer))
onMounted(async () => { await load(); loadActions(); focusFromRoute() })
</script>

<style scoped>
.page-tabs { margin: 0 0 12px; border: 1px solid #E4E6EC; border-radius: 10px; overflow: hidden; }
.missing-row { padding: 8px; border-top: 1px solid #EEF0F5; }
.missing-row.focus { background: #FFF7ED; }
.missing-row.retired { opacity: .6; }
.station-row { width: 100%; border: 0; background: transparent; padding: 12px 14px; text-align: right; font: inherit; color: inherit; cursor: pointer; display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.station-row:disabled { cursor: default; opacity: 0.7; }
.station-open { border-bottom: 1px solid #EEF0F4; }
.station { padding: 12px 14px; display: flex; flex-direction: column; gap: 4px; }
.modem { width: 100%; border: 0; border-top: 1px solid #EEF0F4; background: transparent; padding: 10px 14px; text-align: right; font: inherit; color: inherit; cursor: pointer; display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.op-row { padding: 10px 14px; border-top: 1px solid #ECEEF3; display: flex; flex-direction: column; gap: 4px; }
.kv { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 6px 12px; }
.kv > * { min-width: 0; overflow-wrap: anywhere; }
.sim-dialog { width: 420px; max-width: calc(100vw - 24px); overflow-x: hidden; }
.sim-dialog :deep(.q-tabs) { max-width: 100%; }
.table-wrap { overflow-x: auto; }
.sims td { white-space: nowrap; }
.sims tbody tr.static { cursor: default; }
.sum { display: flex; gap: 6px; }
button.tile { border: 0; font: inherit; cursor: pointer; }
.tile { position: relative; }
.tile .funnel { position: absolute; top: 5px; left: 5px; color: #9AA0AC; }
.tile.picked { outline: 2px solid var(--q-primary); }
.tile.picked .funnel { color: var(--q-primary); }
.sub { margin: 8px; padding: 8px; background: #F4F6FA; border-radius: 8px; }
.chip { border: 1px solid #D5D9E0; }
.phone-row { padding: 8px 14px 12px; border-top: 1px solid #EEF0F4; }
.phone-sim { display: block; width: 100%; text-align: right; border: 1px solid #EEF0F4; border-radius: 8px; background: transparent; padding: 8px 10px; margin-top: 6px; font: inherit; color: inherit; cursor: pointer; }
.link { border: 0; background: transparent; padding: 0; font: inherit; color: var(--q-primary); cursor: pointer; }
.tile { flex: 1 1 0; min-width: 0; background: #F1F8F3; border-radius: 10px; padding: 8px 4px; text-align: center; color: #5B6170; }
.tile .n { font-size: 22px; font-weight: 700; color: #1E8E3E; }
.tile.zero { background: #FDECEA; color: #C62828; }
.tile.zero .n { color: #C62828; }
.sims { width: 100%; border-collapse: collapse; font-size: 14px; }
.sims th { text-align: right; font-weight: 600; color: #5B6170; padding: 8px 10px; border-bottom: 1px solid #E3E6EC; white-space: nowrap; }
.sims td { padding: 8px 10px; border-top: 1px solid #EEF0F4; vertical-align: top; }
.sims tbody tr { cursor: pointer; }
.sims tbody tr:hover { background: #F6F7F9; }
.warn-box { background: #FFF7ED; border: 1px solid #FDBA74; border-radius: 8px; padding: 8px; }
.place { overflow-wrap: anywhere; }
.fix-line { font-size: 12px; overflow-wrap: anywhere; }
.act-row { border-top: 1px solid #eef0f4; padding-top: 8px; }
/* On a phone (owner 2026-10-30: «الشاشة عريضة، التنقل فيها صعب»): each row a small card, nothing to scroll sideways */
@media (max-width: 640px) {
  .table-wrap { overflow-x: visible; }
  .sims thead { display: none; }
  .sims, .sims tbody { display: block; }
  .sims tr { display: flex; flex-wrap: wrap; align-items: flex-start; gap: 4px 14px; padding: 10px 6px; border-top: 1px solid #EEF0F4; }
  .sims td { display: block; border: 0; padding: 0; white-space: normal; min-width: 0; }
  .sims td:first-child, .sims td[colspan] { flex-basis: 100%; }
}
.sim-down { opacity: 0.55; }
.place { font-weight: 700; white-space: nowrap; }
.place .struck { text-decoration: line-through; color: #C62828; }
.pc-head td { background: #F3F5FA; padding: 8px 12px; }
.pc-icon { font-size: 26px; vertical-align: middle; }
.pc-no { font-size: 22px; font-weight: 800; margin-inline-start: 4px; vertical-align: middle; }
.pc-no.struck { text-decoration: line-through; color: #C62828; }
.dot { display: inline-block; width: 11px; height: 11px; border-radius: 50%; margin-inline-end: 6px; vertical-align: middle; }
.dot.on { background: #2FAE1E; box-shadow: 0 0 6px #2FAE1E; }
.dot.off { background: #D32F2F; }
.bal { font-size: 13px; padding: 4px 8px; }
.sim-set { background: #F7F8FB; border-radius: 10px; padding: 10px; }
</style>
