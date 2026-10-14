-- =====================================================================
-- اختبارات المرحلة 3: العملاء والموردون والخزينة (pgTAP)
-- الصلاحيات، القاعدة 9، السندات والإلغاء، الأرصدة الافتتاحية للأطراف وتعايشها
-- مع أرصدة الحسابات، ومطابقة أرصدة الأطراف والخزينة مع الأستاذ العام.
-- تعمل داخل transaction تُلغى في النهاية. البيانات بتاريخ 1990 وأسماء تنتهي بـ «اختبار».
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(87);

-- ---------------------------------------------------------------------
-- تهيئة معزولة داخل الـ transaction
-- ---------------------------------------------------------------------
update public.settings set lock_date = null where id = 1;

insert into auth.users (id, email, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'accountant@test.local', 'authenticated', 'authenticated');
update public.profiles set role = 'admin' where id = '11111111-1111-1111-1111-111111111111';

-- لو في مشروع التطوير قيود افتتاحية فعلية (أي جزء)، تُلغى داخل الاختبار فقط
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select public.cancel_journal_entry(o.id)
from public.journal_entries o
where o.source_type = 'opening'
  and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id);

create temp table _base as
select (select last_no from public.doc_counters where kind = 'receipt_voucher') as receipt_no,
       (select last_no from public.doc_counters where kind = 'payment_voucher') as payment_no,
       (select coalesce(max(id), 0) from public.vouchers) as voucher_id;
grant select on _base to public;

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

create function pg_temp.cust(p_name text) returns bigint language sql stable as $$
  select id from public.customers where name = p_name;
$$;

create function pg_temp.supp(p_name text) returns bigint language sql stable as $$
  select id from public.suppliers where name = p_name;
$$;

-- سطر رصيد افتتاحي لعميل أو مورد
create function pg_temp.pc(p_name text, p_debit text, p_credit text) returns jsonb language sql stable as $$
  select jsonb_build_object('customer_id', pg_temp.cust(p_name), 'debit', p_debit, 'credit', p_credit);
$$;

create function pg_temp.ps(p_name text, p_debit text, p_credit text) returns jsonb language sql stable as $$
  select jsonb_build_object('supplier_id', pg_temp.supp(p_name), 'debit', p_debit, 'credit', p_credit);
$$;

-- السند رقم n (نسبةً لبداية الاختبار) من نوع معيّن
create function pg_temp.v(p_kind text, p_n int) returns bigint language sql stable as $$
  select id from public.vouchers
  where kind = p_kind
    and doc_no = p_n + (select case p_kind when 'receipt' then receipt_no else payment_no end from pg_temp._base);
$$;

-- إدخال مباشر (كمالك الجدول) لرأس قيد وسطر واحد في أمر واحد، لاختبار trigger القاعدة 9.
-- الرأس من نوع سند لأن حسابي العملاء والموردين مسموحان فيه (القيد اليدوي يرفضهما قبل فحص الطرف).
create function pg_temp.direct_line(p_code text, p_customer bigint, p_supplier bigint) returns void language sql as $$
  with e as (
    insert into public.journal_entries (entry_no, entry_date, description, source_type, created_by)
    values (-100, '1990-08-01', 'إدخال مباشر', 'voucher', '22222222-2222-2222-2222-222222222222')
    returning id
  )
  insert into public.journal_lines (entry_id, account_id, debit, customer_id, supplier_id)
  select e.id, (select id from public.accounts where code = p_code), 10, p_customer, p_supplier from e;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات: anon
-- ---------------------------------------------------------------------
set local role anon;

select throws_ok($$select * from public.customers$$, '42501', null, 'anon لا يقرأ العملاء');
select throws_ok($$select * from public.vouchers$$, '42501', null, 'anon لا يقرأ السندات');
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-01', 1, 'account', 2, '10', null)$$,
  '42501', null, 'anon لا يعتمد سندات'
);
select throws_ok(
  $$select * from public.party_statement('customer', 1, null, null)$$,
  '42501', null, 'anon لا يقرأ كشف حساب طرف'
);

reset role;

-- ---------------------------------------------------------------------
-- المحاسب يدير العملاء والموردين (أعمدة محددة فقط)
-- ---------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select lives_ok(
  $$insert into public.customers (name, phone, address)
    values ('ع1 اختبار', '0100', 'القاهرة'), ('ع2 اختبار', null, null),
           ('ع4 بلا قيود اختبار', null, null)$$,
  'المحاسب يضيف عملاء'
);
select lives_ok(
  $$insert into public.suppliers (name, phone) values ('م1 اختبار', '0120'), ('م2 اختبار', null)$$,
  'المحاسب يضيف موردين'
);
select lives_ok(
  $$insert into public.customers (name, is_active) values ('ع3 معطل اختبار', false)$$,
  'المحاسب يضيف عميلًا معطّلًا'
);

select throws_ok(
  $$insert into public.customers (id, name) overriding system value values (999999, 'معرّف صريح اختبار')$$,
  '42501', null, 'المستخدم لا يحدد معرّف العميل بنفسه'
);
select throws_ok(
  $$insert into public.customers (name) values ('ع1 اختبار')$$,
  '23505', null, 'اسم العميل لا يتكرر (حتى لا ينقسم رصيده على سجلين)'
);

update public.customers set phone = '0111' where name = 'ع2 اختبار';
select is(
  (select phone from public.customers where name = 'ع2 اختبار'), '0111',
  'المحاسب يعدّل بيانات العميل'
);

select throws_ok(
  $$insert into public.vouchers (kind, doc_no, doc_date, treasury_account_id, party_kind, account_id, amount, journal_entry_id)
    values ('receipt', 1, '1990-05-01', 1, 'account', 2, 10, 1)$$,
  '42501', null, 'المستخدم لا يكتب في vouchers مباشرة'
);
select throws_ok(
  $$update public.vouchers set amount = 1 where id = 1$$,
  '42501', null, 'المستخدم لا يعدّل vouchers'
);

-- مستخدم مسجَّل بلا ملف (غير مصرح) لا يعتمد سندًا
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-01', pg_temp.acc('1101'), 'account', pg_temp.acc('4201'), '10')$$,
  '42501', null, 'مستخدم بلا ملف لا يعتمد سندًا'
);
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

reset role;

-- ---------------------------------------------------------------------
-- القاعدة 9 داخل قاعدة البيانات (إدخال مباشر كمالك الجدول)
-- ---------------------------------------------------------------------
select throws_ok(
  $$select pg_temp.direct_line('1201', null, null)$$,
  'P0001', 'الترحيل على حساب 1201 - العملاء يتطلب تحديد العميل',
  'سطر العملاء بلا عميل مرفوض'
);
select throws_ok(
  $$select pg_temp.direct_line('1201', pg_temp.cust('ع1 اختبار'), pg_temp.supp('م1 اختبار'))$$,
  'P0001', 'لا يُسمح بتحديد مورد على حساب 1201 - العملاء',
  'سطر العملاء لا يحمل موردًا'
);
select throws_ok(
  $$select pg_temp.direct_line('2101', pg_temp.cust('ع1 اختبار'), null)$$,
  'P0001', 'الترحيل على حساب 2101 - الموردين يتطلب تحديد المورد',
  'سطر الموردين بلا مورد مرفوض'
);
select throws_ok(
  $$select pg_temp.direct_line('2101', pg_temp.cust('ع1 اختبار'), pg_temp.supp('م1 اختبار'))$$,
  'P0001', 'لا يُسمح بتحديد عميل على حساب 2101 - الموردين',
  'سطر الموردين لا يحمل عميلًا'
);
select throws_ok(
  $$select pg_temp.direct_line('6201', pg_temp.cust('ع1 اختبار'), null)$$,
  'P0001', 'لا يُسمح بتحديد عميل أو مورد على حساب 6201 - كهرباء ومياه وغاز',
  'لا طرف على حساب غير العملاء والموردين'
);

-- ---------------------------------------------------------------------
-- الأرصدة الافتتاحية: جزء الحسابات ثم جزء العملاء والموردين
-- ---------------------------------------------------------------------
set local role authenticated;

select lives_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1101', '100000', '0'),
      pg_temp.line('1501', '50000', '0'),
      pg_temp.line('3101', '0', '150000')))$$,
  'أرصدة الحسابات الافتتاحية (SPEC §11 الخطوة 1)'
);

select throws_ok(
  $$select public.post_party_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.pc('ع1 اختبار', '2700', ''), pg_temp.ps('م1 اختبار', '', '10500')))$$,
  'P0001', 'الأرصدة غير متوازنة: المدين 2,700.00 والدائن 10,500.00 والفرق 7,800.00. أكّد تسجيل الفرق على حساب رأس المال',
  'أرصدة الأطراف غير المتوازنة تُرفض بدون تأكيد مع عرض الفرق'
);
select throws_ok(
  $$select public.post_party_opening_balances('1990-01-01', jsonb_build_array(
      jsonb_build_object('customer_id', pg_temp.cust('ع1 اختبار'), 'supplier_id', pg_temp.supp('م1 اختبار'), 'debit', '5')), true)$$,
  'P0001', 'السطر 1: حدد عميلًا أو موردًا (واحدًا فقط)',
  'سطر بعميل ومورد معًا مرفوض'
);
select throws_ok(
  $$select public.post_party_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.pc('ع1 اختبار', '5', ''), jsonb_build_object('debit', '5')), true)$$,
  'P0001', 'السطر 2: حدد عميلًا أو موردًا (واحدًا فقط)',
  'سطر بلا طرف مرفوض'
);
select throws_ok(
  $$select public.post_party_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.pc('ع3 معطل اختبار', '5', '')), true)$$,
  'P0001', 'السطر 1: العميل غير موجود أو معطّل',
  'عميل معطّل مرفوض في الأرصدة الافتتاحية'
);
select throws_ok(
  $$select public.post_party_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.pc('ع1 اختبار', '5', ''), pg_temp.pc('ع1 اختبار', '7', '')), true)$$,
  'P0001', 'السطر 2: العميل "ع1 اختبار" مكرر',
  'العميل لا يتكرر في الأرصدة الافتتاحية'
);
select throws_ok(
  $$select public.post_party_opening_balances('1990-01-01', '[]'::jsonb, true)$$,
  'P0001', 'أدخل رصيدًا واحدًا على الأقل',
  'أرصدة أطراف بلا سطور مرفوضة'
);

select lives_ok(
  $$select public.post_party_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.pc('ع1 اختبار', '2700', ''), pg_temp.ps('م1 اختبار', '', '10500')), true)$$,
  'بعد التأكيد تُسجَّل أرصدة الأطراف والفرق على رأس المال'
);

select results_eq(
  $$select a.code, c.name, s.name, l.debit, l.credit, l.description
    from public.journal_lines l
    join public.accounts a on a.id = l.account_id
    left join public.customers c on c.id = l.customer_id
    left join public.suppliers s on s.id = l.supplier_id
    where l.entry_id = (select max(id) from public.journal_entries where source_type = 'opening')
    order by l.id$$,
  $$values ('1201'::text, 'ع1 اختبار'::text, null::text, 2700.00::numeric, 0.00::numeric, 'ع1 اختبار'::text),
           ('2101', null, 'م1 اختبار', 0.00, 10500.00, 'م1 اختبار'),
           ('3101', null, null, 7800.00, 0.00, 'فرق الأرصدة الافتتاحية')$$,
  'قيد أرصدة الأطراف: العملاء والموردين بالطرف، والفرق على رأس المال'
);

select results_eq(
  $$select part from public.active_openings()$$,
  $$values ('accounts'::text), ('parties')$$,
  'جزءان افتتاحيان نشطان معًا: الحسابات والأطراف'
);

select throws_ok(
  $$select public.post_party_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.pc('ع2 اختبار', '10', '')), true)$$,
  'P0001', 'أرصدة العملاء والموردين الافتتاحية مسجّلة بالفعل. للتصحيح ألغِ قيدها ثم سجّلها من جديد',
  'أرصدة الأطراف مرة واحدة فقط'
);
select throws_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1102', '10', '0'), pg_temp.line('3101', '0', '10')))$$,
  'P0001', 'الأرصدة الافتتاحية مسجّلة بالفعل. للتصحيح ألغِ القيد الافتتاحي ثم سجّلها من جديد',
  'أرصدة الحسابات ما زالت مرة واحدة بعد تسجيل أرصدة الأطراف'
);

-- إلغاء جزء الحسابات وإعادته بينما جزء الأطراف نشط
select lives_ok(
  $$select public.cancel_journal_entry(
      (select entry_id from public.active_openings() where part = 'accounts'))$$,
  'إلغاء أرصدة الحسابات لا يمس أرصدة الأطراف'
);
select lives_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1101', '100000', '0'),
      pg_temp.line('1501', '50000', '0'),
      pg_temp.line('3101', '0', '150000')))$$,
  'إعادة أرصدة الحسابات وأرصدة الأطراف نشطة'
);

-- إلغاء جزء الأطراف: القيد العكسي يحمل نفس الأطراف، ثم إعادة التسجيل
select lives_ok(
  $$select public.cancel_journal_entry(
      (select entry_id from public.active_openings() where part = 'parties'))$$,
  'إلغاء أرصدة الأطراف بقيد عكسي'
);
select results_eq(
  $$select a.code, c.name, s.name, l.debit, l.credit
    from public.journal_entries r
    join public.journal_lines l on l.entry_id = r.id
    join public.accounts a on a.id = l.account_id
    left join public.customers c on c.id = l.customer_id
    left join public.suppliers s on s.id = l.supplier_id
    where r.id = (select max(id) from public.journal_entries where source_type = 'reversal')
    order by l.id$$,
  $$values ('1201'::text, 'ع1 اختبار'::text, null::text, 0.00::numeric, 2700.00::numeric),
           ('2101', null, 'م1 اختبار', 10500.00, 0.00),
           ('3101', null, null, 0.00, 7800.00)$$,
  'القيد العكسي لأرصدة الأطراف معكوس بنفس العميل والمورد'
);
select results_eq(
  $$select part from public.active_openings()$$,
  $$values ('accounts'::text)$$,
  'بعد الإلغاء يبقى جزء الحسابات وحده نشطًا'
);
select lives_ok(
  $$select public.post_party_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.pc('ع1 اختبار', '2700', ''), pg_temp.ps('م1 اختبار', '', '10500')), true)$$,
  'إعادة تسجيل أرصدة الأطراف بعد إلغائها'
);
select results_eq(
  $$select b.balance from public.party_balances('customer') b where b.party_id = pg_temp.cust('ع1 اختبار')
    union all
    select b.balance from public.party_balances('supplier') b where b.party_id = pg_temp.supp('م1 اختبار')$$,
  $$values ('2700.00'::text), ('-10500.00')$$,
  'بعد الإلغاء وإعادة التسجيل يُحسب رصيد الطرف مرة واحدة'
);

-- ---------------------------------------------------------------------
-- السندات: الحالات الست
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_voucher('payment', '1990-05-05', pg_temp.acc('1101'), 'supplier',
      pg_temp.supp('م1 اختبار'), '5000', null)$$,
  'سند صرف للمورد م1 من الخزينة 5,000 (SPEC §11 الخطوة 3)'
);
select lives_ok(
  $$select public.post_voucher('receipt', '1990-05-10', pg_temp.acc('1101'), 'customer',
      pg_temp.cust('ع1 اختبار'), '1000', 'دفعة')$$,
  'سند قبض من العميل ع1 نقدًا 1,000 (SPEC §11 الخطوة 6)'
);
select lives_ok(
  $$select public.post_voucher('payment', '1990-05-15', pg_temp.acc('1101'), 'account',
      pg_temp.acc('6201'), '200', null)$$,
  'سند صرف مصروف كهرباء 200 من الخزينة (SPEC §11 الخطوة 7)'
);
select lives_ok(
  $$select public.post_voucher('receipt', '1990-05-20', pg_temp.acc('1102'), 'supplier',
      pg_temp.supp('م2 اختبار'), '100', null)$$,
  'سند قبض من مورد إلى البنك'
);
select lives_ok(
  $$select public.post_voucher('payment', '1990-05-21', pg_temp.acc('1102'), 'customer',
      pg_temp.cust('ع2 اختبار'), '50', null)$$,
  'سند صرف لعميل من البنك'
);
select lives_ok(
  $$select public.post_voucher('receipt', '1990-05-22', pg_temp.acc('1102'), 'account',
      pg_temp.acc('4201'), '300', null)$$,
  'سند قبض من حساب إيرادات أخرى إلى البنك'
);

select results_eq(
  $$select v.kind, v.doc_no - case v.kind when 'receipt' then b.receipt_no else b.payment_no end
    from public.vouchers v cross join pg_temp._base b
    where v.id > b.voucher_id
    order by v.kind, v.doc_no$$,
  $$values ('payment'::text, 1::bigint), ('payment', 2), ('payment', 3),
           ('receipt', 1), ('receipt', 2), ('receipt', 3)$$,
  'ترقيم مستقل ومتتالٍ لسندات القبض والصرف'
);

select results_eq(
  $$select v.kind, v.doc_no - case v.kind when 'receipt' then b.receipt_no else b.payment_no end,
           a.code, l.debit, l.credit, c.name, s.name
    from public.vouchers v cross join pg_temp._base b
    join public.journal_lines l on l.entry_id = v.journal_entry_id
    join public.accounts a on a.id = l.account_id
    left join public.customers c on c.id = l.customer_id
    left join public.suppliers s on s.id = l.supplier_id
    where v.id > b.voucher_id
    order by v.kind, v.doc_no, l.id$$,
  $$values ('payment'::text, 1::bigint, '2101'::text, 5000.00::numeric, 0.00::numeric, null::text, 'م1 اختبار'::text),
           ('payment', 1, '1101', 0.00, 5000.00, null, null),
           ('payment', 2, '6201', 200.00, 0.00, null, null),
           ('payment', 2, '1101', 0.00, 200.00, null, null),
           ('payment', 3, '1201', 50.00, 0.00, 'ع2 اختبار', null),
           ('payment', 3, '1102', 0.00, 50.00, null, null),
           ('receipt', 1, '1101', 1000.00, 0.00, null, null),
           ('receipt', 1, '1201', 0.00, 1000.00, 'ع1 اختبار', null),
           ('receipt', 2, '1102', 100.00, 0.00, null, null),
           ('receipt', 2, '2101', 0.00, 100.00, null, 'م2 اختبار'),
           ('receipt', 3, '1102', 300.00, 0.00, null, null),
           ('receipt', 3, '4201', 0.00, 300.00, null, null)$$,
  'قيود السندات الست: الطرف المدين والدائن صحيح والطرف على سطر العملاء/الموردين'
);

select results_eq(
  $$select e.source_type, e.source_id = v.id, e.entry_date = v.doc_date,
           e.description = 'سند قبض رقم ' || v.doc_no || ' - العميل ع1 اختبار - دفعة', v.amount
    from public.vouchers v
    join public.journal_entries e on e.id = v.journal_entry_id
    where v.id = pg_temp.v('receipt', 1)$$,
  $$values ('voucher'::text, true, true, true, 1000.00::numeric)$$,
  'السند مربوط بقيده في الاتجاهين وبنفس التاريخ والبيان'
);

-- ---------------------------------------------------------------------
-- رفض السندات برسائل عربية
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-25', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع1 اختبار'), '0')$$,
  'P0001', 'المبلغ مطلوب ويجب أن يكون أكبر من صفر', 'رفض سند بمبلغ صفر'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-25', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع1 اختبار'), '-5')$$,
  'P0001', 'المبلغ يجب أن يكون رقمًا موجبًا', 'رفض سند بمبلغ سالب'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-25', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع1 اختبار'), '10.005')$$,
  'P0001', 'المبلغ لا يزيد عن خانتين عشريتين', 'رفض أكثر من خانتين عشريتين'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-25', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع1 اختبار'), 'abc')$$,
  'P0001', 'المبلغ "abc" غير صالح', 'رفض مبلغ غير رقمي'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-25', pg_temp.acc('6201'), 'customer', pg_temp.cust('ع1 اختبار'), '10')$$,
  'P0001', 'اختر خزينة أو بنكًا', 'الخزينة يجب أن تكون حساب خزينة أو بنك'
);
select throws_ok(
  $$select public.post_voucher('payment', '1990-05-25', pg_temp.acc('1101'), 'account', pg_temp.acc('1101'), '10')$$,
  'P0001', 'اختر حسابًا غير الخزينة أو البنك المختار', 'رفض نفس الحساب في طرفي السند'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-25', pg_temp.acc('1101'), 'account', pg_temp.acc('1201'), '10')$$,
  'P0001', 'الحساب 1201 - العملاء حساب أطراف: اختر العميل أو المورد بدلًا منه',
  'حساب العملاء لا يُختار كحساب آخر'
);
select throws_ok(
  $$select public.post_voucher('payment', '1990-05-25', pg_temp.acc('1101'), 'account', pg_temp.acc('1301'), '10')$$,
  'P0001', 'لا يمكن استخدام حساب المخزون 1301 - مخزون مواد خام في السندات. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'حساب المخزون مرفوض في السندات'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-25', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع3 معطل اختبار'), '10')$$,
  'P0001', 'اختر عميلًا نشطًا', 'عميل معطّل مرفوض في السندات'
);
select throws_ok(
  $$select public.post_voucher('receipt', '1990-05-25', pg_temp.acc('1101'), 'partner', 1, '10')$$,
  'P0001', 'اختر نوع الطرف: عميل أو مورد أو حساب', 'نوع طرف غير صالح'
);
select throws_ok(
  $$select public.post_voucher('transfer', '1990-05-25', pg_temp.acc('1101'), 'account', pg_temp.acc('4201'), '10')$$,
  'P0001', 'نوع السند غير صالح', 'نوع سند غير صالح'
);
select throws_ok(
  $$select public.post_journal_entry('1990-05-25', 'طرف على قيد يدوي', 'manual', jsonb_build_array(
      pg_temp.line('6201', '10', '0') || jsonb_build_object('customer_id', pg_temp.cust('ع1 اختبار')),
      pg_temp.line('1101', '0', '10')))$$,
  'P0001', 'لا يُسمح بتحديد عميل أو مورد على حساب 6201 - كهرباء ومياه وغاز',
  'القيد اليدوي لا يمرر طرفًا على حساب آخر'
);

-- قفل الفترة: السند والإلغاء
reset role;
update public.settings set lock_date = '1990-06-30' where id = 1;
set local role authenticated;

select throws_ok(
  $$select public.post_voucher('receipt', '1990-06-15', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع1 اختبار'), '10')$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 15/06/1990 لأن الفترة مقفولة حتى 30/06/1990',
  'رفض سند بتاريخ داخل فترة مقفولة'
);
select throws_ok(
  $$select public.cancel_voucher(pg_temp.v('receipt', 1))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 10/05/1990 لأن الفترة مقفولة حتى 30/06/1990',
  'رفض إلغاء سند تاريخه داخل فترة مقفولة'
);

reset role;
update public.settings set lock_date = null where id = 1;

select results_eq(
  $$select (select last_no from public.doc_counters where kind = 'receipt_voucher') - receipt_no,
           (select last_no from public.doc_counters where kind = 'payment_voucher') - payment_no,
           (select count(*) from public.vouchers where id > voucher_id)
    from pg_temp._base$$,
  $$values (3::bigint, 3::bigint, 6::bigint)$$,
  'السندات المرفوضة لم تستهلك أرقامًا ولم تترك سندات'
);

-- ---------------------------------------------------------------------
-- السند المعتمد لا يُعدَّل ولا يُحذف حتى من مالك الجدول
-- ---------------------------------------------------------------------
select throws_ok(
  $$update public.vouchers set notes = 'تعديل' where id = pg_temp.v('receipt', 1)$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'لا تعديل لسند معتمد'
);
select throws_ok(
  $$delete from public.vouchers where id = pg_temp.v('receipt', 1)$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'لا حذف لسند معتمد'
);
select throws_ok(
  $$truncate public.vouchers$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'لا تفريغ لجدول السندات'
);

-- حذف الأطراف: مسموح بلا قيود، ومرفوض لو عليه قيود
set local role authenticated;

select throws_ok(
  $$delete from public.customers where name = 'ع1 اختبار'$$,
  '23503', null, 'لا يُحذف عميل عليه قيود (التعطيل بدل الحذف)'
);
select lives_ok(
  $$delete from public.customers where name = 'ع4 بلا قيود اختبار'$$,
  'حذف عميل بلا قيود مسموح'
);

-- ---------------------------------------------------------------------
-- إلغاء السند بقيد عكسي ثم إعادة إدخاله
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.cancel_voucher(pg_temp.v('receipt', 1))$$,
  'إلغاء سند القبض بقيد عكسي'
);
select results_eq(
  $$select r.entry_date, r.source_type, a.code, l.debit, l.credit, c.name
    from public.journal_entries r
    join public.journal_lines l on l.entry_id = r.id
    join public.accounts a on a.id = l.account_id
    left join public.customers c on c.id = l.customer_id
    where r.reverses_entry_id = (select journal_entry_id from public.vouchers where id = pg_temp.v('receipt', 1))
    order by l.id$$,
  $$values ('1990-05-10'::date, 'reversal'::text, '1101'::text, 0.00::numeric, 1000.00::numeric, null::text),
           ('1990-05-10', 'reversal', '1201', 1000.00, 0.00, 'ع1 اختبار')$$,
  'القيد العكسي بنفس التاريخ وسطور معكوسة بنفس العميل'
);
select is(
  (select balance from public.party_balances('customer') where party_id = pg_temp.cust('ع1 اختبار')),
  '2700.00',
  'رصيد العميل يعود كما كان بعد إلغاء السند'
);
select results_eq(
  $$select code, debit, credit from public.trial_balance('1990-12-31')
    where code in ('1101', '1201')$$,
  $$values ('1101'::text, '94800.00'::text, '0.00'::text), ('1201', '2750.00', '0.00')$$,
  'الخزينة والعملاء في ميزان المراجعة بعد الإلغاء'
);
select results_eq(
  $$select v.doc_no - (select receipt_no from pg_temp._base), v.is_cancelled
    from public.voucher_list('receipt', '1990-01-01', '1990-12-31') v
    where v.id > (select voucher_id from pg_temp._base)
    order by v.doc_no$$,
  $$values (1::bigint, true), (2, false), (3, false)$$,
  'قائمة السندات تُظهر السند الملغى'
);
select throws_ok(
  $$select public.cancel_voucher(pg_temp.v('receipt', 1))$$,
  'P0001', 'سند القبض رقم ' || ((select receipt_no from _base) + 1) || ' ملغى بالفعل',
  'لا يُلغى السند مرتين'
);
select throws_ok(
  $$select public.cancel_journal_entry((select journal_entry_id from public.vouchers where id = pg_temp.v('payment', 1)))$$,
  'P0001', 'هذا القيد يُلغى من خلال المستند المرتبط به',
  'قيد السند لا يُلغى من شاشة القيود'
);

select lives_ok(
  $$select public.post_voucher('receipt', '1990-05-10', pg_temp.acc('1101'), 'customer',
      pg_temp.cust('ع1 اختبار'), '1000', 'دفعة')$$,
  'إعادة إدخال سند القبض بعد إلغائه (رقم جديد)'
);
select lives_ok(
  $$select public.post_journal_entry('1990-05-31', 'إهلاك الفترة', 'adjustment', jsonb_build_array(
      pg_temp.line('6801', '500', '0'), pg_temp.line('1509', '0', '500')))$$,
  'قيد تسوية إهلاك 500 (SPEC §11 الخطوة 8)'
);

-- ---------------------------------------------------------------------
-- الدقة والمطابقة مع الأستاذ العام
-- ---------------------------------------------------------------------
select results_eq(
  $$select c.name, b.balance from public.party_balances('customer', '1990-12-31') b
    join public.customers c on c.id = b.party_id
    where c.name like '% اختبار'
    order by c.name$$,
  $$values ('ع1 اختبار'::text, '1700.00'::text), ('ع2 اختبار', '50.00')$$,
  'رصيد العميل ع1 1,700 مدين (SPEC §11) والعميل ع2 50 مدين'
);
select results_eq(
  $$select s.name, b.balance from public.party_balances('supplier', '1990-12-31') b
    join public.suppliers s on s.id = b.party_id
    where s.name like '% اختبار'
    order by s.name$$,
  $$values ('م1 اختبار'::text, '-5500.00'::text), ('م2 اختبار', '-100.00')$$,
  'رصيد المورد م1 5,500 دائن (SPEC §11) والمورد م2 100 دائن'
);
select is(
  (select sum(balance::numeric) from public.party_balances('customer', '1990-12-31')),
  (select debit::numeric - credit::numeric from public.trial_balance('1990-12-31') where code = '1201'),
  'مجموع أرصدة العملاء = رصيد حساب العملاء'
);
select is(
  (select sum(balance::numeric) from public.party_balances('supplier', '1990-12-31')),
  (select debit::numeric - credit::numeric from public.trial_balance('1990-12-31') where code = '2101'),
  'مجموع أرصدة الموردين = رصيد حساب الموردين'
);
select results_eq(
  $$select code, debit, credit from public.trial_balance('1990-12-31') where code in ('1101', '1102')$$,
  $$values ('1101'::text, '95800.00'::text, '0.00'::text), ('1102', '350.00', '0.00')$$,
  'رصيد الخزينة 95,800 والبنك 350 من القيود'
);
select is(
  (select s.balance
   from public.account_statement(pg_temp.acc('1101'), null, '1990-12-31') with ordinality as s
   order by s.ordinality desc limit 1),
  '95800.00',
  'الرصيد الختامي في كشف حساب الخزينة = رصيدها في ميزان المراجعة'
);
select results_eq(
  $$select debit, credit, balance
    from public.party_statement('customer', pg_temp.cust('ع1 اختبار'), '1990-05-01', '1990-12-31')$$,
  $$values (null::text, null::text, '2700.00'::text),
           ('0.00', '1000.00', '1700.00'),
           ('1000.00', '0.00', '2700.00'),
           ('0.00', '1000.00', '1700.00')$$,
  'كشف حساب العميل: رصيد أول المدة ثم رصيد جارٍ بعد القبض والإلغاء وإعادة القبض'
);
select is(
  (select count(*)
   from (
     select 'customer' as kind, id from public.customers where name like '% اختبار'
     union all
     select 'supplier', id from public.suppliers where name like '% اختبار'
   ) p
   where coalesce(
           (select s.balance
            from public.party_statement(p.kind, p.id, null, '1990-12-31') with ordinality as s
            order by s.ordinality desc limit 1), '0.00')
         is distinct from coalesce(
           (select b.balance from public.party_balances(p.kind, '1990-12-31') b where b.party_id = p.id), '0.00')),
  0::bigint,
  'الرصيد الختامي في كشف كل طرف = رصيده في أرصدة الأطراف'
);
select results_eq(
  $$select sum(debit::numeric), sum(credit::numeric) from public.trial_balance('1990-12-31')$$,
  $$values (148600.00::numeric, 148600.00::numeric)$$,
  'ميزان المراجعة متوازن: 148,600 = 148,600'
);

-- ---------------------------------------------------------------------
-- ربط حسابي العملاء والموردين ثابت بعد وجود قيود
-- ---------------------------------------------------------------------
reset role;

select throws_ok(
  $$update public.system_accounts set account_id = pg_temp.acc('1401') where key = 'receivables'$$,
  'P0001', 'لا يمكن تغيير حساب العملاء بعد وجود قيود على الحساب الحالي أو الجديد',
  'لا يتغيّر حساب العملاء بعد وجود قيود'
);
select throws_ok(
  $$update public.system_accounts set account_id = pg_temp.acc('2201') where key = 'payables'$$,
  'P0001', 'لا يمكن تغيير حساب الموردين بعد وجود قيود على الحساب الحالي أو الجديد',
  'لا يتغيّر حساب الموردين بعد وجود قيود'
);

select lives_ok($$set constraints all immediate$$, 'كل القيود المعتمدة متوازنة عند الفحص المؤجَّل');

select * from finish();
rollback;
