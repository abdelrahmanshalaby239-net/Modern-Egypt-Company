-- =====================================================================
-- اختبارات المرحلة 1: الأساس (pgTAP)
-- تعمل داخل transaction تُلغى في النهاية، فلا تبقى بيانات تجريبية.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(31);

-- ---------------------------------------------------------------------
-- RLS والبيانات الأولية
-- ---------------------------------------------------------------------
select is(
  (select count(*) from pg_tables where schemaname = 'public' and not rowsecurity),
  0::bigint,
  'RLS مفعّل على كل جداول public'
);

select is((select count(*) from public.accounts), 36::bigint, 'دليل الحسابات: 36 حسابًا');

select results_eq(
  $$select code from public.accounts where not is_postable order by code$$,
  $$values ('1000'), ('2000'), ('3000'), ('4000'), ('5000'), ('6000')$$,
  'المجموعات الست فقط غير قابلة للترحيل'
);

select results_eq(
  $$select code from public.accounts where is_treasury order by code$$,
  $$values ('1101'), ('1102')$$,
  'الخزينة والبنك فقط حسابات خزينة'
);

select results_eq(
  $$select s.key, a.code
    from public.system_accounts s join public.accounts a on a.id = s.account_id
    order by s.key$$,
  $$values ('capital', '3101'), ('cogs', '5101'), ('inventory_adjustment', '5201'),
           ('inventory_finished', '1303'), ('inventory_packaging', '1302'),
           ('inventory_raw', '1301'), ('payables', '2101'), ('receivables', '1201'),
           ('retained_earnings', '3301'), ('sales_revenue', '4101')$$,
  'مفاتيح النظام العشرة مربوطة بالأكواد الصحيحة'
);

select results_eq(
  $$select currency_name, currency_symbol from public.settings$$,
  $$values ('جنيه مصري', 'ج.م')$$,
  'عملة واحدة: الجنيه المصري'
);

-- ---------------------------------------------------------------------
-- المستخدمون: الـ trigger ينشئ profile بدور accountant
-- ---------------------------------------------------------------------
insert into auth.users (id, email, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'accountant@test.local', 'authenticated', 'authenticated');

select is(
  (select role from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  'accountant',
  'المستخدم الجديد يأخذ دور accountant تلقائيًا'
);

update public.profiles set role = 'admin' where id = '11111111-1111-1111-1111-111111111111';

-- ---------------------------------------------------------------------
-- anon: لا يصل لشيء
-- ---------------------------------------------------------------------
set local role anon;

select throws_ok($$select * from public.accounts$$, '42501', null, 'anon لا يقرأ دليل الحسابات');
select throws_ok(
  $$insert into public.accounts (code, name, type) values ('9999', 'x', 'asset')$$,
  '42501', null, 'anon لا يضيف حسابات'
);
select throws_ok($$select * from public.settings$$, '42501', null, 'anon لا يقرأ الإعدادات');

reset role;

-- ---------------------------------------------------------------------
-- accountant
-- ---------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select is((select count(*) from public.accounts), 36::bigint, 'المحاسب يقرأ دليل الحسابات');

select lives_ok(
  $$insert into public.accounts (code, name, type, parent_id)
    select '6902', 'مصروف اختبار', 'expense', id from public.accounts where code = '6000'$$,
  'المحاسب يضيف حسابًا'
);

select is((select count(*) from public.profiles), 1::bigint, 'المحاسب يرى ملفه فقط');

update public.settings set company_name = 'تعديل غير مصرح' where id = 1;
select isnt(
  (select company_name from public.settings), 'تعديل غير مصرح',
  'المحاسب لا يعدّل الإعدادات'
);

update public.system_accounts
  set account_id = (select id from public.accounts where code = '1102')
  where key = 'receivables';
select is(
  (select a.code from public.system_accounts s join public.accounts a on a.id = s.account_id
   where s.key = 'receivables'),
  '1201',
  'المحاسب لا يغيّر ربط حسابات النظام'
);

update public.profiles set role = 'admin' where id = '22222222-2222-2222-2222-222222222222';
select is(
  (select role from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  'accountant',
  'المحاسب لا يرفع دوره'
);

select throws_ok(
  $$update public.profiles set email = 'x@test.local' where id = '22222222-2222-2222-2222-222222222222'$$,
  '42501', null, 'لا يُعدَّل من profiles إلا عمود الدور'
);

-- ---------------------------------------------------------------------
-- admin
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is(
  (select count(*) from public.profiles
   where id in ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')),
  2::bigint,
  'admin يرى كل المستخدمين'
);

update public.settings
  set company_name = 'شركة اختبار', company_address = 'العاشر من رمضان', company_phone = '0123456789'
  where id = 1;
select results_eq(
  $$select company_name, company_address, company_phone from public.settings$$,
  $$values ('شركة اختبار', 'العاشر من رمضان', '0123456789')$$,
  'admin يعدّل اسم الشركة وعنوانها وهاتفها'
);

select throws_ok(
  $$update public.settings set lock_date = '2026-12-31' where id = 1$$,
  '42501', null, 'تاريخ القفل لا يُعدَّل مباشرة (يحدّثه القفل الشهري وإقفال السنة فقط)'
);

select throws_ok(
  $$update public.settings set currency_name = 'دولار' where id = 1$$,
  '42501', null, 'العملة ثابتة ولا تُعدَّل من الواجهة'
);

update public.profiles set role = 'admin' where id = '22222222-2222-2222-2222-222222222222';
select is(
  (select role from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  'admin',
  'admin يغيّر دور مستخدم آخر'
);

select throws_ok(
  $$update public.profiles set role = 'accountant' where id = '11111111-1111-1111-1111-111111111111'$$,
  'P0001', 'لا يمكنك تغيير دورك بنفسك',
  'admin لا يغيّر دوره بنفسه'
);

-- ---------------------------------------------------------------------
-- قواعد دليل الحسابات (رسائل عربية)
-- ---------------------------------------------------------------------
select throws_ok(
  $$delete from public.accounts where code = '1201'$$,
  'P0001', 'لا يمكن حذف حساب نظام',
  'رفض حذف حساب نظام'
);

select throws_ok(
  $$update public.accounts set is_active = false where code = '1201'$$,
  'P0001', 'لا يمكن تعطيل حساب نظام',
  'رفض تعطيل حساب نظام'
);

select throws_ok(
  $$insert into public.accounts (code, name, type, parent_id)
    select '110201', 'فرعي', 'asset', id from public.accounts where code = '1102'$$,
  'P0001', 'الحساب الأب يجب أن يكون حسابًا تجميعيًا (غير قابل للترحيل)',
  'رفض إضافة حساب تحت حساب قابل للترحيل'
);

select throws_ok(
  $$insert into public.accounts (code, name, type, parent_id)
    select '6903', 'نوع مختلف', 'asset', id from public.accounts where code = '6000'$$,
  'P0001', 'نوع الحساب يجب أن يطابق نوع الحساب الأب',
  'رفض اختلاف نوع الحساب عن الأب'
);

select throws_ok(
  $$update public.system_accounts
    set account_id = (select id from public.accounts where code = '1000')
    where key = 'receivables'$$,
  'P0001', 'حساب النظام يجب أن يكون حسابًا فرعيًا نشطًا',
  'رفض ربط مفتاح نظام بحساب تجميعي'
);

select throws_ok(
  $$delete from public.accounts where code = '6000'$$,
  'P0001', 'لا يمكن حذف حساب له حسابات فرعية',
  'رفض حذف حساب له حسابات فرعية'
);

select throws_ok(
  $$insert into public.accounts (code, name, type) values ('12a', 'كود خطأ', 'asset')$$,
  'P0001', 'كود الحساب يجب أن يكون أرقامًا فقط',
  'رفض كود غير رقمي'
);

select lives_ok(
  $$delete from public.accounts where code = '6902'$$,
  'حذف حساب فرعي غير مستخدم مسموح'
);

reset role;

select * from finish();
rollback;
