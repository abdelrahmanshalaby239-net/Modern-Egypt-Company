-- =====================================================================
-- اختبارات التصنيع (المرحلة 5): الوصفات، تسجيل الإنتاج (SPEC §11 الخطوة 4)، الوحدات في الوصفة والإنتاج،
-- الهالك، التكاليف الإضافية وحسابها، رفض النقص والمدخلات الخطأ، الإلغاء (المواد ترجع والمنتج يخرج،
-- الرصيد السالب مرفوض، فرق التكلفة على 5201)، قفل الفترة، الترقيم، التقرير، والمطابقة.
-- تعمل داخل transaction تُلغى في النهاية.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(62);

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
select (select last_no from public.doc_counters where kind = 'production_order') as production_no,
       (select last_no from public.doc_counters where kind = 'stock_adjustment') as adjustment_no;
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
create function pg_temp.supp(p_name text) returns bigint language sql stable as $$
  select id from public.suppliers where name = p_name;
$$;
create function pg_temp.formula(p_name text) returns bigint language sql stable as $$
  select id from public.formulas where name = p_name;
$$;
create function pg_temp.line(p_code text, p_debit text, p_credit text) returns jsonb language sql stable as $$
  select jsonb_build_object('account_id', (select id from public.accounts where code = p_code),
                            'debit', p_debit, 'credit', p_credit);
$$;
create function pg_temp.pl(p_code text, p_qty text, p_price text) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'qty', p_qty, 'unit_price', p_price);
$$;
-- سطر وصفة أو استهلاك بوحدة (فارغ = الوحدة الأساسية)
create function pg_temp.fl(p_code text, p_qty text, p_unit text default null) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'unit_id', pg_temp.unit(p_code, p_unit),
                            'qty_per_batch', p_qty, 'qty', p_qty);
$$;
create function pg_temp.po(p_n int) returns bigint language sql stable as $$
  select id from public.production_orders where doc_no = (select production_no from pg_temp._base) + p_n;
$$;
create function pg_temp.po_entry(p_n int) returns bigint language sql stable as $$
  select journal_entry_id from public.production_orders where id = pg_temp.po(p_n);
$$;
create function pg_temp.reversal_of(p_entry bigint) returns bigint language sql stable as $$
  select id from public.journal_entries where reverses_entry_id = p_entry;
$$;
create function pg_temp.entry_lines(p_entry bigint)
returns table (code text, debit text, credit text) language sql stable as $$
  select a.code, l.debit::text, l.credit::text
  from public.journal_lines l join public.accounts a on a.id = l.account_id
  where l.entry_id = p_entry order by l.id;
$$;
create function pg_temp.card(p_code text, p_name text, p_type text, p_unit text) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', pg_temp.item(p_code), 'code', p_code, 'name', p_name, 'type', p_type, 'unit', p_unit);
$$;
create function pg_temp.state()
returns table (orders bigint, lines bigint, entries bigint, movements bigint, production_no bigint, journal_no bigint)
language sql stable as $$
  select (select count(*) from public.production_orders), (select count(*) from public.production_lines),
         (select count(*) from public.journal_entries), (select count(*) from public.stock_movements),
         (select last_no from public.doc_counters where kind = 'production_order'),
         (select last_no from public.doc_counters where kind = 'journal');
$$;

-- ---------------------------------------------------------------------
-- 1) الصلاحيات
-- ---------------------------------------------------------------------
set local role anon;
select throws_ok($$select * from public.formulas$$, '42501', null, 'anon لا يقرأ الوصفات');
select throws_ok($$select * from public.production_orders$$, '42501', null, 'anon لا يقرأ أوامر الإنتاج');
select throws_ok(
  $$select public.post_production_order('1990-02-01', 1, '1', '1', null, '[]'::jsonb)$$,
  '42501', null, 'anon لا يسجّل إنتاجًا'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

-- البيانات الأساسية (SPEC §11): خامات وتعبئة ومنتجان تامان، ووحدات بديلة
insert into public.items (code, name, type, unit, sale_price, is_active) values
  ('M-LABSA', 'LABSA تصنيع اختبار', 'raw_material', 'كجم', null, true),
  ('M-SLES', 'SLES تصنيع اختبار', 'raw_material', 'كجم', null, true),
  ('M-SALT', 'ملح تصنيع اختبار', 'raw_material', 'كجم', null, true),
  ('M-BOTTLE', 'عبوة 1 لتر تصنيع اختبار', 'packaging', 'قطعة', null, true),
  ('M-DISH', 'سائل أطباق تصنيع اختبار', 'finished_good', 'عبوة', 18, true),
  ('M-GLASS', 'زجاج تصنيع اختبار', 'finished_good', 'عبوة', null, true),
  ('M-OLD', 'خام معطل تصنيع اختبار', 'raw_material', 'كجم', null, false);
select public.save_item(pg_temp.card('M-DISH', 'سائل أطباق تصنيع اختبار', 'finished_good', 'عبوة'),
  jsonb_build_array(jsonb_build_object('name', 'كرتونة', 'factor', '12')));
select public.save_item(pg_temp.card('M-BOTTLE', 'عبوة 1 لتر تصنيع اختبار', 'packaging', 'قطعة'),
  jsonb_build_array(jsonb_build_object('name', 'كرتونة', 'factor', '50')));
select public.save_item(pg_temp.card('M-LABSA', 'LABSA تصنيع اختبار', 'raw_material', 'كجم'),
  jsonb_build_array(jsonb_build_object('name', 'عبوة صغيرة', 'factor', '0.125')));
insert into public.suppliers (name) values ('م1 تصنيع اختبار');

select throws_ok(
  $$insert into public.formulas (name, finished_item_id, batch_qty) values ('مباشر', pg_temp.item('M-DISH'), 1)$$,
  '42501', null, 'المستخدم لا يكتب الوصفات مباشرة'
);
select throws_ok(
  $$insert into public.production_orders (doc_no, doc_date, formula_id, finished_item_id, batches, unit_name, factor,
      qty_produced, base_qty_produced, materials_cost, total_cost, unit_cost, journal_entry_id)
    values (1, '1990-01-01', 1, 1, 1, 'x', 1, 1, 1, 1, 1, 1, 1)$$,
  '42501', null, 'المستخدم لا يكتب أوامر الإنتاج مباشرة'
);

-- ---------------------------------------------------------------------
-- 2) الوصفات
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.save_formula(null, 'سائل أطباق تصنيع اختبار', pg_temp.item('M-DISH'), '100', null, jsonb_build_array(
      pg_temp.fl('M-LABSA', '8'), pg_temp.fl('M-SLES', '6'), pg_temp.fl('M-SALT', '3'), pg_temp.fl('M-BOTTLE', '100')))$$,
  'وصفة SPEC §11: دفعة 100 عبوة (LABSA 8، SLES 6، ملح 3، عبوات 100)'
);
select results_eq(
  $$select i.code, l.qty_per_batch::text, l.unit_id is null
    from public.formula_lines l join public.items i on i.id = l.item_id
    where l.formula_id = pg_temp.formula('سائل أطباق تصنيع اختبار') order by i.code collate "C"$$,
  $$values ('M-BOTTLE'::text, '100.000'::text, true), ('M-LABSA', '8.000', true), ('M-SALT', '3.000', true),
           ('M-SLES', '6.000', true)$$,
  'سطور الوصفة محفوظة بالوحدة الأساسية'
);
select lives_ok(
  $$select public.save_formula(null, 'سائل أطباق كراتين اختبار', pg_temp.item('M-DISH'), '10',
      pg_temp.unit('M-DISH', 'كرتونة'), jsonb_build_array(
        pg_temp.fl('M-LABSA', '9.6'), pg_temp.fl('M-BOTTLE', '2.4', 'كرتونة')))$$,
  'وصفة بالوحدات: الدفعة 10 كراتين، والعبوات 2.4 كرتونة'
);
select lives_ok(
  $$select public.save_formula(null, 'زجاج تصنيع اختبار', pg_temp.item('M-GLASS'), '10', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')))$$,
  'وصفة منتج ثانٍ'
);
select lives_ok(
  $$select public.save_formula(null, 'وصفة غير مستخدمة اختبار', pg_temp.item('M-GLASS'), '1', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')))$$,
  'وصفة لن تُستخدم'
);
select throws_ok(
  $$select public.save_formula(null, 'وصفة خطأ', pg_temp.item('M-LABSA'), '1', null, jsonb_build_array(pg_temp.fl('M-SALT', '1')))$$,
  'P0001', 'الوصفة تنتج منتجًا تامًا فقط، والصنف M-LABSA - LABSA تصنيع اختبار ليس منتجًا تامًا',
  'الوصفة تنتج منتجًا تامًا فقط'
);
select throws_ok(
  $$select public.save_formula(null, 'وصفة خطأ', pg_temp.item('M-DISH'), '1', null, jsonb_build_array(pg_temp.fl('M-GLASS', '1')))$$,
  'P0001', 'السطر 1: مواد الوصفة خامات أو مواد تعبئة فقط، والصنف M-GLASS - زجاج تصنيع اختبار منتج تام',
  'مواد الوصفة خامات أو تعبئة فقط'
);
select throws_ok(
  $$select public.save_formula(null, 'وصفة خطأ', pg_temp.item('M-DISH'), '1', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1'), pg_temp.fl('M-SALT', '2')))$$,
  'P0001', 'السطر 2: الصنف M-SALT - ملح تصنيع اختبار مكرر في الوصفة',
  'المادة لا تتكرر في الوصفة'
);
select throws_ok(
  $$select public.save_formula(null, 'سائل أطباق تصنيع اختبار', pg_temp.item('M-DISH'), '1', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')))$$,
  'P0001', 'يوجد وصفة بنفس الاسم',
  'اسم الوصفة لا يتكرر'
);
select throws_ok(
  $$select public.save_formula(null, 'وصفة خطأ', pg_temp.item('M-DISH'), '1', null, jsonb_build_array(pg_temp.fl('M-OLD', '1')))$$,
  'P0001', 'السطر 1: الصنف M-OLD - خام معطل تصنيع اختبار معطّل',
  'مادة معطّلة مرفوضة في الوصفة'
);

-- ---------------------------------------------------------------------
-- 3) خطوات SPEC §11 من 1 إلى 4
-- ---------------------------------------------------------------------
select public.post_opening_balances('1990-01-01', jsonb_build_array(
  pg_temp.line('1101', '100000', '0'), pg_temp.line('1501', '50000', '0'), pg_temp.line('3101', '0', '150000')));
select public.post_purchase_invoice('1990-01-10', pg_temp.supp('م1 تصنيع اختبار'), jsonb_build_array(
  pg_temp.pl('M-LABSA', '100', '40'), pg_temp.pl('M-SLES', '100', '50'), pg_temp.pl('M-SALT', '100', '5'),
  pg_temp.pl('M-BOTTLE', '500', '2')));
select public.post_voucher('payment', '1990-01-15', pg_temp.acc('1101'), 'supplier', pg_temp.supp('م1 تصنيع اختبار'), '5000');

select lives_ok(
  $$select public.post_production_order('1990-02-01', pg_temp.formula('سائل أطباق تصنيع اختبار'), '2', '200', null,
      jsonb_build_array(pg_temp.fl('M-LABSA', '16'), pg_temp.fl('M-SLES', '12'), pg_temp.fl('M-SALT', '6'),
                        pg_temp.fl('M-BOTTLE', '200')),
      '330', pg_temp.acc('1101'), 'الخطوة 4')$$,
  'الخطوة 4: دفعتان (200 عبوة) + تكاليف إضافية 330 من الخزينة'
);
select results_eq(
  $$select o.doc_no - (select production_no from pg_temp._base), trim_scale(o.batches)::text, o.qty_produced::text,
           o.base_qty_produced::text, o.materials_cost::text, o.extra_cost::text, o.total_cost::text, o.unit_cost::text,
           e.source_type, e.source_id = o.id
    from public.production_orders o join public.journal_entries e on e.id = o.journal_entry_id
    where o.id = pg_temp.po(1)$$,
  $$values (1::bigint, '2'::text, '200.000'::text, '200.000'::text, '1670.00'::text, '330.00'::text, '2000.00'::text,
            '10.0000'::text, 'production'::text, true)$$,
  'أمر الإنتاج: المواد 1,670 والإجمالي 2,000 وتكلفة العبوة 10.0000، مربوط بقيده'
);
select results_eq(
  $$select i.code, l.qty::text, l.base_qty::text, trim_scale(l.standard_base_qty)::text, l.unit_cost::text, l.total_cost::text
    from public.production_lines l join public.items i on i.id = l.item_id
    where l.order_id = pg_temp.po(1) order by i.code collate "C"$$,
  $$values ('M-BOTTLE'::text, '200.000'::text, '200.000'::text, '200'::text, '2.0000'::text, '400.00'::text),
           ('M-LABSA', '16.000', '16.000', '16', '40.0000', '640.00'),
           ('M-SALT', '6.000', '6.000', '6', '5.0000', '30.00'),
           ('M-SLES', '12.000', '12.000', '12', '50.0000', '600.00')$$,
  'الاستهلاك: LABSA 16 (640)، SLES 12 (600)، ملح 6 (30)، عبوات 200 (400) بمتوسط التكلفة'
);
select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.po_entry(1))$$,
  $$values ('1303'::text, '2000.00'::text, '0.00'::text), ('1301', '0.00', '1270.00'), ('1302', '0.00', '400.00'),
           ('1101', '0.00', '330.00')$$,
  'القيد: م مخزون منتج تام 2,000 / د مخزون خام 1,270 + د مخزون تعبئة 400 + د الخزينة 330'
);
select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('M-LABSA', 'M-SLES', 'M-SALT', 'M-BOTTLE', 'M-DISH') order by i.code collate "C"$$,
  $$values ('M-BOTTLE'::text, '300.000'::text, '600.00'::text, '2.0000'::text),
           ('M-DISH', '200.000', '2000.00', '10.0000'),
           ('M-LABSA', '84.000', '3360.00', '40.0000'),
           ('M-SALT', '94.000', '470.00', '5.0000'),
           ('M-SLES', '88.000', '4400.00', '50.0000')$$,
  'المخزون بعد الإنتاج: LABSA 84، SLES 88، ملح 94، عبوات 300، منتج تام 200 بتكلفة 10'
);
select results_eq(
  $$select code, debit, credit from public.trial_balance('1990-02-01')$$,
  $$values ('1101'::text, '94670.00'::text, '0.00'::text), ('1301', '8230.00', '0.00'), ('1302', '600.00', '0.00'),
           ('1303', '2000.00', '0.00'), ('1501', '50000.00', '0.00'), ('2101', '0.00', '5500.00'),
           ('3101', '0.00', '150000.00')$$,
  'ميزان المراجعة بعد الخطوة 4 متوازن (155,500)'
);

-- ---------------------------------------------------------------------
-- 4) الإنتاج بالوحدات والهالك
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_production_order('1990-02-02', pg_temp.formula('سائل أطباق كراتين اختبار'), '1', '10',
      pg_temp.unit('M-DISH', 'كرتونة'),
      jsonb_build_array(pg_temp.fl('M-LABSA', '9.6'), pg_temp.fl('M-BOTTLE', '2.5', 'كرتونة')))$$,
  'إنتاج 10 كراتين (120 عبوة) باستهلاك 2.5 كرتونة عبوات (125 قطعة، والمعيار 120)'
);
select results_eq(
  $$select o.unit_name, trim_scale(o.factor)::text, o.qty_produced::text, o.base_qty_produced::text,
           o.materials_cost::text, o.unit_cost::text
    from public.production_orders o where o.id = pg_temp.po(2)$$,
  $$values ('كرتونة'::text, '12'::text, '10.000'::text, '120.000'::text, '634.00'::text, '5.2833'::text)$$,
  'الكمية المنتجة بالكرتونة (معامل 12) = 120 عبوة، وتكلفة العبوة 634 ÷ 120'
);
select results_eq(
  $$select i.code, l.unit_name, l.qty::text, l.base_qty::text, trim_scale(l.standard_base_qty)::text, l.total_cost::text
    from public.production_lines l join public.items i on i.id = l.item_id
    where l.order_id = pg_temp.po(2) order by i.code collate "C"$$,
  $$values ('M-BOTTLE'::text, 'كرتونة'::text, '2.500'::text, '125.000'::text, '120'::text, '250.00'::text),
           ('M-LABSA', 'كجم', '9.600', '9.600', '9.6', '384.00')$$,
  'سطر العبوات بالكرتونة: 125 قطعة فعليًا مقابل 120 معياريًا (هالك 5)'
);
select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('M-DISH', 'M-LABSA', 'M-BOTTLE') order by i.code collate "C"$$,
  $$values ('M-BOTTLE'::text, '175.000'::text, '350.00'::text, '2.0000'::text),
           ('M-DISH', '320.000', '2634.00', '8.2313'),
           ('M-LABSA', '74.400', '2976.00', '40.0000')$$,
  'المتوسط المرجح الجديد للمنتج التام = 2,634 ÷ 320'
);

-- ---------------------------------------------------------------------
-- 5) الرفض: لا قيد ولا حركة ولا رقم
-- ---------------------------------------------------------------------
reset role;
create temp table _snap as select * from pg_temp.state();
set local role authenticated;
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-LABSA', '100'), pg_temp.fl('M-BOTTLE', '100')))$$,
  'P0001', 'السطر 1: الكمية المطلوبة من الصنف M-LABSA - LABSA تصنيع اختبار هي 100 كجم والمتاح 74.4 كجم فقط (النقص 25.6)',
  'الإنتاج بخام ناقص يُرفض مع توضيح النقص'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-GLASS', '1')))$$,
  'P0001', 'السطر 1: مواد الإنتاج خامات أو مواد تعبئة فقط، والصنف M-GLASS - زجاج تصنيع اختبار منتج تام',
  'المنتج التام لا يُستهلك كمادة'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-LABSA', '1'), pg_temp.fl('M-LABSA', '2')))$$,
  'P0001', 'السطر 2: الصنف M-LABSA - LABSA تصنيع اختبار مكرر',
  'المادة لا تتكرر في أمر الإنتاج'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-OLD', '1')))$$,
  'P0001', 'السطر 1: الصنف M-OLD - خام معطل تصنيع اختبار معطّل',
  'المادة المعطّلة مرفوضة'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-LABSA', '1.001', 'عبوة صغيرة')))$$,
  'P0001', 'السطر 1: الكمية بالوحدة الأساسية (0.125125) لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة',
  'تحويل كمية الاستهلاك دقيق بلا تقريب'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '0', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')))$$,
  'P0001', 'الكمية المنتجة: الكمية يجب أن تكون أكبر من صفر',
  'الكمية المنتجة صفر مرفوضة'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '1',
      pg_temp.unit('M-BOTTLE', 'كرتونة'), jsonb_build_array(pg_temp.fl('M-SALT', '1')))$$,
  'P0001', 'الكمية المنتجة: الوحدة المختارة ليست من وحدات هذا الصنف',
  'وحدة الكمية المنتجة من وحدات المنتج فقط'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')), '50', null)$$,
  'P0001', 'اختر الحساب الدائن للتكاليف الإضافية',
  'تكاليف إضافية بلا حساب مرفوضة'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')), '50', pg_temp.acc('6101'))$$,
  'P0001', 'حساب التكاليف الإضافية يجب أن يكون خزينة أو بنكًا أو حساب خصوم (مثل المصروفات المستحقة)',
  'حساب مصروف مرفوض للتكاليف الإضافية (حتى لا تُحسب مرتين)'
);
select throws_ok(
  $$select public.post_production_order('1990-02-03', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')), '50', pg_temp.acc('2101'))$$,
  'P0001', 'حساب التكاليف الإضافية يجب أن يكون خزينة أو بنكًا أو حساب خصوم (مثل المصروفات المستحقة)',
  'حساب الموردين (حساب نظام) مرفوض للتكاليف الإضافية'
);
reset role;
select results_eq(
  $$select * from pg_temp.state()$$,
  $$select * from _snap$$,
  'المحاولات المرفوضة لم تترك أمرًا ولا قيدًا ولا حركة ولم تستهلك أرقامًا'
);
set local role authenticated;

-- ---------------------------------------------------------------------
-- 6) الإلغاء
-- ---------------------------------------------------------------------
select lives_ok($$select public.cancel_production_order(pg_temp.po(2))$$, 'إلغاء أمر إنتاج الكراتين');
select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.reversal_of(pg_temp.po_entry(2)))$$,
  $$values ('1303'::text, '0.00'::text, '634.00'::text), ('1301', '384.00', '0.00'), ('1302', '250.00', '0.00')$$,
  'القيد العكسي يعكس سطور الإنتاج بلا فرق تكلفة'
);
select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('M-DISH', 'M-LABSA', 'M-BOTTLE') order by i.code collate "C"$$,
  $$values ('M-BOTTLE'::text, '300.000'::text, '600.00'::text, '2.0000'::text),
           ('M-DISH', '200.000', '2000.00', '10.0000'),
           ('M-LABSA', '84.000', '3360.00', '40.0000')$$,
  'المواد رجعت بتكلفتها الأصلية والمنتج خرج، والأرصدة كما كانت'
);
select throws_ok(
  $$select public.cancel_production_order(pg_temp.po(2))$$,
  'P0001', 'أمر الإنتاج رقم ' || ((select production_no from pg_temp._base) + 2) || ' ملغى بالفعل',
  'لا يُلغى أمر الإنتاج مرتين'
);
select throws_ok(
  $$select public.cancel_journal_entry(pg_temp.po_entry(1))$$,
  'P0001', 'هذا القيد يُلغى من خلال المستند المرتبط به',
  'قيد الإنتاج لا يُلغى من شاشة القيود'
);

-- إنتاج بتكاليف إضافية على المصروفات المستحقة، ثم عجز في المنتج يمنع إلغاءه (رصيد سالب)
select lives_ok(
  $$select public.post_production_order('1990-03-01', pg_temp.formula('سائل أطباق تصنيع اختبار'), '1', '100', null,
      jsonb_build_array(pg_temp.fl('M-LABSA', '8'), pg_temp.fl('M-SLES', '6'), pg_temp.fl('M-SALT', '3'),
                        pg_temp.fl('M-BOTTLE', '100')),
      '100', pg_temp.acc('2201'))$$,
  'إنتاج دفعة بتكاليف إضافية 100 على المصروفات المستحقة (حساب خصوم)'
);
select results_eq(
  $$select o.materials_cost::text, o.total_cost::text, o.unit_cost::text, s.qty::text, s.value::text, s.avg_cost::text
    from public.production_orders o join public.item_stock s on s.item_id = o.finished_item_id
    where o.id = pg_temp.po(3)$$,
  $$values ('835.00'::text, '935.00'::text, '9.3500'::text, '300.000'::text, '2935.00'::text, '9.7833'::text)$$,
  'دفعة ثانية: المواد 835 + 100 = 935، والمتوسط الجديد 2,935 ÷ 300'
);
select public.post_stock_adjustment('1990-03-02', pg_temp.item('M-DISH'), '50');
select throws_ok(
  $$select public.cancel_production_order(pg_temp.po(3))$$,
  'P0001', 'لا يمكن الإلغاء: المتبقي من الصنف M-DISH - سائل أطباق تصنيع اختبار هو 50 فقط، وكمية المستند 100',
  'إلغاء إنتاج صُرف من منتجه ما يجعل الرصيد سالبًا مرفوض'
);

-- فرق التكلفة عند الإلغاء على فروقات الجرد (5201)
select public.post_production_order('1990-03-05', pg_temp.formula('زجاج تصنيع اختبار'), '1', '10', null,
  jsonb_build_array(pg_temp.fl('M-SALT', '1')), '95', pg_temp.acc('1101'));
select public.post_production_order('1990-03-06', pg_temp.formula('زجاج تصنيع اختبار'), '1', '10', null,
  jsonb_build_array(pg_temp.fl('M-SALT', '1')), '195', pg_temp.acc('2201'));
select public.post_stock_adjustment('1990-03-07', pg_temp.item('M-GLASS'), '10');
select lives_ok($$select public.cancel_production_order(pg_temp.po(5))$$, 'إلغاء الدفعة الأغلى بعد الصرف من المنتج');
select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.reversal_of(pg_temp.po_entry(5)))$$,
  $$values ('1303'::text, '0.00'::text, '200.00'::text), ('1301', '5.00', '0.00'), ('2201', '195.00', '0.00'),
           ('1303', '50.00', '0.00'), ('5201', '0.00', '50.00')$$,
  'القيد العكسي بالتكلفة الأصلية 200 + فرق 50 على فروقات الجرد، والتكاليف الإضافية تُعكس على حسابها'
);
select results_eq(
  $$select s.qty::text, s.value::text, s.avg_cost::text from public.item_stock s where s.item_id = pg_temp.item('M-GLASS')$$,
  $$values ('0.000'::text, '0.00'::text, '15.0000'::text)$$,
  'المنتج يخرج بقيمته المتبقية بالضبط (صفر بقيمة صفر)'
);

-- قفل الفترة (أمر قابل للإلغاء قبل القفل)
select public.post_production_order('1990-03-08', pg_temp.formula('زجاج تصنيع اختبار'), '1', '10', null,
  jsonb_build_array(pg_temp.fl('M-SALT', '1')));
reset role;
update public.settings set lock_date = '1990-03-31' where id = 1;
set local role authenticated;
select throws_ok(
  $$select public.cancel_production_order(pg_temp.po(6))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 08/03/1990 لأن الفترة مقفولة حتى 31/03/1990',
  'إلغاء أمر إنتاج في فترة مقفولة مرفوض'
);
select throws_ok(
  $$select public.post_production_order('1990-03-15', pg_temp.formula('زجاج تصنيع اختبار'), '1', '10', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 15/03/1990 لأن الفترة مقفولة حتى 31/03/1990',
  'إنتاج في فترة مقفولة مرفوض'
);
reset role;
update public.settings set lock_date = null where id = 1;
set local role authenticated;

-- ---------------------------------------------------------------------
-- 7) التقرير والوصفات المستخدمة والوحدات
-- ---------------------------------------------------------------------
select results_eq(
  $$select doc_no - (select production_no from pg_temp._base), item_code, qty_produced, unit_name, total_cost, is_cancelled
    from public.production_list(null, null, 'M-') order by doc_no$$,
  $$values (1::bigint, 'M-DISH'::text, '200.000'::text, 'عبوة'::text, '2000.00'::text, false),
           (2, 'M-DISH', '10.000', 'كرتونة', '634.00', true),
           (3, 'M-DISH', '100.000', 'عبوة', '935.00', false),
           (4, 'M-GLASS', '10.000', 'عبوة', '100.00', false),
           (5, 'M-GLASS', '10.000', 'عبوة', '200.00', true),
           (6, 'M-GLASS', '10.000', 'عبوة', '5.00', false)$$,
  'تقرير الإنتاج: كل الأوامر بحالة الإلغاء'
);
select results_eq(
  $$select (select count(*) from public.production_orders where doc_no > (select production_no from pg_temp._base)),
           (select max(doc_no) - (select production_no from pg_temp._base) from public.production_orders)$$,
  $$values (6::bigint, 6::bigint)$$,
  'ترقيم أوامر الإنتاج متسلسل بلا فجوات'
);
select results_eq(
  $$select kind, doc_no - (select production_no from pg_temp._base), qty_in
    from public.item_movements(pg_temp.item('M-DISH'), null, null) where kind = 'production' order by movement_id$$,
  $$values ('production'::text, 1::bigint, '200.000'::text), ('production', 2, '120.000'), ('production', 3, '100.000')$$,
  'حركة الصنف تعرض رقم أمر الإنتاج'
);
select throws_ok(
  $$select public.delete_formula(pg_temp.formula('سائل أطباق تصنيع اختبار'))$$,
  'P0001', 'لا يمكن حذف وصفة استُخدمت في الإنتاج. عطّلها بدل الحذف',
  'وصفة مستخدمة لا تُحذف'
);
select lives_ok(
  $$select public.delete_formula(pg_temp.formula('وصفة غير مستخدمة اختبار'))$$,
  'وصفة غير مستخدمة تُحذف مع سطورها'
);
select public.save_formula(pg_temp.formula('زجاج تصنيع اختبار'), 'زجاج تصنيع اختبار', pg_temp.item('M-GLASS'), '10', null,
  jsonb_build_array(pg_temp.fl('M-SALT', '1')), null, false);
select throws_ok(
  $$select public.post_production_order('1990-04-01', pg_temp.formula('زجاج تصنيع اختبار'), '1', '10', null,
      jsonb_build_array(pg_temp.fl('M-SALT', '1')))$$,
  'P0001', 'اختر وصفة نشطة',
  'الوصفة المعطّلة لا يُنتج بها'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('M-DISH', 'سائل أطباق تصنيع اختبار', 'finished_good', 'عبوة'),
      jsonb_build_array(jsonb_build_object('id', pg_temp.unit('M-DISH', 'كرتونة'), 'name', 'كرتونة', 'factor', '24')))$$,
  'P0001', 'لا يمكن تغيير معامل تحويل الوحدة كرتونة لأنها استُخدمت في مستندات أو وصفات',
  'معامل وحدة مستخدمة في وصفة وإنتاج لا يتغير'
);
select throws_ok(
  $$update public.items set type = 'raw_material' where code = 'M-GLASS'$$,
  'P0001', 'لا يمكن تغيير نوع صنف عليه حركات أو مستندات',
  'نوع منتج مستخدم في وصفة وإنتاج لا يتغير'
);

-- ---------------------------------------------------------------------
-- 8) المطابقة
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
  $$values ('1301'::text, '7585.00'::text, '7585.00'::text),
           ('1302', '400.00', '400.00'),
           ('1303', '494.17', '494.17')$$,
  'كل حساب مخزون في الأستاذ = قيمة أصناف نوعه'
);
select results_eq(
  $$select sum(o.total_cost)::text, sum(o.materials_cost + o.extra_cost)::text,
           (select sum(m.total_cost) from public.stock_movements m join public.production_orders p2
              on m.source_type = 'production' and m.source_id = p2.id and m.kind = 'production' and m.qty_in > 0)::text
    from public.production_orders o$$,
  $$values ('3874.00'::text, '3874.00'::text, '3874.00'::text)$$,
  'قيمة المنتج التام المضافة = المواد المصروفة + التكاليف الإضافية'
);
select results_eq(
  $$select sum(debit::numeric) = sum(credit::numeric) from public.trial_balance()$$,
  $$values (true)$$,
  'ميزان المراجعة متوازن'
);

reset role;
select * from finish();
rollback;
