-- =====================================================================
-- اختبارات المبيعات (المرحلة 6): SPEC §11 الخطوات 5–8 ونتائجها، البيع بالوحدات والخصم بالوحدة الأساسية،
-- تكلفة المبيعات التاريخية، التحصيل الكامل والجزئي والآجل بسند قبض، الإلغاء (المنتج يرجع بتكلفته والسند
-- يبقى)، تقرير أرباح الأصناف ومطابقته مع 4101 − 5101، منع القيود اليدوية على 4101/5101، الرفض بلا أثر،
-- قفل الفترة، الترقيم، والمطابقة. تعمل داخل transaction تُلغى في النهاية.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(81);

-- ---------------------------------------------------------------------
-- تهيئة معزولة داخل الـ transaction
-- ---------------------------------------------------------------------
update public.settings set lock_date = null where id = 1;

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

create temp table _base as
select (select last_no from public.doc_counters where kind = 'sales_invoice') as sales_no,
       (select last_no from public.doc_counters where kind = 'receipt_voucher') as receipt_no,
       (select coalesce(max(id), 0) from public.journal_entries) as entry_id;
grant select on _base to public;

create function pg_temp.acc(p_code text) returns bigint language sql stable as $$
  select id from public.accounts where code = p_code;
$$;
create function pg_temp.item(p_code text) returns bigint language sql stable as $$
  select id from public.items where code = p_code;
$$;
create function pg_temp.unit(p_code text, p_name text) returns bigint language sql stable as $$
  select id from public.item_units where item_id = pg_temp.item(p_code) and name = p_name;
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
-- سطر بيع بوحدة (فارغ = الوحدة الأساسية)
create function pg_temp.sl(p_code text, p_qty text, p_price text, p_unit text default null) returns jsonb
language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'unit_id', pg_temp.unit(p_code, p_unit),
                            'qty', p_qty, 'unit_price', p_price);
$$;
create function pg_temp.si(p_n int) returns bigint language sql stable as $$
  select id from public.sales_invoices where doc_no = (select sales_no from pg_temp._base) + p_n;
$$;
create function pg_temp.si_entry(p_n int) returns bigint language sql stable as $$
  select journal_entry_id from public.sales_invoices where id = pg_temp.si(p_n);
$$;
create function pg_temp.reversal_of(p_entry bigint) returns bigint language sql stable as $$
  select id from public.journal_entries where reverses_entry_id = p_entry;
$$;
create function pg_temp.entry_lines(p_entry bigint)
returns table (code text, debit text, credit text, customer text) language sql stable as $$
  select a.code, l.debit::text, l.credit::text, c.name
  from public.journal_lines l join public.accounts a on a.id = l.account_id
  left join public.customers c on c.id = l.customer_id
  where l.entry_id = p_entry order by l.id;
$$;
create function pg_temp.stock(p_code text) returns table (qty text, value text, avg_cost text) language sql stable as $$
  select qty::text, value::text, avg_cost::text from public.item_stock where item_id = pg_temp.item(p_code);
$$;
create function pg_temp.card(p_code text, p_name text) returns jsonb language sql stable as $$
  select jsonb_build_object('id', pg_temp.item(p_code), 'code', p_code, 'name', p_name, 'type', 'finished_good',
                            'unit', 'عبوة', 'sale_price', '18');
$$;
create function pg_temp.state()
returns table (invoices bigint, lines bigint, entries bigint, movements bigint, vouchers bigint, sales_no bigint,
               receipt_no bigint, journal_no bigint)
language sql stable as $$
  select (select count(*) from public.sales_invoices), (select count(*) from public.sales_invoice_lines),
         (select count(*) from public.journal_entries), (select count(*) from public.stock_movements),
         (select count(*) from public.vouchers),
         (select last_no from public.doc_counters where kind = 'sales_invoice'),
         (select last_no from public.doc_counters where kind = 'receipt_voucher'),
         (select last_no from public.doc_counters where kind = 'journal');
$$;

-- ---------------------------------------------------------------------
-- 1) الصلاحيات
-- ---------------------------------------------------------------------
set local role anon;
select throws_ok($$select * from public.sales_invoices$$, '42501', null, 'anon لا يقرأ فواتير المبيعات');
select throws_ok(
  $$select public.post_sales_invoice('1990-02-10', 1, '[]'::jsonb)$$,
  '42501', null, 'anon لا يعتمد فاتورة مبيعات'
);
select throws_ok($$select * from public.item_profit()$$, '42501', null, 'anon لا يقرأ أرباح الأصناف');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

-- البيانات الأساسية (SPEC §11) + وحدات بيع للمنتج التام
insert into public.items (code, name, type, unit, sale_price, is_active) values
  ('S-LABSA', 'LABSA مبيعات اختبار', 'raw_material', 'كجم', null, true),
  ('S-SLES', 'SLES مبيعات اختبار', 'raw_material', 'كجم', null, true),
  ('S-SALT', 'ملح مبيعات اختبار', 'raw_material', 'كجم', null, true),
  ('S-BOTTLE', 'عبوة 1 لتر مبيعات اختبار', 'packaging', 'قطعة', null, true),
  ('S-DISH', 'سائل أطباق مبيعات اختبار', 'finished_good', 'عبوة', 18, true);
select public.save_item(pg_temp.card('S-DISH', 'سائل أطباق مبيعات اختبار'), jsonb_build_array(
  jsonb_build_object('name', 'كرتونة', 'factor', '12', 'sale_price', '200'),
  jsonb_build_object('name', 'عينة', 'factor', '0.125'),
  jsonb_build_object('name', 'شوال', 'factor', '24', 'is_active', false)));
select public.save_item(
  jsonb_build_object('id', pg_temp.item('S-BOTTLE'), 'code', 'S-BOTTLE', 'name', 'عبوة 1 لتر مبيعات اختبار',
                     'type', 'packaging', 'unit', 'قطعة'),
  jsonb_build_array(jsonb_build_object('name', 'كرتونة', 'factor', '50')));
insert into public.suppliers (name) values ('م1 مبيعات اختبار');
insert into public.customers (name) values ('ع1 مبيعات اختبار'), ('ع2 مبيعات اختبار');
insert into public.customers (name, is_active) values ('عميل معطل مبيعات اختبار', false);

select lives_ok($$select count(*) from public.sales_invoices$$, 'المستخدم يقرأ فواتير المبيعات');
select throws_ok(
  $$insert into public.sales_invoices (doc_no, doc_date, customer_id, total, journal_entry_id)
    values (1, '1990-01-01', pg_temp.cust('ع1 مبيعات اختبار'), 1, 1)$$,
  '42501', null, 'المستخدم لا يكتب فواتير المبيعات مباشرة'
);
select throws_ok(
  $$insert into public.sales_invoice_lines (invoice_id, item_id, unit_name, factor, qty, base_qty, unit_price,
      line_total, unit_cost, cost_total)
    values (1, pg_temp.item('S-DISH'), 'عبوة', 1, 1, 1, 1, 1, 0, 0)$$,
  '42501', null, 'المستخدم لا يكتب سطور فواتير المبيعات مباشرة'
);

-- ---------------------------------------------------------------------
-- 2) SPEC §11 الخطوات 1–4 (تهيئة)، ثم 5–8 بنتائجها
-- ---------------------------------------------------------------------
select public.post_opening_balances('1990-01-01', jsonb_build_array(
  pg_temp.line('1101', '100000', '0'), pg_temp.line('1501', '50000', '0'), pg_temp.line('3101', '0', '150000')));
select public.post_purchase_invoice('1990-01-10', pg_temp.supp('م1 مبيعات اختبار'), jsonb_build_array(
  pg_temp.pl('S-LABSA', '100', '40'), pg_temp.pl('S-SLES', '100', '50'), pg_temp.pl('S-SALT', '100', '5'),
  pg_temp.pl('S-BOTTLE', '500', '2')));
select public.post_voucher('payment', '1990-01-15', pg_temp.acc('1101'), 'supplier', pg_temp.supp('م1 مبيعات اختبار'), '5000');
select public.save_formula(null, 'سائل أطباق مبيعات اختبار', pg_temp.item('S-DISH'), '100', null, jsonb_build_array(
  pg_temp.fl('S-LABSA', '8'), pg_temp.fl('S-SLES', '6'), pg_temp.fl('S-SALT', '3'), pg_temp.fl('S-BOTTLE', '100')));
select public.post_production_order('1990-02-01', (select id from public.formulas where name = 'سائل أطباق مبيعات اختبار'),
  '2', '200', null, jsonb_build_array(pg_temp.fl('S-LABSA', '16'), pg_temp.fl('S-SLES', '12'), pg_temp.fl('S-SALT', '6'),
                                      pg_temp.fl('S-BOTTLE', '200')),
  '330', pg_temp.acc('1101'));

select lives_ok(
  $$select public.post_sales_invoice('1990-02-10', pg_temp.cust('ع1 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '150', '18')))$$,
  'الخطوة 5: فاتورة مبيعات آجل للعميل ع1: 150 عبوة × 18'
);
select results_eq(
  $$select s.doc_no - (select sales_no from pg_temp._base), s.total::text, s.paid_amount::text,
           s.receipt_voucher_id is null, e.source_type, e.source_id = s.id
    from public.sales_invoices s join public.journal_entries e on e.id = s.journal_entry_id
    where s.id = pg_temp.si(1)$$,
  $$values (1::bigint, '2700.00'::text, '0.00'::text, true, 'sale'::text, true)$$,
  'الفاتورة 2,700 آجل بالكامل بلا سند، مربوطة بقيدها'
);
select results_eq(
  $$select unit_name, factor::text, qty::text, base_qty::text, unit_price::text, line_total::text, unit_cost::text,
           cost_total::text
    from public.sales_invoice_lines where invoice_id = pg_temp.si(1)$$,
  $$values ('عبوة'::text, '1.000000'::text, '150.000'::text, '150.000'::text, '18.00'::text, '2700.00'::text,
            '10.0000'::text, '1500.00'::text)$$,
  'السطر يحفظ الوحدة والسعر وتكلفة البيع (متوسط 10 وقت البيع)'
);
select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.si_entry(1))$$,
  $$values ('1201'::text, '2700.00'::text, '0.00'::text, 'ع1 مبيعات اختبار'::text),
           ('4101', '0.00', '2700.00', null), ('5101', '1500.00', '0.00', null), ('1303', '0.00', '1500.00', null)$$,
  'القيد: م العملاء (ع1) 2,700 / د إيرادات المبيعات 2,700، وم تكلفة المبيعات 1,500 / د مخزون منتج تام 1,500'
);
select results_eq(
  $$select kind, qty_out::text, total_cost::text, unit_cost::text, source_type, source_id = pg_temp.si(1)
    from public.stock_movements where journal_entry_id = pg_temp.si_entry(1)$$,
  $$values ('sale'::text, '150.000'::text, '1500.00'::text, '10.0000'::text, 'sale'::text, true)$$,
  'حركة صرف واحدة للمنتج بتكلفته'
);
select results_eq($$select * from pg_temp.stock('S-DISH')$$, $$values ('50.000'::text, '500.00'::text, '10.0000'::text)$$,
  'المنتج التام بعد البيع: 50 عبوة بتكلفة 10');

select public.post_voucher('receipt', '1990-02-15', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع1 مبيعات اختبار'), '1000');
select public.post_voucher('payment', '1990-02-20', pg_temp.acc('1101'), 'account', pg_temp.acc('6201'), '200');
select public.post_journal_entry('1990-02-28', 'إهلاك', 'adjustment', jsonb_build_array(
  pg_temp.line('6801', '500', '0'), pg_temp.line('1509', '0', '500')));

select results_eq(
  $$select code, debit, credit from public.trial_balance('1990-02-28')$$,
  $$values ('1101'::text, '95470.00'::text, '0.00'::text), ('1201', '1700.00', '0.00'), ('1301', '8230.00', '0.00'),
           ('1302', '600.00', '0.00'), ('1303', '500.00', '0.00'), ('1501', '50000.00', '0.00'),
           ('1509', '0.00', '500.00'), ('2101', '0.00', '5500.00'), ('3101', '0.00', '150000.00'),
           ('4101', '0.00', '2700.00'), ('5101', '1500.00', '0.00'), ('6201', '200.00', '0.00'),
           ('6801', '500.00', '0.00')$$,
  'SPEC §11 قبل الإقفال: الخزينة 95,470 والعملاء 1,700 والمخزون 8,230/600/500 والموردون 5,500'
);
select results_eq(
  $$select sum(debit::numeric)::text, sum(credit::numeric)::text from public.trial_balance('1990-02-28')$$,
  $$values ('158700.00'::text, '158700.00'::text)$$,
  'ميزان المراجعة متوازن: 158,700 = 158,700'
);
select results_eq(
  $$select item_code, qty, sales, cost, profit, margin, invoices from public.item_profit('1990-01-01', '1990-02-28')$$,
  $$values ('S-DISH'::text, '150.000'::text, '2700.00'::text, '1500.00'::text, '1200.00'::text, '44.44'::text, 1::bigint)$$,
  'أرباح الأصناف: كمية 150، مبيعات 2,700، تكلفة 1,500، ربح 1,200، هامش 44.44%'
);
select results_eq(
  $$select balance from public.party_balances('customer') where party_id = pg_temp.cust('ع1 مبيعات اختبار')$$,
  $$values ('1700.00'::text)$$,
  'رصيد العميل ع1 = 1,700'
);

-- ---------------------------------------------------------------------
-- 3) الرفض: لا فاتورة ولا قيد ولا حركة ولا سند ولا رقم
-- ---------------------------------------------------------------------
reset role;
create temp table _snap as select * from pg_temp.state();
set local role authenticated;
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '51', '18')))$$,
  'P0001', 'الكمية المطلوبة من الصنف S-DISH - سائل أطباق مبيعات اختبار هي 51 عبوة والمتاح 50 عبوة فقط (النقص 1)',
  'بيع أكثر من 50 عبوة مرفوض مع توضيح النقص'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '4', '200', 'كرتونة'), pg_temp.sl('S-DISH', '3', '18')))$$,
  'P0001', 'الكمية المطلوبة من الصنف S-DISH - سائل أطباق مبيعات اختبار هي 51 عبوة والمتاح 50 عبوة فقط (النقص 1)',
  'الرصيد يُفحص لكل الصنف بكل وحداته معًا (4 كراتين + 3 عبوات = 51)'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-LABSA', '1', '50')))$$,
  'P0001', 'السطر 1: فاتورة المبيعات للمنتج التام فقط، والصنف S-LABSA - LABSA مبيعات اختبار ليس منتجًا تامًا',
  'بيع خام مرفوض'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '18'), pg_temp.sl('S-DISH', '2', '18')))$$,
  'P0001', 'السطر 2: الصنف S-DISH - سائل أطباق مبيعات اختبار بنفس الوحدة مكرر في الفاتورة',
  'الصنف لا يتكرر بنفس الوحدة'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('عميل معطل مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '18')))$$,
  'P0001', 'اختر عميلًا نشطًا',
  'عميل معطّل مرفوض'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'), '[]'::jsonb)$$,
  'P0001', 'أضف صنفًا واحدًا على الأقل',
  'فاتورة بلا سطور مرفوضة'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '18')), null, '18.01', pg_temp.acc('1101'))$$,
  'P0001', 'المقبوض الآن 18.01 أكبر من إجمالي الفاتورة 18.00',
  'المقبوض أكبر من الإجمالي مرفوض'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '18')), null, '5')$$,
  'P0001', 'اختر الخزينة أو البنك المقبوض فيه',
  'مقبوض بلا خزينة مرفوض'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '18.005')))$$,
  'P0001', 'السطر 1: سعر البيع لا يزيد عن خانتين عشريتين',
  'سعر البيع بثلاث خانات مرفوض'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '')))$$,
  'P0001', 'السطر 1: سعر البيع مطلوب',
  'سعر البيع مطلوب'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '0.001', '1', 'عينة')))$$,
  'P0001', 'السطر 1: الكمية بالوحدة الأساسية (0.000125) لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة',
  'تحويل غير دقيق للوحدة الأساسية مرفوض (بلا تقريب صامت)'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '400', 'شوال')))$$,
  'P0001', 'السطر 1: الوحدة شوال معطّلة',
  'وحدة معطّلة مرفوضة'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(jsonb_build_object('item_id', pg_temp.item('S-DISH'),
        'unit_id', pg_temp.unit('S-BOTTLE', 'كرتونة'), 'qty', '1', 'unit_price', '1')))$$,
  'P0001', 'السطر 1: الوحدة المختارة ليست من وحدات هذا الصنف',
  'وحدة صنف آخر مرفوضة'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '0.001', '0.01')))$$,
  'P0001', 'السطر 1: إجمالي السطر يجب أن يكون أكبر من صفر',
  'إجمالي سطر صفر مرفوض'
);
select throws_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '18')), null, '5', pg_temp.acc('1501'))$$,
  'P0001', 'اختر خزينة أو بنكًا',
  'الفشل في سند القبض بعد قيد الفاتورة يُرفض كله'
);
reset role;
select results_eq(
  $$select * from pg_temp.state()$$,
  $$select * from _snap$$,
  'المحاولات المرفوضة لم تترك فاتورة ولا قيدًا ولا حركة ولا سندًا ولم تستهلك أرقامًا'
);
set local role authenticated;

-- ---------------------------------------------------------------------
-- 4) البيع بالوحدات والتحصيل الجزئي والكامل
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '2', '200', 'كرتونة'), pg_temp.sl('S-DISH', '5', '18')),
      'كراتين وقطع', '200', pg_temp.acc('1101'))$$,
  'فاتورة بكرتونتين (24 عبوة) + 5 عبوات، مقبوض منها 200 (تحصيل جزئي)'
);
select results_eq(
  $$select unit_name, factor::text, qty::text, base_qty::text, unit_price::text, line_total::text, unit_cost::text,
           cost_total::text
    from public.sales_invoice_lines where invoice_id = pg_temp.si(2) order by id$$,
  $$values ('كرتونة'::text, '12.000000'::text, '2.000'::text, '24.000'::text, '200.00'::text, '400.00'::text,
            '10.0000'::text, '240.00'::text),
           ('عبوة', '1.000000', '5.000', '5.000', '18.00', '90.00', '10.0000', '50.00')$$,
  'السعر لوحدة البيع، والتكلفة بالوحدة الأساسية (24 و5 عبوات بمتوسط 10)'
);
select results_eq(
  $$select kind, qty_out::text, total_cost::text from public.stock_movements where journal_entry_id = pg_temp.si_entry(2)$$,
  $$values ('sale'::text, '29.000'::text, '290.00'::text)$$,
  'الخصم بالوحدة الأساسية: حركة واحدة 29 عبوة للصنف بكل وحداته'
);
select results_eq(
  $$select s.total::text, s.paid_amount::text, v.kind, v.doc_no - (select receipt_no from pg_temp._base), v.amount::text,
           v.notes, v.doc_date = s.doc_date
    from public.sales_invoices s join public.vouchers v on v.id = s.receipt_voucher_id
    where s.id = pg_temp.si(2)$$,
  $$values ('490.00'::text, '200.00'::text, 'receipt'::text, 2::bigint, '200.00'::text,
            'تحصيل جزئي لفاتورة مبيعات رقم ' || ((select sales_no from pg_temp._base) + 2), true)$$,
  'سند قبض بالمقبوض فقط (200) مربوط بالفاتورة وبنفس تاريخها'
);
select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.si_entry(2))$$,
  $$values ('1201'::text, '490.00'::text, '0.00'::text, 'ع2 مبيعات اختبار'::text),
           ('4101', '0.00', '490.00', null), ('5101', '290.00', '0.00', null), ('1303', '0.00', '290.00', null)$$,
  'قيد الفاتورة بكامل الإجمالي على العميل'
);
select lives_ok(
  $$select public.post_sales_invoice('1990-03-02', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '18')), null, '18', pg_temp.acc('1102'))$$,
  'فاتورة مقبوضة بالكامل في البنك'
);
select results_eq(
  $$select v.amount::text, v.notes, a.code
    from public.sales_invoices s join public.vouchers v on v.id = s.receipt_voucher_id
    join public.accounts a on a.id = v.treasury_account_id
    where s.id = pg_temp.si(3)$$,
  $$values ('18.00'::text, 'تحصيل فاتورة مبيعات رقم ' || ((select sales_no from pg_temp._base) + 3), '1102'::text)$$,
  'تحصيل كامل: سند قبض بالإجمالي في البنك'
);
select results_eq(
  $$select balance from public.party_balances('customer') where party_id = pg_temp.cust('ع2 مبيعات اختبار')$$,
  $$values ('290.00'::text)$$,
  'رصيد العميل ع2 = 490 − 200 + 18 − 18 = 290'
);

-- ---------------------------------------------------------------------
-- 5) تكلفة المبيعات التاريخية: إنتاج لاحق بتكلفة مختلفة لا يغيّر فاتورة سابقة
-- ---------------------------------------------------------------------
select public.post_production_order('1990-03-05', (select id from public.formulas where name = 'سائل أطباق مبيعات اختبار'),
  '1', '100', null, jsonb_build_array(pg_temp.fl('S-LABSA', '8'), pg_temp.fl('S-SLES', '6'), pg_temp.fl('S-SALT', '3'),
                                      pg_temp.fl('S-BOTTLE', '100')));
select results_eq($$select * from pg_temp.stock('S-DISH')$$, $$values ('120.000'::text, '1035.00'::text, '8.6250'::text)$$,
  'إنتاج لاحق بتكلفة 8.35 يغيّر المتوسط إلى 8.625');
select lives_ok(
  $$select public.post_sales_invoice('1990-03-06', pg_temp.cust('ع1 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '200', 'كرتونة'), pg_temp.sl('S-DISH', '1', '18')))$$,
  'بيع كرتونة + عبوة بالمتوسط الجديد'
);
select results_eq(
  $$select unit_name, base_qty::text, unit_cost::text, cost_total::text
    from public.sales_invoice_lines where invoice_id = pg_temp.si(4) order by id$$,
  $$values ('كرتونة'::text, '12.000'::text, '8.6254'::text, '103.50'::text), ('عبوة', '1.000', '8.6254', '8.63')$$,
  'تكلفة الصنف 112.13 (13 × 1,035 ÷ 120) تُوزَّع على سطوره ومجموعها بالضبط'
);
select results_eq(
  $$select unit_cost::text, cost_total::text from public.sales_invoice_lines where invoice_id = pg_temp.si(1)$$,
  $$values ('10.0000'::text, '1500.00'::text)$$,
  'تكلفة الفاتورة الأولى المحفوظة لم تتغير بالمتوسط الجديد'
);

-- ---------------------------------------------------------------------
-- 6) الإلغاء
-- ---------------------------------------------------------------------
select lives_ok($$select public.cancel_sales_invoice(pg_temp.si(1))$$, 'إلغاء فاتورة الخطوة 5');
select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.reversal_of(pg_temp.si_entry(1)))$$,
  $$values ('1201'::text, '0.00'::text, '2700.00'::text, 'ع1 مبيعات اختبار'::text),
           ('4101', '2700.00', '0.00', null), ('5101', '0.00', '1500.00', null), ('1303', '1500.00', '0.00', null)$$,
  'قيد عكسي لكل سطور الفاتورة'
);
select results_eq(
  $$select r.kind, r.qty_in::text, r.total_cost::text, r.unit_cost::text, r.source_type, r.movement_date::text,
           r.reverses_movement_id = m.id
    from public.stock_movements r join public.stock_movements m on m.journal_entry_id = pg_temp.si_entry(1)
    where r.journal_entry_id = pg_temp.reversal_of(pg_temp.si_entry(1))$$,
  $$values ('reversal'::text, '150.000'::text, '1500.00'::text, '10.0000'::text, 'sale'::text, '1990-02-10'::text, true)$$,
  '150 عبوة ترجع للمخزون بتكلفة 10 للوحدة (بتاريخ الفاتورة)'
);
select results_eq($$select * from pg_temp.stock('S-DISH')$$, $$values ('257.000'::text, '2422.87'::text, '9.4275'::text)$$,
  'رصيد المنتج بعد الإرجاع: 107 + 150 = 257');
select throws_ok(
  $$select public.cancel_sales_invoice(pg_temp.si(1))$$,
  'P0001', 'فاتورة المبيعات رقم ' || ((select sales_no from pg_temp._base) + 1) || ' ملغاة بالفعل',
  'لا تُلغى الفاتورة مرتين'
);
select throws_ok(
  $$select public.cancel_journal_entry(pg_temp.si_entry(2))$$,
  'P0001', 'هذا القيد يُلغى من خلال المستند المرتبط به',
  'قيد المبيعات لا يُلغى من شاشة القيود'
);

-- إلغاء فاتورة مقبوض منها جزء: السند يبقى، والمبلغ رصيد دائن للعميل، والفاتورة المصححة لا تُحصَّل مرتين
select lives_ok($$select public.cancel_sales_invoice(pg_temp.si(2))$$, 'إلغاء الفاتورة المقبوض منها 200');
select results_eq(
  $$select (select count(*) from public.journal_entries r where r.reverses_entry_id = v.journal_entry_id)
    from public.sales_invoices s join public.vouchers v on v.id = s.receipt_voucher_id where s.id = pg_temp.si(2)$$,
  $$values (0::bigint)$$,
  'سند القبض لا يُلغى مع الفاتورة'
);
select results_eq(
  $$select balance from public.party_balances('customer') where party_id = pg_temp.cust('ع2 مبيعات اختبار')$$,
  $$values ('-200.00'::text)$$,
  'بعد الإلغاء: المقبوض 200 رصيد دائن (دفعة مقدمة) للعميل ع2'
);
select lives_ok(
  $$select public.post_sales_invoice('1990-03-01', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '2', '200', 'كرتونة'), pg_temp.sl('S-DISH', '5', '18')), 'تصحيح')$$,
  'الفاتورة المصححة بمقبوض صفر'
);
select results_eq(
  $$select s.paid_amount::text, s.receipt_voucher_id is null,
           (select balance from public.party_balances('customer') where party_id = s.customer_id)
    from public.sales_invoices s where s.id = pg_temp.si(5)$$,
  $$values ('0.00'::text, true, '290.00'::text)$$,
  'الفاتورة المصححة بلا سند جديد، ورصيد العميل 290 (السداد السابق خُصم تلقائيًا)'
);
select results_eq(
  $$select unit_cost::text, cost_total::text from public.sales_invoice_lines where invoice_id = pg_temp.si(5) order by id$$,
  $$values ('9.4855'::text, '227.65'::text), ('9.4855', '47.43')$$,
  'توزيع تكلفة 275.08 (29 × 2,712.87 ÷ 286) على السطرين بالتراكم: 227.65 + 47.43'
);

-- ---------------------------------------------------------------------
-- 7) تقرير أرباح الأصناف وقائمة الفواتير
-- ---------------------------------------------------------------------
select results_eq(
  $$select item_code, qty, sales, cost, profit, margin, invoices from public.item_profit('1990-01-01', '1990-12-31')$$,
  $$values ('S-DISH'::text, '43.000'::text, '726.00'::text, '397.21'::text, '328.79'::text, '45.29'::text, 3::bigint)$$,
  'الفواتير الملغاة خارج التقرير: 1 + 13 + 29 عبوة، مبيعات 726، تكلفة 397.21'
);
select results_eq(
  $$select item_code, sales, cost, profit, margin
    from public.item_profit('1990-01-01', '1990-12-31', null, pg_temp.cust('ع1 مبيعات اختبار'))$$,
  $$values ('S-DISH'::text, '218.00'::text, '112.13'::text, '105.87'::text, '48.56'::text)$$,
  'فلتر العميل'
);
select results_eq(
  $$select doc_no - (select sales_no from pg_temp._base), unit_name, qty, base_qty, unit_price, line_total, cost_total, profit
    from public.item_profit_lines(pg_temp.item('S-DISH'), '1990-01-01', '1990-12-31')$$,
  $$values (4::bigint, 'كرتونة'::text, '1.000'::text, '12.000'::text, '200.00'::text, '200.00'::text, '103.50'::text, '96.50'::text),
           (4, 'عبوة', '1.000', '1.000', '18.00', '18.00', '8.63', '9.37'),
           (3, 'عبوة', '1.000', '1.000', '18.00', '18.00', '10.00', '8.00'),
           (5, 'كرتونة', '2.000', '24.000', '200.00', '400.00', '227.65', '172.35'),
           (5, 'عبوة', '5.000', '5.000', '18.00', '90.00', '47.43', '42.57')$$,
  'الضغط على الصنف يعرض سطور الفواتير غير الملغاة'
);
select results_eq(
  $$select (select sum(profit::numeric) from public.item_profit())::text,
           (select sum(l.credit - l.debit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
            where l.account_id = pg_temp.acc('4101') and e.id > (select entry_id from pg_temp._base))::text,
           (select sum(l.debit - l.credit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
            where l.account_id = pg_temp.acc('5101') and e.id > (select entry_id from pg_temp._base))::text$$,
  $$values ('328.79'::text, '726.00'::text, '397.21'::text)$$,
  'مجموع أرباح الأصناف = إيرادات المبيعات (726) − تكلفة المبيعات (397.21)'
);
select results_eq(
  $$select doc_no - (select sales_no from pg_temp._base), total, paid_amount, cost_total, gross_profit, is_cancelled
    from public.sales_invoice_list('1990-01-01', '1990-12-31')$$,
  $$values (4::bigint, '218.00'::text, '0.00'::text, '112.13'::text, '105.87'::text, false),
           (3, '18.00', '18.00', '10.00', '8.00', false),
           (5, '490.00', '0.00', '275.08', '214.92', false),
           (2, '490.00', '200.00', '290.00', '200.00', true),
           (1, '2700.00', '0.00', '1500.00', '1200.00', true)$$,
  'قائمة الفواتير: المقبوض عند الاعتماد والتكلفة ومجمل الربح والملغاة'
);
select results_eq(
  $$select count(*) from public.sales_invoice_list(null, null, 'ع1 مبيعات')$$,
  $$values (2::bigint)$$,
  'البحث باسم العميل'
);

-- ---------------------------------------------------------------------
-- 8) القيود اليدوية على 4101/5101 ممنوعة، وحسابا المبيعات ثابتان بعد القيود
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.post_journal_entry('1990-03-10', 'إيراد يدوي', 'manual', jsonb_build_array(
      pg_temp.line('1101', '10', '0'), pg_temp.line('4101', '0', '10')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 4101 - إيرادات المبيعات. إيرادات المبيعات وتكلفتها تتحرك من فواتير المبيعات فقط (لمطابقة تقرير أرباح الأصناف)',
  'قيد يدوي على إيرادات المبيعات مرفوض'
);
select throws_ok(
  $$select public.post_journal_entry('1990-03-10', 'تكلفة يدوية', 'adjustment', jsonb_build_array(
      pg_temp.line('5101', '10', '0'), pg_temp.line('1101', '0', '10')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 5101 - تكلفة البضاعة المباعة. إيرادات المبيعات وتكلفتها تتحرك من فواتير المبيعات فقط (لمطابقة تقرير أرباح الأصناف)',
  'قيد تسوية على تكلفة المبيعات مرفوض'
);
select lives_ok(
  $$select public.post_journal_entry('1990-03-10', 'إيراد آخر', 'manual', jsonb_build_array(
      pg_temp.line('1101', '10', '0'), pg_temp.line('4201', '0', '10')))$$,
  'الإيرادات الأخرى (4201) تقبل القيد اليدوي'
);
reset role;
select throws_ok(
  $$update public.system_accounts set account_id = pg_temp.acc('4201') where key = 'sales_revenue'$$,
  'P0001', 'لا يمكن تغيير حساب إيرادات المبيعات بعد وجود قيود على الحساب الحالي أو الجديد',
  'حساب إيرادات المبيعات ثابت بعد القيود'
);
select throws_ok(
  $$update public.system_accounts set account_id = pg_temp.acc('5201') where key = 'cogs'$$,
  'P0001', 'لا يمكن تغيير حساب تكلفة البضاعة المباعة بعد وجود قيود على الحساب الحالي أو الجديد',
  'حساب تكلفة المبيعات ثابت بعد القيود'
);

-- المستندات ثابتة
select throws_ok(
  $$update public.sales_invoices set notes = 'تعديل' where id = pg_temp.si(3)$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'لا تعديل لفاتورة مبيعات معتمدة'
);
select throws_ok(
  $$delete from public.sales_invoice_lines where invoice_id = pg_temp.si(3)$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'لا حذف لسطور فاتورة معتمدة'
);
select throws_ok(
  $$truncate public.sales_invoices, public.sales_invoice_lines$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'لا تفريغ لجداول المبيعات'
);
set local role authenticated;

-- معامل الوحدة ثابت بعد البيع بها، والاسم المحفوظ في السطر لا يتغير بإعادة التسمية
select throws_ok(
  $$select public.save_item(pg_temp.card('S-DISH', 'سائل أطباق مبيعات اختبار'), jsonb_build_array(
      jsonb_build_object('id', pg_temp.unit('S-DISH', 'كرتونة'), 'name', 'كرتونة', 'factor', '10', 'sale_price', '200'),
      jsonb_build_object('id', pg_temp.unit('S-DISH', 'عينة'), 'name', 'عينة', 'factor', '0.125'),
      jsonb_build_object('id', pg_temp.unit('S-DISH', 'شوال'), 'name', 'شوال', 'factor', '24', 'is_active', false)))$$,
  'P0001', 'لا يمكن تغيير معامل تحويل الوحدة كرتونة لأنها استُخدمت في مستندات أو وصفات',
  'معامل وحدة بيعت بها لا يتغير'
);
select lives_ok(
  $$select public.save_item(pg_temp.card('S-DISH', 'سائل أطباق مبيعات اختبار'), jsonb_build_array(
      jsonb_build_object('id', pg_temp.unit('S-DISH', 'كرتونة'), 'name', 'كرتونة 12', 'factor', '12', 'sale_price', '210'),
      jsonb_build_object('id', pg_temp.unit('S-DISH', 'عينة'), 'name', 'عينة', 'factor', '0.125'),
      jsonb_build_object('id', pg_temp.unit('S-DISH', 'شوال'), 'name', 'شوال', 'factor', '24', 'is_active', false)))$$,
  'إعادة تسمية الوحدة وتغيير سعرها مسموح'
);
select results_eq(
  $$select distinct unit_name from public.sales_invoice_lines where unit_id = pg_temp.unit('S-DISH', 'كرتونة 12')$$,
  $$values ('كرتونة'::text)$$,
  'الفواتير المعتمدة تحتفظ باسم الوحدة وقت البيع'
);

-- ---------------------------------------------------------------------
-- 9) قفل الفترة والترقيم
-- ---------------------------------------------------------------------
select public.post_sales_invoice('1990-03-20', pg_temp.cust('ع2 مبيعات اختبار'),
  jsonb_build_array(pg_temp.sl('S-DISH', '1', '18')));
reset role;
update public.settings set lock_date = '1990-03-31' where id = 1;
set local role authenticated;
select throws_ok(
  $$select public.post_sales_invoice('1990-03-25', pg_temp.cust('ع2 مبيعات اختبار'),
      jsonb_build_array(pg_temp.sl('S-DISH', '1', '18')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 25/03/1990 لأن الفترة مقفولة حتى 31/03/1990',
  'فاتورة مبيعات في فترة مقفولة مرفوضة'
);
select throws_ok(
  $$select public.cancel_sales_invoice(pg_temp.si(6))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 20/03/1990 لأن الفترة مقفولة حتى 31/03/1990',
  'إلغاء فاتورة في فترة مقفولة مرفوض'
);
select results_eq(
  $$select doc_no - (select sales_no from pg_temp._base) from public.sales_invoices
    where doc_no > (select sales_no from pg_temp._base) order by doc_no$$,
  $$values (1::bigint), (2), (3), (4), (5), (6)$$,
  'ترقيم الفواتير متسلسل بلا فجوات رغم المحاولات المرفوضة'
);

-- ---------------------------------------------------------------------
-- 10) المطابقة
-- ---------------------------------------------------------------------
select lives_ok($$set constraints all immediate$$, 'كل ما سبق يجتاز فحوص الـ commit بصلاحية المستخدم');
set constraints all deferred;
select is_empty(
  $$select s.item_id
    from public.item_stock s
    left join (select item_id, sum(qty_in - qty_out) as qty,
                      sum(case when qty_in > 0 then total_cost else -total_cost end) as value
               from public.stock_movements group by item_id) m on m.item_id = s.item_id
    where s.qty <> coalesce(m.qty, 0) or s.value <> coalesce(m.value, 0)$$,
  'رصيد كل صنف = مجموع حركاته'
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
  $$values ('1301'::text, '7595.00'::text, '7595.00'::text),
           ('1302', '400.00', '400.00'),
           ('1303', '2428.30', '2428.30')$$,
  'كل حساب مخزون في الأستاذ = قيمة أصناف نوعه'
);
select results_eq(
  $$select (select coalesce(sum(balance::numeric), 0) from public.party_balances('customer'))::text,
           (select coalesce(sum(debit - credit), 0) from public.journal_lines where account_id = pg_temp.acc('1201'))::text$$,
  $$values ('-474.00'::text, '-474.00'::text)$$,
  'مجموع أرصدة العملاء = رصيد حساب العملاء'
);
select results_eq(
  $$select sum(debit::numeric) = sum(credit::numeric) from public.trial_balance()$$,
  $$values (true)$$,
  'ميزان المراجعة متوازن'
);

reset role;
select * from finish();
rollback;
