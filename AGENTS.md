# card-store — قواعد ملزمة

اقرأ أولًا `amordz72/developer/AGENTS.md` و`amordz72/flexy-core/AGENTS.md`.

1. **card-store يكلّم Flexy API فقط** (`src/api/flexy.js`). لا يستدعي أبدًا دوال `station_connect_*` ولا جداول `flexy`، لا من المتصفح ولا بجلسة المدير.
   كل ما يمس مودمًا أو شريحة أو USSD أو رسائل: مسار مالك في `flexy-api` (`/v1/owner/...`).
2. **خطأ وقع (2026-10-26):** `src/components/ModemPanel.vue` (PR #62) يستدعي `station_connect_admin_*` مباشرة. مسجّل في `developer/NEXT-STEP.md`، ويُصلح بنقل الصفحة إلى مسارات flexy-api. لا تُضف استدعاءً مثله.
