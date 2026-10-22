# متجر البطاقات — card-store

متجر بطاقات مستقل: **هاتف · إنترنت · ألعاب**. الزبائن أصحاب محلات يشترون أكوادًا من رصيدهم.

- **الواجهة:** Vue 3 + Quasar (PWA، عربي RTL)، منشورة على GitHub Pages: `https://amordz72.github.io/card-store/`
- **النشر:** GitHub Pages **فقط** (سير `.github/workflows/deploy.yml` عند كل دمج في `main`). **Cloudflare Pages متوقف بقرار صاحب المشروع (2026-10-22)**: لا تُعتمد روابط `*.pages.dev` ولا يُعاد ربطه إلا بقرار جديد.
- **الخلفية:** Supabase (مشروع `amor-manager`، مخطط مستقل `store`). كل المنطق المالي في دوال قاعدة البيانات `public.store_*` ← `private.store_*_impl`.
- **القرارات والتوثيق:** مستودع `developer` ← `projects/card-store/`.

## الدخول
- **الزبون:** `#/login`، بالهاتف وكلمة السر. الجلسة رمز خاص بالمتجر، ومستقلة عن جلسة Supabase.
- **المدير:** `#/admin/login`، ببريد وكلمة سر Supabase Auth. يجب أن يكون الحساب في `store.admins`.

## التطوير
```bash
npm install
npm run dev      # http://localhost:9000/card-store/
npm run lint
npm run build    # dist/pwa
```

## قاعدة البيانات
- `supabase/migrations/`: مطبّقة على الإنتاج بنفس أرقام الإصدار.
- `supabase/tests/`: اختبارات محلية (Postgres 16):
  ```bash
  psql -d <testdb> -f supabase/tests/test_baseline.sql
  psql -d <testdb> -f supabase/migrations/20261021151125_card_store_v1.sql
  psql -d <testdb> -f supabase/migrations/20261021152159_card_store_v1_1_admin_announcement.sql
  psql -d <testdb> -f supabase/tests/test_store.sql
  ```

## الأمان
- المفتاح في `src/boot/supabase.js` هو المفتاح **العلني** (publishable)، ولا يجوز وضع `service_role` أو أي سر هنا.
- CSP في `index.html`، دون سكربتات من أطراف خارجية.
- قبل الإنتاج: راجع `developer/projects/card-store/PRODUCTION-CHECKLIST.md`، وفيها MFA للمدير وحذف بيانات DEMO.
