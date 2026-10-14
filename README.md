# نظام المحاسبة والتصنيع — مصنع منظفات

ERP بسيط (محاسبة + مخزون + تصنيع) حسب [`SPEC.md`](SPEC.md).
Next.js + Supabase (Postgres + Auth + RLS). الواجهة عربية RTL.

**الحالة:** المرحلة 1 (الأساس): الدخول والأدوار، الإعدادات، دليل الحسابات.

## التشغيل

المتطلبات: Node.js 22 ومشروع Supabase.

```bash
npm install
cp .env.example .env.local   # ثم ضع القيم
npm run dev                  # http://localhost:3000
```

في `.env.local`:

- `NEXT_PUBLIC_SUPABASE_URL`: رابط المشروع.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`: الـ publishable key (أو anon key القديم) من
  Project Settings ← API Keys.

> لا تضع `service_role` أو أي مفتاح سري في الواجهة أو في Git.

أوامر أخرى: `npm run build` و`npm run lint`.

## إعداد قاعدة البيانات (مرة واحدة)

1. **الترحيلات:** `supabase link --project-ref <ref>` ثم `supabase db push`
   (تطبّق ملفات `supabase/migrations/`).
2. **البيانات الأولية:** شغّل `supabase/seed.sql` مرة واحدة من SQL Editor
   (الإعدادات + دليل الحسابات + حسابات النظام). إعادة تشغيله آمنة.
   محليًا: `supabase db reset` يطبّق الترحيلات والـ seed معًا.
3. **منع التسجيل الذاتي:** من Authentication ← Sign In / Providers أوقف
   «Allow new users to sign up».

## أول مدير نظام (admin)

1. من Authentication ← Users ← Add user: أدخل البريد وكلمة المرور وفعّل «Auto Confirm User».
   المستخدم الجديد يأخذ دور «محاسب» تلقائيًا.
2. من SQL Editor:

   ```sql
   update public.profiles set role = 'admin' where email = 'you@example.com';
   ```

3. سجّل الدخول. باقي المستخدمين يُنشؤون بنفس الخطوة 1، والمدير يغيّر أدوارهم من
   الإعدادات ← المستخدمون.

## الاختبارات

اختبارات قاعدة البيانات (pgTAP) في `supabase/tests/`، وتعمل داخل transaction تُلغى في
النهاية فلا تترك بيانات.

- محليًا (يحتاج Docker): `supabase start` ثم `supabase test db`.
- عبر Supabase MCP: انظر `CLAUDE.md`.

## الملفات

- `supabase/migrations/`: الـ schema والدوال وRLS.
- `supabase/seed.sql`: البيانات الأولية.
- `DECISIONS.md`: القرارات التي اتُّخذت عند عدم وضوح المواصفات.
