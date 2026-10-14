-- =====================================================================
-- اختبارات المرحلة 2: المحاسبة الأساسية (pgTAP)
-- تعمل داخل transaction تُلغى في النهاية. قيود الاختبار بتاريخ 1990 حتى لا
-- تختلط بأي بيانات تجريبية في مشروع التطوير.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(64);

-- ---------------------------------------------------------------------
-- تهيئة معزولة داخل الـ transaction
-- ---------------------------------------------------------------------
update public.settings set lock_date = null where id = 1;

insert into auth.users (id, email, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'accountant@test.local', 'authenticated', 'authenticated');
update public.profiles set role = 'admin' where id = '11111111-1111-1111-1111-111111111111';

insert into public.accounts (code, name, type, parent_id, is_active)
select '6999', 'حساب معطل للاختبار', 'expense', id, false from public.accounts where code = '6000';

-- لو في مشروع التطوير قيد افتتاحي فعلي، يُلغى داخل الاختبار فقط (ثم يُسترجع بالـ rollback)
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select public.cancel_journal_entry(o.id)
from public.journal_entries o
where o.source_type = 'opening'
  and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id);

create temp table _base as
select (select last_no from public.doc_counters where kind = 'journal') as last_no,
       (select count(*) from public.journal_entries) as entries,
       (select count(*) from public.journal_lines) as lines;
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

-- ---------------------------------------------------------------------
-- الصلاحيات: anon
-- ---------------------------------------------------------------------
set local role anon;

select throws_ok($$select * from public.journal_entries$$, '42501', null, 'anon لا يقرأ القيود');
select throws_ok($$select * from public.journal_lines$$, '42501', null, 'anon لا يقرأ سطور القيود');
select throws_ok(
  $$select public.post_journal_entry('1990-01-05', 'x', 'manual', '[]'::jsonb)$$,
  '42501', null, 'anon لا يعتمد قيودًا'
);
select throws_ok($$select * from public.trial_balance('1990-12-31')$$, '42501', null, 'anon لا يقرأ ميزان المراجعة');

reset role;

-- ---------------------------------------------------------------------
-- الصلاحيات: المستخدم لا يكتب في جداول القيود مباشرة
-- ---------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select throws_ok(
  $$insert into public.journal_entries (entry_no, entry_date, description, source_type, created_by)
    values (999999, '1990-01-05', 'x', 'manual', '22222222-2222-2222-2222-222222222222')$$,
  '42501', null, 'المستخدم لا يكتب في journal_entries مباشرة'
);
select throws_ok(
  $$insert into public.journal_lines (entry_id, account_id, debit) values (1, 1, 1)$$,
  '42501', null, 'المستخدم لا يكتب في journal_lines مباشرة'
);
select throws_ok(
  $$update public.journal_lines set debit = 1 where id = 1$$,
  '42501', null, 'المستخدم لا يعدّل journal_lines'
);
select throws_ok(
  $$delete from public.journal_entries where id = 1$$,
  '42501', null, 'المستخدم لا يحذف journal_entries'
);
select throws_ok($$select * from public.doc_counters$$, '42501', null, 'المستخدم لا يقرأ عدّادات الترقيم');
select throws_ok(
  $$select private.post_entry('1990-01-05', 'x', 'manual', '[]'::jsonb)$$,
  '42501', null, 'دالة الاعتماد الداخلية غير متاحة للمستخدم'
);

-- ---------------------------------------------------------------------
-- الاعتماد: سيناريو SPEC §11 (الخطوات 1 و7 و8)
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1101', '100000', '0'),
      pg_temp.line('1501', '50000', '0'),
      pg_temp.line('3101', '0', '150000')))$$,
  'المحاسب يسجّل الأرصدة الافتتاحية'
);

select results_eq(
  $$select e.entry_no - (select last_no from _base), e.source_type, e.created_by,
           (select count(*) from public.journal_lines l where l.entry_id = e.id)
    from public.journal_entries e
    where e.entry_no = (select last_no from _base) + 1$$,
  $$values (1::bigint, 'opening'::text, '22222222-2222-2222-2222-222222222222'::uuid, 3::bigint)$$,
  'القيد الافتتاحي: الرقم التالي، النوع، المستخدم، 3 سطور'
);

select lives_ok(
  $$select public.post_journal_entry('1990-03-15', 'فاتورة كهرباء', 'manual', jsonb_build_array(
      pg_temp.line('6201', '200', '0'),
      pg_temp.line('1101', '0', '200')))$$,
  'قيد يومية يدوي: كهرباء 200 من الخزينة'
);

select lives_ok(
  $$select public.post_journal_entry('1990-03-31', 'إهلاك الفترة', 'adjustment', jsonb_build_array(
      pg_temp.line('6801', '500', '0'),
      pg_temp.line('1509', '0', '500')))$$,
  'قيد تسوية: إهلاك 500'
);

select results_eq(
  $$select entry_no - (select last_no from _base), source_type
    from public.journal_entries
    where entry_no > (select last_no from _base)
    order by entry_no$$,
  $$values (1::bigint, 'opening'::text), (2::bigint, 'manual'::text), (3::bigint, 'adjustment'::text)$$,
  'أرقام القيود متتالية بلا فجوات'
);

select lives_ok($$set constraints all immediate$$, 'القيود المعتمدة تجتاز فحص التوازن المؤجَّل');
set constraints all deferred;

-- ---------------------------------------------------------------------
-- الدقة المحاسبية: ميزان المراجعة وكشف الحساب من journal_lines فقط
-- ---------------------------------------------------------------------
select results_eq(
  $$select code, debit, credit from public.trial_balance('1990-12-31')$$,
  $$values ('1101'::text, '99800.00'::text, '0.00'::text),
           ('1501', '50000.00', '0.00'),
           ('1509', '0.00', '500.00'),
           ('3101', '0.00', '150000.00'),
           ('6201', '200.00', '0.00'),
           ('6801', '500.00', '0.00')$$,
  'ميزان المراجعة بالأرصدة حتى 31/12/1990'
);

select results_eq(
  $$select sum(debit::numeric), sum(credit::numeric) from public.trial_balance('1990-12-31')$$,
  $$values (150500.00::numeric, 150500.00::numeric)$$,
  'ميزان المراجعة متوازن: 150,500 = 150,500'
);

select results_eq(
  $$select sum(debit::numeric), sum(credit::numeric) from public.trial_balance('1990-03-20')$$,
  $$values (150000.00::numeric, 150000.00::numeric)$$,
  'ميزان المراجعة بتاريخ وسيط يستبعد القيود اللاحقة'
);

select is_empty($$select * from public.trial_balance('1989-12-31')$$, 'ميزان المراجعة قبل أول قيد فارغ');

select results_eq(
  $$select entry_date, debit, credit, balance
    from public.account_statement(pg_temp.acc('1101'), '1990-01-01', '1990-12-31')$$,
  $$values ('1990-01-01'::date, null::text, null::text, '0.00'::text),
           ('1990-01-01', '100000.00', '0.00', '100000.00'),
           ('1990-03-15', '0.00', '200.00', '99800.00')$$,
  'كشف حساب الخزينة: 100,000 ثم 99,800'
);

select results_eq(
  $$select description, balance
    from public.account_statement(pg_temp.acc('1101'), '1990-02-01', '1990-12-31')$$,
  $$values ('رصيد أول المدة'::text, '100000.00'::text), ('فاتورة كهرباء', '99800.00')$$,
  'رصيد أول المدة يجمع ما قبل بداية الفترة'
);

select is(
  (select min(balance::numeric) from public.account_statement(pg_temp.acc('3101'), '1990-01-01', '1990-12-31')),
  -150000.00::numeric,
  'رصيد رأس المال دائن (سالب في الرصيد الجاري)'
);

select results_eq(
  $$select entry_no - (select last_no from _base), source_type, total
    from public.journal_entry_list('1990-01-01', '1990-12-31', 'كهرباء')$$,
  $$values (2::bigint, 'manual'::text, '200.00'::text)$$,
  'قائمة القيود: البحث بالبيان والإجمالي نصًا بخانتين'
);

-- ---------------------------------------------------------------------
-- الرفض برسائل عربية
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'غير متوازن', 'manual', jsonb_build_array(
      pg_temp.line('6201', '100', '0'), pg_temp.line('1101', '0', '90')))$$,
  'P0001', 'القيد غير متوازن: إجمالي المدين 100.00 وإجمالي الدائن 90.00',
  'رفض قيد غير متوازن'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'سطر واحد', 'manual', jsonb_build_array(
      pg_temp.line('6201', '100', '0')))$$,
  'P0001', 'القيد يحتاج سطرين على الأقل',
  'رفض قيد بسطر واحد'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'مدين ودائن', 'manual', jsonb_build_array(
      pg_temp.line('6201', '100', '100'), pg_temp.line('1101', '0', '100')))$$,
  'P0001', 'السطر 1: أدخل مبلغًا في المدين أو في الدائن (واحدًا فقط)',
  'رفض سطر مدين ودائن معًا'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'سطر بلا مبلغ', 'manual', jsonb_build_array(
      pg_temp.line('6201', '100', '0'), pg_temp.line('1101', '0', '0')))$$,
  'P0001', 'السطر 2: أدخل مبلغًا في المدين أو في الدائن (واحدًا فقط)',
  'رفض سطر بلا مبلغ'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'سالب', 'manual', jsonb_build_array(
      pg_temp.line('6201', '-100', '0'), pg_temp.line('1101', '0', '-100')))$$,
  'P0001', 'السطر 1: المبلغ يجب أن يكون رقمًا موجبًا',
  'رفض مبلغ سالب'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'كسور', 'manual', jsonb_build_array(
      pg_temp.line('6201', '10.005', '0'), pg_temp.line('1101', '0', '10.005')))$$,
  'P0001', 'السطر 1: المبلغ لا يزيد عن خانتين عشريتين',
  'رفض أكثر من خانتين عشريتين (بلا تقريب صامت)'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'NaN', 'manual', jsonb_build_array(
      pg_temp.line('6201', 'NaN', '0'), pg_temp.line('1101', '0', '1')))$$,
  'P0001', 'السطر 1: المبلغ يجب أن يكون رقمًا موجبًا',
  'رفض NaN'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'نص', 'manual', jsonb_build_array(
      pg_temp.line('6201', 'abc', '0'), pg_temp.line('1101', '0', '1')))$$,
  'P0001', 'السطر 1: المبلغ "abc" غير صالح',
  'رفض مبلغ غير رقمي'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'حساب تجميعي', 'manual', jsonb_build_array(
      pg_temp.line('6000', '100', '0'), pg_temp.line('1101', '0', '100')))$$,
  'P0001', 'الترحيل مسموح فقط على حساب فرعي نشط: 6000 - المصروفات',
  'رفض الترحيل على حساب تجميعي'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'حساب معطل', 'manual', jsonb_build_array(
      pg_temp.line('6999', '100', '0'), pg_temp.line('1101', '0', '100')))$$,
  'P0001', 'الترحيل مسموح فقط على حساب فرعي نشط: 6999 - حساب معطل للاختبار',
  'رفض الترحيل على حساب معطّل'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'عملاء', 'manual', jsonb_build_array(
      pg_temp.line('1201', '100', '0'), pg_temp.line('4101', '0', '100')))$$,
  'P0001', 'لا يمكن الترحيل على حساب 1201 - العملاء بدون تحديد عميل أو مورد',
  'رفض حساب العملاء بدون عميل (القاعدة 9)'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'موردين', 'manual', jsonb_build_array(
      pg_temp.line('2101', '0', '100'), pg_temp.line('6201', '100', '0')))$$,
  'P0001', 'لا يمكن الترحيل على حساب 2101 - الموردين بدون تحديد عميل أو مورد',
  'رفض حساب الموردين بدون مورد (القاعدة 9)'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'مخزون', 'manual', jsonb_build_array(
      pg_temp.line('1301', '100', '0'), pg_temp.line('1101', '0', '100')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 1301 - مخزون مواد خام. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'رفض قيد يدوي على حساب المخزون'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', '   ', 'manual', jsonb_build_array(
      pg_temp.line('6201', '100', '0'), pg_temp.line('1101', '0', '100')))$$,
  'P0001', 'بيان القيد مطلوب',
  'رفض قيد بلا بيان'
);

select throws_ok(
  $$select public.post_journal_entry('1990-04-01', 'نوع خطأ', 'opening', jsonb_build_array(
      pg_temp.line('6201', '100', '0'), pg_temp.line('1101', '0', '100')))$$,
  'P0001', 'نوع القيد غير صالح',
  'القيد اليدوي يكون يومية أو تسوية فقط'
);

select throws_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1102', '10', '0'), pg_temp.line('3101', '0', '10')))$$,
  'P0001', 'الأرصدة الافتتاحية مسجّلة بالفعل. للتصحيح ألغِ القيد الافتتاحي ثم سجّلها من جديد',
  'الأرصدة الافتتاحية مرة واحدة فقط'
);

-- ---------------------------------------------------------------------
-- قفل الفترة (lock_date يُضبط هنا كمالك الجدول، ثم يُلغى)
-- ---------------------------------------------------------------------
reset role;
update public.settings set lock_date = '1990-06-30' where id = 1;
set local role authenticated;

select throws_ok(
  $$select public.post_journal_entry('1990-06-30', 'داخل الفترة المقفولة', 'manual', jsonb_build_array(
      pg_temp.line('6201', '10', '0'), pg_temp.line('1101', '0', '10')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 30/06/1990 لأن الفترة مقفولة حتى 30/06/1990',
  'رفض قيد بتاريخ داخل فترة مقفولة'
);

select lives_ok(
  $$select public.post_journal_entry('1990-07-01', 'بعد تاريخ القفل', 'manual', jsonb_build_array(
      pg_temp.line('6701', '10', '0'), pg_temp.line('1101', '0', '10')))$$,
  'القيد بعد تاريخ القفل مسموح'
);

select throws_ok(
  $$select public.cancel_journal_entry(
      (select id from public.journal_entries where entry_no = (select last_no from _base) + 2))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 15/03/1990 لأن الفترة مقفولة حتى 30/06/1990',
  'رفض إلغاء قيد تاريخه داخل فترة مقفولة'
);

reset role;
update public.settings set lock_date = null where id = 1;

-- ---------------------------------------------------------------------
-- التراجع الكامل: المحاولات المرفوضة لا تترك أثرًا ولا تستهلك أرقامًا
-- ---------------------------------------------------------------------
select results_eq(
  $$select (select last_no from public.doc_counters where kind = 'journal') - (select last_no from _base),
           (select count(*) from public.journal_entries) - (select entries from _base),
           (select count(*) from public.journal_lines) - (select lines from _base)$$,
  $$values (4::bigint, 4::bigint, 9::bigint)$$,
  'المحاولات المرفوضة لم تترك رأسًا ولا سطورًا ولم تستهلك أرقامًا'
);

-- ---------------------------------------------------------------------
-- ضمانات قاعدة البيانات حتى لمالك الجدول
-- ---------------------------------------------------------------------
select throws_ok(
  $$update public.journal_lines set debit = debit
    where entry_id = (select id from public.journal_entries where entry_no = (select last_no from _base) + 2)$$,
  'P0001', 'لا يمكن تعديل أو حذف قيد معتمد. للتصحيح ألغِ القيد ثم أدخله من جديد',
  'لا تعديل لسطور قيد معتمد حتى من مالك الجدول'
);

select throws_ok(
  $$delete from public.journal_entries where entry_no = (select last_no from _base) + 2$$,
  'P0001', 'لا يمكن تعديل أو حذف قيد معتمد. للتصحيح ألغِ القيد ثم أدخله من جديد',
  'لا حذف لقيد معتمد حتى من مالك الجدول'
);

select throws_ok(
  $$insert into public.journal_entries (entry_no, entry_date, description, source_type, created_by)
    values ((select last_no from _base) + 1, '1990-08-01', 'رقم مكرر', 'manual',
            '22222222-2222-2222-2222-222222222222')$$,
  '23505', null,
  'رقم القيد لا يتكرر أبدًا حتى مع التزامن (فهرس فريد)'
);

-- ---------------------------------------------------------------------
-- الإلغاء بقيد عكسي
-- ---------------------------------------------------------------------
set local role authenticated;

select lives_ok(
  $$select public.cancel_journal_entry(
      (select id from public.journal_entries where entry_no = (select last_no from _base) + 3))$$,
  'إلغاء قيد التسوية بقيد عكسي'
);

select results_eq(
  $$select r.entry_date, r.source_type, r.entry_no - (select last_no from _base), a.code, l.debit, l.credit
    from public.journal_entries r
    join public.journal_lines l on l.entry_id = r.id
    join public.accounts a on a.id = l.account_id
    where r.reverses_entry_id = (select id from public.journal_entries where entry_no = (select last_no from _base) + 3)
    order by l.id$$,
  $$values ('1990-03-31'::date, 'reversal'::text, 5::bigint, '6801'::text, 0.00::numeric, 500.00::numeric),
           ('1990-03-31', 'reversal', 5, '1509', 500.00, 0.00)$$,
  'القيد العكسي بنفس التاريخ وبسطور معكوسة'
);

select is(
  (select sum(l.debit - l.credit)
   from public.journal_lines l
   join public.journal_entries e on e.id = l.entry_id
   where l.account_id = pg_temp.acc('6801') and e.entry_no > (select last_no from _base)),
  0.00::numeric,
  'صافي حساب الإهلاك صفر بعد الإلغاء'
);

select throws_ok(
  $$select public.cancel_journal_entry(
      (select id from public.journal_entries where entry_no = (select last_no from _base) + 3))$$,
  'P0001', 'القيد رقم ' || ((select last_no from _base) + 3) || ' ملغى بالفعل',
  'لا يُلغى القيد مرتين'
);

select throws_ok(
  $$select public.cancel_journal_entry(
      (select id from public.journal_entries where entry_no = (select last_no from _base) + 5))$$,
  'P0001', 'لا يمكن إلغاء قيد عكسي',
  'لا يُلغى القيد العكسي'
);

reset role;

select throws_ok(
  $$insert into public.journal_entries (entry_no, entry_date, description, source_type, reverses_entry_id, created_by)
    values (-2, '1990-08-01', 'إلغاء مكرر', 'reversal',
            (select id from public.journal_entries where entry_no = (select last_no from _base) + 3),
            '22222222-2222-2222-2222-222222222222')$$,
  '23505', null,
  'لا يمكن إلغاء القيد مرتين حتى مع التزامن (فهرس فريد)'
);

-- ---------------------------------------------------------------------
-- الأرصدة الافتتاحية: الإلغاء ثم إعادة التسجيل، والفرق على رأس المال
-- ---------------------------------------------------------------------
set local role authenticated;

select lives_ok(
  $$select public.cancel_journal_entry(
      (select id from public.journal_entries where entry_no = (select last_no from _base) + 1))$$,
  'إلغاء القيد الافتتاحي'
);

select throws_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1101', '1000', '0'), pg_temp.line('3101', '0', '900')))$$,
  'P0001', 'الأرصدة غير متوازنة: المدين 1,000.00 والدائن 900.00 والفرق 100.00. أكّد تسجيل الفرق على حساب رأس المال',
  'أرصدة افتتاحية غير متوازنة تُرفض بدون تأكيد مع عرض الفرق'
);

select throws_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1301', '500', '0'), pg_temp.line('3101', '0', '500')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 1301 - مخزون مواد خام. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'لا أرصدة افتتاحية لحسابات المخزون من هذه الشاشة'
);

select lives_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1101', '1000', '0'), pg_temp.line('3101', '0', '900')), true)$$,
  'بعد التأكيد يُسجَّل الفرق على رأس المال'
);

select results_eq(
  $$select a.code, l.debit, l.credit
    from public.journal_lines l
    join public.accounts a on a.id = l.account_id
    where l.entry_id = (select max(id) from public.journal_entries where source_type = 'opening')
    order by l.id$$,
  $$values ('1101'::text, 1000.00::numeric, 0.00::numeric), ('3101', 0.00, 900.00), ('3101', 0.00, 100.00)$$,
  'القيد الافتتاحي الجديد وفيه سطر فرق رأس المال'
);

-- ---------------------------------------------------------------------
-- دليل الحسابات بعد وجود القيود
-- ---------------------------------------------------------------------
select throws_ok(
  $$delete from public.accounts where code = '6201'$$,
  'P0001', 'لا يمكن حذف حساب عليه قيود. يمكنك تعطيله بدل الحذف',
  'رفض حذف حساب عليه قيود'
);

select throws_ok(
  $$update public.accounts set is_postable = false where code = '6201'$$,
  'P0001', 'لا يمكن جعل حساب عليه قيود حسابًا تجميعيًا',
  'رفض تحويل حساب عليه قيود إلى تجميعي'
);

insert into public.accounts (code, name, type) values ('9001', 'حساب رئيسي للاختبار', 'expense');
select public.post_journal_entry('1991-01-10', 'قيد على حساب رئيسي', 'manual', jsonb_build_array(
  pg_temp.line('9001', '5', '0'), pg_temp.line('1101', '0', '5')));

select throws_ok(
  $$update public.accounts set type = 'asset' where code = '9001'$$,
  'P0001', 'لا يمكن تغيير نوع حساب عليه قيود',
  'رفض تغيير نوع حساب عليه قيود'
);

select lives_ok(
  $$update public.accounts set is_active = false where code = '6201'$$,
  'تعطيل حساب عليه قيود مسموح'
);

select throws_ok(
  $$select public.cancel_journal_entry(
      (select id from public.journal_entries where entry_no = (select last_no from _base) + 2))$$,
  'P0001', 'الترحيل مسموح فقط على حساب فرعي نشط: 6201 - كهرباء ومياه وغاز',
  'إلغاء قيد على حساب معطّل يُرفض حتى يُعاد تفعيله'
);

-- ---------------------------------------------------------------------
-- التوازن مفروض داخل قاعدة البيانات حتى للإدخال المباشر (آخر اختبار)
-- ---------------------------------------------------------------------
reset role;

insert into public.journal_entries (entry_no, entry_date, description, source_type, created_by)
values (-1, '1990-08-01', 'إدخال مباشر غير متوازن', 'manual', '22222222-2222-2222-2222-222222222222');
insert into public.journal_lines (entry_id, account_id, debit, credit)
select id, pg_temp.acc('6701'), 100, 0 from public.journal_entries where entry_no = -1;

select throws_ok(
  $$set constraints all immediate$$,
  'P0001', 'القيد غير متوازن أو ناقص: مدين 100.00 ودائن 0.00 في 1 سطر',
  'قاعدة البيانات ترفض قيدًا غير متوازن حتى لو أُدخل مباشرة'
);

select * from finish();
rollback;
