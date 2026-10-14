-- =====================================================================
-- اختبارات القوائم المالية والقفل والإقفال (المرحلة 7): السنة المالية، القفل الشهري، سيناريو SPEC §11 كاملًا
-- حتى الخطوة 9 (قائمة الدخل والميزانية وقيد الإقفال والميزان بعده)، السنة التالية، قيود الإقفال والحسابات
-- المحمية، والشاشة الرئيسية. تعمل داخل transaction تُلغى في النهاية.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(71);

-- ---------------------------------------------------------------------
-- تهيئة معزولة داخل الـ transaction
-- ---------------------------------------------------------------------
update public.settings set lock_date = null where id = 1;
delete from public.fiscal_years where id > 0;

insert into auth.users (id, email, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'accountant@test.local', 'authenticated', 'authenticated');
update public.profiles set role = 'admin' where id = '11111111-1111-1111-1111-111111111111';

select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select public.cancel_journal_entry(o.id)
from public.journal_entries o
where o.source_type = 'opening'
  and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id);

create function pg_temp.as_admin() returns text language sql as $$
  select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
$$;
create function pg_temp.as_accountant() returns text language sql as $$
  select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
$$;
create function pg_temp.today() returns date language sql stable as $$
  select (now() at time zone 'Africa/Cairo')::date;
$$;
create function pg_temp.lock() returns text language sql stable as $$
  select lock_date::text from public.settings where id = 1;
$$;
create function pg_temp.acc(p_code text) returns bigint language sql stable as $$
  select id from public.accounts where code = p_code;
$$;
create function pg_temp.item(p_code text) returns bigint language sql stable as $$
  select id from public.items where code = p_code;
$$;
create function pg_temp.cust(p_name text) returns bigint language sql stable as $$
  select id from public.customers where name = p_name;
$$;
create function pg_temp.supp(p_name text) returns bigint language sql stable as $$
  select id from public.suppliers where name = p_name;
$$;
create function pg_temp.line(p_code text, p_debit text, p_credit text) returns jsonb language sql stable as $$
  select jsonb_build_object('account_id', (select id from public.accounts where code = p_code),
                            'debit', p_debit, 'credit', p_credit);
$$;
create function pg_temp.pl(p_code text, p_qty text, p_price text) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'qty', p_qty, 'unit_price', p_price);
$$;
create function pg_temp.fl(p_code text, p_qty text) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'qty_per_batch', p_qty, 'qty', p_qty);
$$;
create function pg_temp.year_entry(p_name text) returns bigint language sql stable as $$
  select closing_entry_id from public.fiscal_years where name = p_name;
$$;
create function pg_temp.entry_lines(p_entry bigint)
returns table (code text, debit text, credit text) language sql stable as $$
  select a.code, l.debit::text, l.credit::text
  from public.journal_lines l join public.accounts a on a.id = l.account_id
  where l.entry_id = p_entry order by l.id;
$$;

-- ---------------------------------------------------------------------
-- 1) الصلاحيات
-- ---------------------------------------------------------------------
set local role anon;
select throws_ok($$select * from public.fiscal_years$$, '42501', null, 'anon لا يقرأ السنوات المالية');
select throws_ok($$select * from public.income_statement()$$, '42501', null, 'anon لا يقرأ قائمة الدخل');
select throws_ok($$select * from public.dashboard_summary()$$, '42501', null, 'anon لا يقرأ ملخص الشاشة الرئيسية');
reset role;

set local role authenticated;
select pg_temp.as_accountant();
select throws_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1990', '1990-01-01', '1990-12-31')$$,
  '42501', 'هذه العملية لمدير النظام فقط', 'المحاسب لا يعرّف السنة المالية'
);
select throws_ok($$select public.lock_period('1990-01-31')$$, '42501', 'هذه العملية لمدير النظام فقط',
  'المحاسب لا يقفل الفترات');
select throws_ok($$select public.close_fiscal_year()$$, '42501', 'هذه العملية لمدير النظام فقط',
  'المحاسب لا يقفل السنة');
select throws_ok(
  $$insert into public.fiscal_years (name, start_date, end_date) values ('مباشر', '1990-01-01', '1990-12-31')$$,
  '42501', null, 'المستخدم لا يكتب السنوات المالية مباشرة'
);
select throws_ok(
  $$update public.settings set lock_date = '1990-01-31' where id = 1$$,
  '42501', null, 'تاريخ القفل لا يُعدَّل مباشرة'
);
select lives_ok($$select * from public.balance_sheet()$$, 'المستخدم يقرأ الميزانية');

-- البيانات الأساسية (SPEC §11)
insert into public.items (code, name, type, unit, sale_price, is_active) values
  ('C-LABSA', 'LABSA إقفال اختبار', 'raw_material', 'كجم', null, true),
  ('C-SLES', 'SLES إقفال اختبار', 'raw_material', 'كجم', null, true),
  ('C-SALT', 'ملح إقفال اختبار', 'raw_material', 'كجم', null, true),
  ('C-BOTTLE', 'عبوة 1 لتر إقفال اختبار', 'packaging', 'قطعة', null, true),
  ('C-DISH', 'سائل أطباق إقفال اختبار', 'finished_good', 'عبوة', 18, true);
insert into public.suppliers (name) values ('م1 إقفال اختبار');
insert into public.customers (name) values ('ع1 إقفال اختبار');
select public.save_formula(null, 'سائل أطباق إقفال اختبار', pg_temp.item('C-DISH'), '100', null, jsonb_build_array(
  pg_temp.fl('C-LABSA', '8'), pg_temp.fl('C-SLES', '6'), pg_temp.fl('C-SALT', '3'), pg_temp.fl('C-BOTTLE', '100')));

-- قيد قبل بداية السنة ثم إلغاؤه (صافيهما صفر)
select public.post_journal_entry('1989-12-20', 'مصروف قبل السنة', 'manual', jsonb_build_array(
  pg_temp.line('6901', '10', '0'), pg_temp.line('1101', '0', '10')));

-- ---------------------------------------------------------------------
-- 2) تعريف السنة المالية
-- ---------------------------------------------------------------------
select pg_temp.as_admin();
select throws_ok($$select public.save_open_fiscal_year('س', '1990-01-02', '1990-12-31')$$,
  'P0001', 'بداية السنة المالية يجب أن تكون أول يوم في شهر', 'البداية أول الشهر');
select throws_ok($$select public.save_open_fiscal_year('س', '1990-01-01', '1990-12-30')$$,
  'P0001', 'نهاية السنة المالية يجب أن تكون آخر يوم في شهر', 'النهاية آخر الشهر');
select throws_ok($$select public.save_open_fiscal_year('س', '1990-12-01', '1990-11-30')$$,
  'P0001', 'نهاية السنة المالية يجب أن تكون بعد بدايتها', 'النهاية بعد البداية');
select throws_ok($$select public.save_open_fiscal_year('س', '1990-01-01', '1992-01-31')$$,
  'P0001', 'السنة المالية لا تزيد عن 24 شهرًا', 'السنة لا تزيد عن 24 شهرًا');
select throws_ok($$select public.save_open_fiscal_year('  ', '1990-01-01', '1990-12-31')$$,
  'P0001', 'اسم السنة المالية مطلوب', 'الاسم مطلوب');
select throws_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1990', '1990-01-01', '1990-12-31')$$,
  'P0001', 'توجد قيود بتاريخ قبل بداية السنة المالية (أولها بتاريخ 20/12/1989). اختر بداية لا تتأخر عن أول قيد',
  'أول سنة لا تبدأ بعد قيود سابقة'
);
select public.cancel_journal_entry(id) from public.journal_entries where description = 'مصروف قبل السنة';
select lives_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1990', '1990-01-01', '1990-12-31')$$,
  'قيد سابق ملغى مع عكسه (صافيهما صفر) لا يمنع أول سنة'
);
select results_eq(
  $$select name, start_date::text, end_date::text, is_closed, pg_temp.lock() from public.fiscal_years$$,
  $$values ('السنة المالية 1990'::text, '1990-01-01'::text, '1990-12-31'::text, false, '1989-12-31'::text)$$,
  'السنة 1990 مفتوحة، وتاريخ القفل = اليوم السابق لبدايتها'
);
select throws_ok(
  $$select public.post_journal_entry('1989-12-31', 'قبل السنة', 'manual', jsonb_build_array(
      pg_temp.line('6901', '10', '0'), pg_temp.line('1101', '0', '10')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 31/12/1989 لأن الفترة مقفولة حتى 31/12/1989',
  'لا يُسجَّل شيء قبل بداية السنة المالية'
);

-- ---------------------------------------------------------------------
-- 3) SPEC §11 الخطوات 1–8
-- ---------------------------------------------------------------------
select pg_temp.as_accountant();
select public.post_opening_balances('1990-01-01', jsonb_build_array(
  pg_temp.line('1101', '100000', '0'), pg_temp.line('1501', '50000', '0'), pg_temp.line('3101', '0', '150000')));
select public.post_purchase_invoice('1990-01-10', pg_temp.supp('م1 إقفال اختبار'), jsonb_build_array(
  pg_temp.pl('C-LABSA', '100', '40'), pg_temp.pl('C-SLES', '100', '50'), pg_temp.pl('C-SALT', '100', '5'),
  pg_temp.pl('C-BOTTLE', '500', '2')));
select public.post_voucher('payment', '1990-01-15', pg_temp.acc('1101'), 'supplier', pg_temp.supp('م1 إقفال اختبار'), '5000');
select public.post_production_order('1990-02-01', (select id from public.formulas where name = 'سائل أطباق إقفال اختبار'),
  '2', '200', null, jsonb_build_array(pg_temp.fl('C-LABSA', '16'), pg_temp.fl('C-SLES', '12'), pg_temp.fl('C-SALT', '6'),
                                      pg_temp.fl('C-BOTTLE', '200')),
  '330', pg_temp.acc('1101'));
select public.post_sales_invoice('1990-02-10', pg_temp.cust('ع1 إقفال اختبار'), jsonb_build_array(
  jsonb_build_object('item_id', pg_temp.item('C-DISH'), 'qty', '150', 'unit_price', '18')));
select public.post_voucher('receipt', '1990-02-15', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع1 إقفال اختبار'), '1000');
select public.post_voucher('payment', '1990-02-20', pg_temp.acc('1101'), 'account', pg_temp.acc('6201'), '200');
select public.post_journal_entry('1990-02-28', 'إهلاك', 'adjustment', jsonb_build_array(
  pg_temp.line('6801', '500', '0'), pg_temp.line('1509', '0', '500')));

select pg_temp.as_admin();
select throws_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1990', '1990-02-01', '1990-12-31')$$,
  'P0001', 'توجد قيود بتاريخ قبل بداية السنة المالية (أولها بتاريخ 01/01/1990). اختر بداية لا تتأخر عن أول قيد',
  'بداية أول سنة لا تتأخر عن قيودها'
);
select throws_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1990', '1989-12-01', '1990-12-31')$$,
  'P0001', 'الفترة مقفولة حتى 31/12/1989، فلا تبدأ السنة المالية قبل ذلك',
  'بداية أول سنة لا تتقدم على تاريخ القفل (القفل لا يرجع للخلف)'
);

-- ---------------------------------------------------------------------
-- 4) القفل الشهري
-- ---------------------------------------------------------------------
select throws_ok($$select public.lock_period('1990-01-30')$$,
  'P0001', 'تاريخ القفل يجب أن يكون آخر يوم في شهر', 'القفل الشهري بآخر يوم في الشهر');
select lives_ok($$select public.lock_period('1990-01-31')$$, 'قفل يناير 1990');
select is(pg_temp.lock(), '1990-01-31', 'تاريخ القفل = 31/01/1990');
select throws_ok($$select public.lock_period('1990-01-31')$$,
  'P0001', 'الفترة مقفولة بالفعل حتى 31/01/1990. القفل للأمام فقط', 'لا قفل لنفس التاريخ مرة أخرى');
select throws_ok($$select public.lock_period('1989-12-31')$$,
  'P0001', 'الفترة مقفولة بالفعل حتى 31/01/1990. القفل للأمام فقط', 'لا رجوع بالقفل للخلف');
select throws_ok($$select public.lock_period('1990-12-31')$$,
  'P0001', 'القفل الشهري قبل نهاية السنة المالية (31/12/1990). نهاية السنة تُقفل بإقفال السنة',
  'القفل الشهري لا يصل لنهاية السنة');
select throws_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1990', '1990-01-01', '1990-01-31')$$,
  'P0001', 'نهاية السنة المالية يجب أن تكون بعد تاريخ القفل 31/01/1990',
  'نهاية السنة بعد تاريخ القفل'
);
select pg_temp.as_accountant();
select throws_ok(
  $$select public.post_voucher('payment', '1990-01-20', pg_temp.acc('1101'), 'account', pg_temp.acc('6201'), '10')$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 20/01/1990 لأن الفترة مقفولة حتى 31/01/1990',
  'مستند في شهر مقفول مرفوض'
);

-- ---------------------------------------------------------------------
-- 5) القوائم المالية قبل الإقفال (SPEC §11)
-- ---------------------------------------------------------------------
select results_eq(
  $$select section, code, amount from public.income_statement('1990-01-01', '1990-12-31')$$,
  $$values ('sales'::text, '4101'::text, '2700.00'::text), ('cost_of_sales', '5101', '1500.00'),
           ('expenses', '6201', '200.00'), ('expenses', '6801', '500.00')$$,
  'قائمة الدخل: مبيعات 2,700، تكلفة المبيعات 1,500، مصروفات 200 + 500'
);
select results_eq(
  $$select sum(amount::numeric) filter (where section = 'sales')
             - sum(amount::numeric) filter (where section = 'cost_of_sales'),
           sum(amount::numeric) filter (where section in ('sales', 'other_revenue'))
             - sum(amount::numeric) filter (where section in ('cost_of_sales', 'expenses'))
    from public.income_statement('1990-01-01', '1990-12-31')$$,
  $$values (1200.00::numeric, 500.00::numeric)$$,
  'مجمل الربح 1,200 وصافي الربح 500'
);
select results_eq(
  $$select section, code, amount from public.balance_sheet('1990-12-31')$$,
  $$values ('asset'::text, '1101'::text, '95470.00'::text), ('asset', '1201', '1700.00'), ('asset', '1301', '8230.00'),
           ('asset', '1302', '600.00'), ('asset', '1303', '500.00'), ('asset', '1501', '50000.00'),
           ('asset', '1509', '-500.00'), ('liability', '2101', '5500.00'), ('equity', '3101', '150000.00'),
           ('equity', null, '500.00')$$,
  'الميزانية: الأصول (مجمع الإهلاك سالب)، الموردون 5,500، رأس المال 150,000، وربح الفترة 500'
);
select results_eq(
  $$select sum(amount::numeric) filter (where section = 'asset'),
           sum(amount::numeric) filter (where section in ('liability', 'equity'))
    from public.balance_sheet('1990-12-31')$$,
  $$values (156000.00::numeric, 156000.00::numeric)$$,
  'الأصول 156,000 = الخصوم وحقوق الملكية 156,000'
);
select results_eq(
  $$select sum(debit::numeric), sum(credit::numeric) from public.trial_balance('1990-12-31')$$,
  $$values (158700.00::numeric, 158700.00::numeric)$$,
  'ميزان المراجعة قبل الإقفال 158,700 = 158,700'
);

-- ---------------------------------------------------------------------
-- 6) إقفال السنة (SPEC §11 الخطوة 9)
-- ---------------------------------------------------------------------
select results_eq(
  $$select line_no, code, debit, credit from public.fiscal_year_closing_preview()$$,
  $$values (1, '4101'::text, '2700.00'::text, '0.00'::text), (2, '5101', '0.00', '1500.00'),
           (3, '6201', '0.00', '200.00'), (4, '6801', '0.00', '500.00'), (5, '3301', '0.00', '500.00')$$,
  'معاينة الإقفال: م إيرادات المبيعات 2,700 / د تكلفة المبيعات 1,500 + الكهرباء 200 + الإهلاك 500 + الأرباح المرحّلة 500'
);
select throws_ok($$select public.close_fiscal_year()$$, '42501', 'هذه العملية لمدير النظام فقط',
  'المحاسب لا يقفل السنة');
select pg_temp.as_admin();
select lives_ok($$select public.close_fiscal_year()$$, 'إقفال السنة المالية 1990');
select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.year_entry('السنة المالية 1990'))$$,
  $$values ('4101'::text, '2700.00'::text, '0.00'::text), ('5101', '0.00', '1500.00'), ('6201', '0.00', '200.00'),
           ('6801', '0.00', '500.00'), ('3301', '0.00', '500.00')$$,
  'قيد الإقفال كما في SPEC بالضبط'
);
select results_eq(
  $$select entry_date::text, source_type from public.journal_entries where id = pg_temp.year_entry('السنة المالية 1990')$$,
  $$values ('1990-12-31'::text, 'closing'::text)$$,
  'قيد الإقفال بتاريخ نهاية السنة ونوعه إقفال'
);
select results_eq(
  $$select name, start_date::text, end_date::text, is_closed, closing_entry_id is not null
    from public.fiscal_years order by start_date$$,
  $$values ('السنة المالية 1990'::text, '1990-01-01'::text, '1990-12-31'::text, true, true),
           ('السنة المالية 1991', '1991-01-01', '1991-12-31', false, false)$$,
  'السنة 1990 مقفلة بقيدها، والسنة 1991 أُنشئت مفتوحة (12 شهرًا)'
);
select is(pg_temp.lock(), '1990-12-31', 'تاريخ القفل = نهاية السنة المقفلة');
select results_eq(
  $$select sum(debit::numeric), sum(credit::numeric), count(*) filter (where type in ('revenue', 'expense'))
    from public.trial_balance('1990-12-31')$$,
  $$values (156500.00::numeric, 156500.00::numeric, 0::bigint)$$,
  'ميزان المراجعة بعد الإقفال 156,500 = 156,500، والإيرادات والمصروفات صفر'
);
select results_eq(
  $$select section, code, amount from public.balance_sheet('1990-12-31') where section = 'equity'$$,
  $$values ('equity'::text, '3101'::text, '150000.00'::text), ('equity', '3301', '500.00'), ('equity', null, '0.00')$$,
  'بعد الإقفال: الربح في الأرباح المرحّلة 500، ولا ربح غير مقفل'
);
select results_eq(
  $$select sum(amount::numeric) filter (where section = 'asset'),
           sum(amount::numeric) filter (where section in ('liability', 'equity'))
    from public.balance_sheet('1990-12-31')$$,
  $$values (156000.00::numeric, 156000.00::numeric)$$,
  'الميزانية بعد الإقفال 156,000 = 156,000'
);
select results_eq(
  $$select sum(amount::numeric) filter (where section in ('sales', 'other_revenue'))
             - sum(amount::numeric) filter (where section in ('cost_of_sales', 'expenses'))
    from public.income_statement('1990-01-01', '1990-12-31')$$,
  $$values (500.00::numeric)$$,
  'قائمة الدخل لا تتأثر بقيد الإقفال (صافي الربح 500)'
);
select pg_temp.as_accountant();
select throws_ok(
  $$select public.post_journal_entry('1990-12-31', 'بعد الإقفال', 'manual', jsonb_build_array(
      pg_temp.line('6901', '10', '0'), pg_temp.line('1101', '0', '10')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 31/12/1990 لأن الفترة مقفولة حتى 31/12/1990',
  'أي قيد بتاريخ ≤ نهاية السنة المقفلة مرفوض'
);
select throws_ok(
  $$select public.cancel_sales_invoice((select id from public.sales_invoices
      where journal_entry_id = (select max(id) from public.journal_entries where source_type = 'sale')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 10/02/1990 لأن الفترة مقفولة حتى 31/12/1990',
  'إلغاء مستند في سنة مقفلة مرفوض'
);
select throws_ok(
  $$select public.cancel_journal_entry(pg_temp.year_entry('السنة المالية 1990'))$$,
  'P0001', 'لا يمكن إلغاء قيد الإقفال، فالسنة المقفلة لا تُعاد فتحها',
  'قيد الإقفال لا يُلغى'
);
select throws_ok(
  $$select public.cancel_journal_entry((select id from public.journal_entries where description = 'إهلاك'))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 28/02/1990 لأن الفترة مقفولة حتى 31/12/1990',
  'رسالة إلغاء باقي القيود كما هي (القفل)'
);

-- سنة بلا إيرادات ولا مصروفات: تُقفل بلا قيد، والسنة التالية تُنشأ
select pg_temp.as_admin();
select lives_ok($$select public.close_fiscal_year()$$, 'إقفال السنة 1991 (بلا أرصدة)');
select results_eq(
  $$select name, is_closed, closing_entry_id is null from public.fiscal_years order by start_date$$,
  $$values ('السنة المالية 1990'::text, true, false), ('السنة المالية 1991', true, true),
           ('السنة المالية 1992', false, true)$$,
  'السنة 1991 مقفلة بلا قيد إقفال، و1992 مفتوحة'
);
select throws_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1992', '1992-02-01', '1992-12-31')$$,
  'P0001', 'بداية السنة المالية تلي نهاية السنة المقفلة السابقة (01/01/1992) ولا تتغير',
  'بداية السنة التالية ثابتة'
);
select lives_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1992/1993', '1992-01-01', '1992-06-30')$$,
  'تعديل اسم السنة المفتوحة ونهايتها (سنة قصيرة)'
);
select lives_ok($$select public.close_fiscal_year()$$, 'إقفال السنة القصيرة');
select results_eq(
  $$select name, start_date::text, end_date::text from public.fiscal_years where not is_closed$$,
  $$values ('السنة المالية 1992/1993 (2)'::text, '1992-07-01'::text, '1993-06-30'::text)$$,
  'السنة التالية 12 شهرًا من أول الشهر التالي، واسمها يتجنب التكرار'
);

-- ---------------------------------------------------------------------
-- 7) حماية الإقفال والقوائم
-- ---------------------------------------------------------------------
reset role;
select throws_ok(
  $$select private.post_entry(pg_temp.today(), 'إقفال خطأ', 'closing', jsonb_build_array(
      pg_temp.line('1101', '1', '0'), pg_temp.line('3301', '0', '1')))$$,
  'P0001', 'قيد الإقفال يقتصر على حسابات الإيرادات والمصروفات والأرباح المرحّلة',
  'قيد الإقفال لا يمس حسابات الميزانية غير الأرباح المرحّلة'
);
select throws_ok(
  $$update public.system_accounts set account_id = pg_temp.acc('3201') where key = 'retained_earnings'$$,
  'P0001', 'لا يمكن تغيير حساب الأرباح المرحّلة بعد وجود قيود على الحساب الحالي أو الجديد',
  'حساب الأرباح المرحّلة ثابت بعد القيود'
);
select throws_ok(
  $$update public.accounts set code = '7801' where code = '6801'$$,
  'P0001', 'لا يمكن تغيير الرقم الأول لكود حساب عليه قيود (يحدد مكانه في القوائم المالية)',
  'الرقم الأول لكود حساب عليه قيود ثابت'
);
select lives_ok(
  $$update public.accounts set name = 'مصروف الإهلاك السنوي' where code = '6801'$$,
  'تغيير اسم الحساب مسموح'
);

-- ---------------------------------------------------------------------
-- 8) الشاشة الرئيسية: الأرصدة من الأستاذ، ومبيعات الشهر وصافي ربحه بنفس تعريف قائمة الدخل
-- ---------------------------------------------------------------------
update public.items set min_stock = 60 where code = 'C-DISH';
set local role authenticated;
select pg_temp.as_accountant();
select lives_ok(
  $$select public.post_sales_invoice(pg_temp.today(), pg_temp.cust('ع1 إقفال اختبار'), jsonb_build_array(
      jsonb_build_object('item_id', pg_temp.item('C-DISH'), 'qty', '1', 'unit_price', '18')))$$,
  'بيع اليوم: عبوة بـ 18'
);
select results_eq(
  $$select treasury, receivables, payables, inventory, month_sales, month_net_profit, low_stock_items,
           month_start = date_trunc('month', pg_temp.today()::timestamp)::date
    from public.dashboard_summary()$$,
  $$values ('95470.00'::text, '1718.00'::text, '5500.00'::text, '9320.00'::text, '18.00'::text, '8.00'::text,
            1::bigint, true)$$,
  'الخزينة 95,470، العملاء 1,718، الموردون 5,500، المخزون 9,320، مبيعات الشهر 18 وربحه 8، صنف تحت الحد الأدنى'
);
select results_eq(
  $$select (select sum(amount::numeric) from public.income_statement(d.month_start, d.month_end)
            where section = 'sales')::text,
           (select sum(case when section in ('sales', 'other_revenue') then amount::numeric else -amount::numeric end)
            from public.income_statement(d.month_start, d.month_end))::text
    from public.dashboard_summary() d$$,
  $$select month_sales, month_net_profit from public.dashboard_summary()$$,
  'مبيعات الشهر وصافي ربحه في الشاشة الرئيسية = قائمة الدخل لنفس الشهر'
);
select results_eq(
  $$select (select sum(value) from public.item_stock s join public.items i on i.id = s.item_id)::text,
           (select inventory from public.dashboard_summary())$$,
  $$values ('9320.00'::text, '9320.00'::text)$$,
  'قيمة المخزون في الشاشة الرئيسية (من الأستاذ) = قيمة الأصناف'
);

-- ---------------------------------------------------------------------
-- 9) القفل والإقفال لا يسبقان الواقع (سنة تشمل اليوم)
-- ---------------------------------------------------------------------
reset role;
delete from public.fiscal_years where not is_closed;
insert into public.fiscal_years (name, start_date, end_date)
values ('سنة جارية اختبار', date_trunc('year', pg_temp.today()::timestamp)::date,
        (date_trunc('year', pg_temp.today()::timestamp) + interval '24 months - 1 day')::date);
set local role authenticated;
select pg_temp.as_admin();
select throws_ok(
  $$select public.lock_period((date_trunc('month', pg_temp.today()::timestamp) + interval '2 months - 1 day')::date)$$,
  'P0001', 'لا يمكن قفل شهر لم ينتهِ بعد',
  'لا يُقفل شهر لم ينتهِ'
);
select lives_ok(
  $$select public.lock_period((date_trunc('month', pg_temp.today()::timestamp) - interval '1 day')::date)$$,
  'قفل الشهر الماضي'
);
select is(pg_temp.lock(), ((date_trunc('month', pg_temp.today()::timestamp) - interval '1 day')::date)::text,
  'تاريخ القفل = آخر يوم في الشهر الماضي');
select throws_ok(
  $$select public.close_fiscal_year()$$,
  'P0001', 'لا يمكن إقفال السنة المالية قبل انتهائها في '
    || to_char((date_trunc('year', pg_temp.today()::timestamp) + interval '24 months - 1 day')::date, 'DD/MM/YYYY'),
  'لا تُقفل سنة لم تنتهِ'
);
select pg_temp.as_accountant();
select throws_ok(
  $$select public.post_journal_entry((date_trunc('month', pg_temp.today()::timestamp) - interval '1 day')::date,
      'شهر مقفول', 'manual', jsonb_build_array(pg_temp.line('6901', '10', '0'), pg_temp.line('1101', '0', '10')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ '
    || to_char((date_trunc('month', pg_temp.today()::timestamp) - interval '1 day')::date, 'DD/MM/YYYY')
    || ' لأن الفترة مقفولة حتى '
    || to_char((date_trunc('month', pg_temp.today()::timestamp) - interval '1 day')::date, 'DD/MM/YYYY'),
  'القيد في الشهر المقفول مرفوض'
);

-- ---------------------------------------------------------------------
-- 10) المطابقة
-- ---------------------------------------------------------------------
select lives_ok($$set constraints all immediate$$, 'كل ما سبق يجتاز فحوص الـ commit بصلاحية المستخدم');
set constraints all deferred;
select results_eq(
  $$select sum(debit::numeric) = sum(credit::numeric) from public.trial_balance()$$,
  $$values (true)$$,
  'ميزان المراجعة متوازن'
);
select results_eq(
  $$select sum(amount::numeric) filter (where section = 'asset')
             = sum(amount::numeric) filter (where section in ('liability', 'equity'))
    from public.balance_sheet()$$,
  $$values (true)$$,
  'الميزانية الحالية متوازنة (بربح غير مقفل)'
);
select results_eq(
  $$select a.code,
           (select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l where l.account_id = a.id)::text,
           (select coalesce(sum(s.value), 0) from public.item_stock s join public.items i on i.id = s.item_id
            where i.type = case k.key when 'inventory_raw' then 'raw_material'
                                      when 'inventory_packaging' then 'packaging' else 'finished_good' end)::text
    from public.system_accounts k join public.accounts a on a.id = k.account_id
    where k.key in ('inventory_raw', 'inventory_packaging', 'inventory_finished')
    order by a.code$$,
  $$values ('1301'::text, '8230.00'::text, '8230.00'::text),
           ('1302', '600.00', '600.00'),
           ('1303', '490.00', '490.00')$$,
  'كل حساب مخزون في الأستاذ = قيمة أصناف نوعه'
);

reset role;
select * from finish();
rollback;
