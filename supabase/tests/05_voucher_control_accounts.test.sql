-- =====================================================================
-- تحقق المرحلة 3 (pgTAP): حسابات النظام محمية من السندات داخل قاعدة البيانات،
-- مع بقاء التحويل بين الخزائن ورد الدفعات للعملاء والموردين ومعاملات رأس المال.
-- تعمل داخل transaction تُلغى في النهاية. البيانات بتاريخ 1990.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(27);

-- ---------------------------------------------------------------------
-- تهيئة معزولة داخل الـ transaction
-- ---------------------------------------------------------------------
update public.settings set lock_date = null where id = 1;

insert into auth.users (id, email, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'accountant@test.local', 'authenticated', 'authenticated');
update public.profiles set role = 'admin' where id = '11111111-1111-1111-1111-111111111111';

create function pg_temp.acc(p_code text) returns bigint language sql stable as $$
  select id from public.accounts where code = p_code;
$$;

create function pg_temp.line(p_code text, p_debit text, p_credit text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'account_id', (select id from public.accounts where code = p_code),
    'debit', p_debit,
    'credit', p_credit
  );
$$;

-- سطور قيد سند بعينه (للتحقق من الأطراف والمبالغ)
create function pg_temp.voucher_lines(p_notes text)
returns table (code text, debit numeric, credit numeric, party text) language sql stable as $$
  select a.code, l.debit, l.credit, coalesce(c.name, s.name)
  from public.vouchers v
  join public.journal_lines l on l.entry_id = v.journal_entry_id
  join public.accounts a on a.id = l.account_id
  left join public.customers c on c.id = l.customer_id
  left join public.suppliers s on s.id = l.supplier_id
  where v.notes = p_notes
  order by l.id;
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
insert into public.customers (name) values ('ع رد اختبار');
insert into public.suppliers (name) values ('م رد اختبار');

-- ---------------------------------------------------------------------
-- 1) حسابات النظام لا تُختار «حسابًا آخر» في السند
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.post_voucher('receipt', '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('1201'), '10')$$,
  'P0001', 'الحساب 1201 - العملاء حساب أطراف: اختر العميل أو المورد بدلًا منه',
  'حساب العملاء لا يُستخدم كحساب آخر (الطرف إلزامي)'
);
select throws_ok(
  $$select public.post_voucher('payment', '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('2101'), '10')$$,
  'P0001', 'الحساب 2101 - الموردين حساب أطراف: اختر العميل أو المورد بدلًا منه',
  'حساب الموردين لا يُستخدم كحساب آخر (الطرف إلزامي)'
);
select throws_ok(
  $$select public.post_voucher('payment', '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('1301'), '10')$$,
  'P0001', 'لا يمكن استخدام حساب المخزون 1301 - مخزون مواد خام في السندات. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'مخزون الخام مرفوض في السندات'
);
select throws_ok(
  $$select public.post_voucher('payment', '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('1302'), '10')$$,
  'P0001', 'لا يمكن استخدام حساب المخزون 1302 - مخزون مواد تعبئة وتغليف في السندات. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'مخزون التعبئة مرفوض في السندات'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('1303'), '10')$$,
  'P0001', 'لا يمكن استخدام حساب المخزون 1303 - مخزون منتج تام في السندات. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'مخزون المنتج التام مرفوض في السندات'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('4101'), '10')$$,
  'P0001', 'لا يمكن استخدام الحساب 4101 - إيرادات المبيعات في السندات. يتحرك من مستنداته فقط (فواتير المبيعات أو تسوية الجرد)',
  'إيرادات المبيعات لا تُسجَّل بسند (فاتورة المبيعات فقط)'
);
select throws_ok(
  $$select public.post_voucher('payment', '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('5101'), '10')$$,
  'P0001', 'لا يمكن استخدام الحساب 5101 - تكلفة البضاعة المباعة في السندات. يتحرك من مستنداته فقط (فواتير المبيعات أو تسوية الجرد)',
  'تكلفة البضاعة المباعة لا تُسجَّل بسند'
);
select throws_ok(
  $$select public.post_voucher('payment', '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('5201'), '10')$$,
  'P0001', 'لا يمكن استخدام الحساب 5201 - فروقات جرد المخزون في السندات. يتحرك من مستنداته فقط (فواتير المبيعات أو تسوية الجرد)',
  'فروقات الجرد لا تُسجَّل بسند'
);

-- ---------------------------------------------------------------------
-- 2) حساب النظام لا يكون خزينة (يمنع إدخال المخزون أو العملاء من باب الخزينة)
-- ---------------------------------------------------------------------
select throws_ok(
  $$update public.accounts set is_treasury = true where code = '1301'$$,
  'P0001', 'حساب النظام لا يكون خزينة أو بنكًا',
  'لا يُعلَّم حساب المخزون كخزينة'
);
select throws_ok(
  $$update public.accounts set is_treasury = true where code = '1201'$$,
  'P0001', 'حساب النظام لا يكون خزينة أو بنكًا',
  'لا يُعلَّم حساب العملاء كخزينة'
);

reset role;

select throws_ok(
  $$update public.system_accounts set account_id = pg_temp.acc('1102') where key = 'inventory_raw'$$,
  'P0001', 'لا يُربط حساب نظام بحساب خزينة أو بنك',
  'لا يُربط مفتاح نظام بحساب خزينة'
);

-- ---------------------------------------------------------------------
-- 3) داخل قاعدة البيانات: سطور القيد حسب نوعه (حتى لو تجاوز أحد دالة السند)
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select throws_ok(
  $$select private.post_entry('1990-07-01', 'سند يمس المخزون', 'voucher', jsonb_build_array(
      pg_temp.line('1302', '10', '0'), pg_temp.line('1101', '0', '10')))$$,
  'P0001', 'لا يمكن الترحيل على حساب 1302 - مخزون مواد تعبئة وتغليف من قيد يدوي أو سند. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'trigger السطور يرفض المخزون في قيد سند'
);
select throws_ok(
  $$select private.post_entry('1990-07-01', 'سند يمس الإيرادات', 'voucher', jsonb_build_array(
      pg_temp.line('1101', '10', '0'), pg_temp.line('4101', '0', '10')))$$,
  'P0001', 'لا يمكن استخدام حساب 4101 - إيرادات المبيعات في السندات. يتحرك من مستنداته فقط (فواتير المبيعات أو تسوية الجرد)',
  'trigger السطور يرفض إيرادات المبيعات في قيد سند'
);
select throws_ok(
  $$select private.post_entry('1990-07-01', 'يدوي يمس المخزون', 'manual', jsonb_build_array(
      pg_temp.line('1303', '10', '0'), pg_temp.line('1101', '0', '10')))$$,
  'P0001', 'لا يمكن الترحيل على حساب 1303 - مخزون منتج تام من قيد يدوي أو سند. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'trigger السطور يرفض المخزون في قيد يدوي'
);
select throws_ok(
  $$select private.post_entry('1990-07-01', 'تسوية تمس العملاء', 'adjustment', jsonb_build_array(
      pg_temp.line('1201', '10', '0') || jsonb_build_object('customer_id', (select id from public.customers where name = 'ع رد اختبار')),
      pg_temp.line('4201', '0', '10')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 1201 - العملاء. حسابات العملاء والموردين تتحرك من السندات والأرصدة الافتتاحية للأطراف فقط',
  'trigger السطور يرفض العملاء في قيد تسوية حتى مع تحديد العميل'
);

-- ---------------------------------------------------------------------
-- 4) داخل قاعدة البيانات: صف السند نفسه (إدخال مباشر كمالك الجدول)
-- ---------------------------------------------------------------------
create temp table _e as
select private.post_entry('1990-07-01', 'قيد سند للاختبار', 'voucher', jsonb_build_array(
  pg_temp.line('6201', '10', '0'), pg_temp.line('1101', '0', '10'))) as id;

select throws_ok(
  $$insert into public.vouchers (kind, doc_no, doc_date, treasury_account_id, party_kind, account_id, amount, journal_entry_id)
    values ('payment', 999001, '1990-07-01', pg_temp.acc('1101'), 'account', pg_temp.acc('5101'), 10, (select id from _e))$$,
  'P0001', 'لا يمكن استخدام حساب نظام يتحرك من مستنداته كحساب آخر في السند',
  'trigger السند يرفض حساب مستندات كحساب آخر'
);
select throws_ok(
  $$insert into public.vouchers (kind, doc_no, doc_date, treasury_account_id, party_kind, account_id, amount, journal_entry_id)
    values ('payment', 999002, '1990-07-01', pg_temp.acc('6201'), 'account', pg_temp.acc('6301'), 10, (select id from _e))$$,
  'P0001', 'خزينة السند يجب أن تكون حساب خزينة أو بنك',
  'trigger السند يرفض خزينة ليست حساب خزينة'
);

-- ---------------------------------------------------------------------
-- 5) العمليات المشروعة ما زالت تعمل
-- ---------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select lives_ok(
  $$select public.post_voucher('payment', '1990-07-02', pg_temp.acc('1101'), 'account', pg_temp.acc('1102'), '2500', 'تحويل اختبار')$$,
  'تحويل من الخزينة إلى البنك بسند صرف'
);
select results_eq(
  $$select * from pg_temp.voucher_lines('تحويل اختبار')$$,
  $$values ('1102'::text, 2500.00::numeric, 0.00::numeric, null::text), ('1101', 0.00, 2500.00, null)$$,
  'قيد التحويل: م البنك / د الخزينة'
);
select lives_ok(
  $$select public.post_voucher('receipt', '1990-07-03', pg_temp.acc('1102'), 'account', pg_temp.acc('1101'), '700', 'إيداع اختبار')$$,
  'إيداع في البنك من الخزينة بسند قبض'
);
select lives_ok(
  $$select public.post_voucher('receipt', '1990-07-04', pg_temp.acc('1101'), 'account', pg_temp.acc('3101'), '10000', 'رأس مال اختبار')$$,
  'زيادة رأس المال نقدًا بسند قبض'
);
select lives_ok(
  $$select public.post_voucher('payment', '1990-07-05', pg_temp.acc('1101'), 'account', pg_temp.acc('3301'), '300', 'توزيع اختبار')$$,
  'صرف من الأرباح المرحّلة بسند صرف'
);
select lives_ok(
  $$select public.post_voucher('payment', '1990-07-06', pg_temp.acc('1101'), 'customer',
      (select id from public.customers where name = 'ع رد اختبار'), '150', 'رد للعميل اختبار')$$,
  'رد دفعة لعميل بسند صرف'
);
select results_eq(
  $$select * from pg_temp.voucher_lines('رد للعميل اختبار')$$,
  $$values ('1201'::text, 150.00::numeric, 0.00::numeric, 'ع رد اختبار'::text), ('1101', 0.00, 150.00, null)$$,
  'قيد رد العميل: م العملاء بالعميل / د الخزينة'
);
select lives_ok(
  $$select public.post_voucher('receipt', '1990-07-07', pg_temp.acc('1102'), 'supplier',
      (select id from public.suppliers where name = 'م رد اختبار'), '90', 'استرداد من المورد اختبار')$$,
  'استرداد من مورد بسند قبض'
);

reset role;

select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname in ('account_keys', 'validate_voucher')
     and (has_function_privilege('anon', p.oid, 'EXECUTE')
          or has_function_privilege('authenticated', p.oid, 'EXECUTE'))),
  0::bigint,
  'دوال الحماية الجديدة غير قابلة للتنفيذ من الـ API'
);

select lives_ok($$set constraints all immediate$$, 'كل القيود المعتمدة متوازنة عند الفحص المؤجَّل');

select * from finish();
rollback;
