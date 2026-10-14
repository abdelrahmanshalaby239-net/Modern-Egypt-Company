-- =====================================================================
-- اختبارات بطاقة الصنف (المرحلة 5): التصنيفات، التكلفة الافتراضية (منفصلة عن المتوسط الفعلي)،
-- الحد الأدنى، الباركود، الوحدات البديلة ومعاملاتها، الحفظ الذري، قفل الوحدة الأساسية والمعامل بعد
-- الاستخدام، المشتريات بوحدة بديلة، ومخزون أول المدة بالتكلفة المقترحة أو المعدّلة. تعمل داخل transaction تُلغى.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(54);

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

create function pg_temp.acc(p_code text) returns bigint language sql stable as $$
  select id from public.accounts where code = p_code;
$$;
create function pg_temp.item(p_code text) returns bigint language sql stable as $$
  select id from public.items where code = p_code;
$$;
create function pg_temp.unit(p_code text, p_name text) returns bigint language sql stable as $$
  select id from public.item_units where item_id = pg_temp.item(p_code) and name = p_name;
$$;
create function pg_temp.cat(p_name text) returns bigint language sql stable as $$
  select id from public.item_categories where name = p_name;
$$;
create function pg_temp.supp(p_name text) returns bigint language sql stable as $$
  select id from public.suppliers where name = p_name;
$$;
-- سطر شراء بوحدة (فارغ = الوحدة الأساسية)
create function pg_temp.pl(p_code text, p_qty text, p_price text, p_unit text default null) returns jsonb
language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'unit_id', pg_temp.unit(p_code, p_unit),
                            'qty', p_qty, 'unit_price', p_price);
$$;
create function pg_temp.ol(p_code text, p_qty text, p_cost text) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'qty', p_qty, 'unit_cost', p_cost);
$$;
-- بطاقة صنف للحفظ
create function pg_temp.card(p_code text, p_name text, p_type text, p_unit text, p_extra jsonb default '{}')
returns jsonb language sql stable as $$
  select jsonb_build_object('id', pg_temp.item(p_code), 'code', p_code, 'name', p_name, 'type', p_type,
                            'unit', p_unit) || p_extra;
$$;
create function pg_temp.stock(p_code text)
returns table (qty text, value text, avg_cost text) language sql stable as $$
  select qty::text, value::text, avg_cost::text from public.item_stock where item_id = pg_temp.item(p_code);
$$;

-- ---------------------------------------------------------------------
-- 1) الصلاحيات
-- ---------------------------------------------------------------------
set local role anon;
select throws_ok($$select * from public.item_units$$, '42501', null, 'anon لا يقرأ وحدات الأصناف');
select throws_ok($$select * from public.item_categories$$, '42501', null, 'anon لا يقرأ التصنيفات');
select throws_ok($$select public.save_item('{}'::jsonb, '[]'::jsonb)$$, '42501', null, 'anon لا يحفظ أصنافًا');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}', true);
select throws_ok(
  $$select public.save_item(jsonb_build_object('code', 'U-X', 'name', 'x', 'type', 'raw_material', 'unit', 'كجم'))$$,
  '42501', 'ليست لديك صلاحية لتنفيذ هذه العملية',
  'مستخدم بلا ملف لا يحفظ أصنافًا'
);
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

-- ---------------------------------------------------------------------
-- 2) التصنيفات
-- ---------------------------------------------------------------------
select lives_ok(
  $$insert into public.item_categories (name) values ('منظفات اختبار'), ('خامات اختبار'), ('تصنيف فارغ اختبار')$$,
  'المحاسب يضيف تصنيفات'
);
select throws_ok(
  $$insert into public.item_categories (name) values ('منظفات اختبار')$$,
  '23505', null, 'اسم التصنيف لا يتكرر'
);
select throws_ok(
  $$insert into public.item_categories (name) values ('  ')$$,
  '23514', null, 'اسم التصنيف مطلوب'
);

-- ---------------------------------------------------------------------
-- 3) حفظ بطاقة الصنف ووحداتها
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.save_item(
      pg_temp.card('U-DISH', 'سائل أطباق وحدات اختبار', 'finished_good', 'عبوة', jsonb_build_object(
        'category_id', pg_temp.cat('منظفات اختبار'), 'barcode', '6221000000017', 'sale_price', '18',
        'default_cost', '9.5', 'min_stock', '20')),
      jsonb_build_array(
        jsonb_build_object('name', 'كرتونة', 'factor', '12', 'sale_price', '210', 'is_default', true),
        jsonb_build_object('name', 'نصف كرتونة', 'factor', '6', 'sale_price', '108')))$$,
  'بطاقة منتج تام بتصنيف وباركود وتكلفة افتراضية وحد أدنى ووحدتين بديلتين'
);
select results_eq(
  $$select i.unit, i.sale_price::text, i.default_cost::text, i.min_stock::text, i.barcode,
           (select name from public.item_categories where id = i.category_id),
           (select name from public.item_units where id = i.default_sale_unit_id)
    from public.items i where i.id = pg_temp.item('U-DISH')$$,
  $$values ('عبوة'::text, '18.00'::text, '9.5000'::text, '20.000'::text, '6221000000017'::text,
            'منظفات اختبار'::text, 'كرتونة'::text)$$,
  'حقول البطاقة محفوظة، ووحدة البيع الافتراضية الكرتونة'
);
select results_eq(
  $$select name, trim_scale(factor)::text, sale_price::text, is_active
    from public.item_units where item_id = pg_temp.item('U-DISH') order by factor desc$$,
  $$values ('كرتونة'::text, '12'::text, '210.00'::text, true), ('نصف كرتونة', '6', '108.00', true)$$,
  'الوحدات البديلة بمعاملها وسعر بيعها'
);
select results_eq(
  $$select * from pg_temp.stock('U-DISH')$$,
  $$values ('0.000'::text, '0.00'::text, '0.0000'::text)$$,
  'التكلفة الافتراضية لا تُنشئ رصيدًا ولا متوسط تكلفة'
);

select lives_ok(
  $$select public.save_item(
      pg_temp.card('U-LABSA', 'LABSA وحدات اختبار', 'raw_material', 'كجم', jsonb_build_object(
        'category_id', pg_temp.cat('خامات اختبار'), 'default_cost', '38.5')),
      jsonb_build_array(
        jsonb_build_object('name', 'برميل', 'factor', '200'),
        jsonb_build_object('name', 'عبوة صغيرة', 'factor', '0.125'),
        jsonb_build_object('name', 'جركن قديم', 'factor', '20', 'is_active', false)))$$,
  'خام بوحدة أساسية كجم ووحدات بديلة (برميل 200، عبوة صغيرة 0.125، جركن معطّل)'
);
select lives_ok(
  $$select public.save_item(pg_temp.card('U-BOTTLE', 'عبوة فارغة وحدات اختبار', 'packaging', 'قطعة'),
      jsonb_build_array(jsonb_build_object('name', 'كرتونة', 'factor', '50')))$$,
  'مواد تعبئة بكرتونة 50 قطعة (اسم الوحدة يتكرر بين صنفين مختلفين)'
);
select lives_ok(
  $$select public.save_item(pg_temp.card('U-SALT', 'ملح وحدات اختبار', 'raw_material', 'كجم',
      jsonb_build_object('default_cost', '4')))$$,
  'صنف بلا وحدات بديلة'
);

-- ---------------------------------------------------------------------
-- 4) رفض المدخلات الخطأ (رسائل عربية) والحفظ الذري
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد', 'raw_material', 'كجم'),
      jsonb_build_array(jsonb_build_object('name', 'كيس', 'factor', '0')))$$,
  'P0001', 'الوحدة 1: معامل التحويل يجب أن يكون أكبر من صفر',
  'معامل تحويل صفر مرفوض'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد', 'raw_material', 'كجم'),
      jsonb_build_array(jsonb_build_object('name', 'كيس', 'factor', '1.1234567')))$$,
  'P0001', 'الوحدة 1: معامل التحويل لا يزيد عن ست خانات عشرية',
  'معامل تحويل بسبع خانات مرفوض'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد', 'raw_material', 'كجم'),
      jsonb_build_array(jsonb_build_object('name', 'كجم', 'factor', '1')))$$,
  'P0001', 'الوحدة 1: اسم الوحدة "كجم" مكرر',
  'اسم الوحدة البديلة لا يساوي الوحدة الأساسية'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد', 'finished_good', 'عبوة'),
      jsonb_build_array(jsonb_build_object('name', 'كرتونة', 'factor', '12', 'is_default', true),
                        jsonb_build_object('name', 'دستة', 'factor', '12', 'is_default', true)))$$,
  'P0001', 'اختر وحدة بيع افتراضية واحدة فقط',
  'وحدة بيع افتراضية واحدة فقط'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد', 'raw_material', 'كجم',
      jsonb_build_object('default_cost', '1.23456')))$$,
  'P0001', 'التكلفة الافتراضية لا يزيد عن أربع خانات عشرية',
  'التكلفة الافتراضية بخمس خانات مرفوضة'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد', 'raw_material', 'كجم',
      jsonb_build_object('min_stock', '-1')))$$,
  'P0001', 'الحد الأدنى للمخزون يجب أن يكون صفرًا أو أكثر',
  'الحد الأدنى السالب مرفوض'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد', 'raw_material', 'كجم',
      jsonb_build_object('barcode', '6221000000017')))$$,
  'P0001', 'الباركود مستخدم لصنف آخر',
  'الباركود لا يتكرر'
);
select throws_ok(
  $$select public.save_item(jsonb_build_object('code', 'U-SALT', 'name', 'مكرر', 'type', 'raw_material', 'unit', 'كجم'))$$,
  'P0001', 'يوجد صنف بنفس الكود',
  'كود الصنف لا يتكرر (رسالة عربية)'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد', 'service', 'كجم'))$$,
  'P0001', 'اختر نوع الصنف',
  'نوع الصنف من القائمة فقط'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-NEW1', 'جديد ذري', 'raw_material', 'كجم'),
      jsonb_build_array(jsonb_build_object('name', 'كيس', 'factor', '25'),
                        jsonb_build_object('name', 'شوال', 'factor', 'abc')))$$,
  'P0001', 'الوحدة 2: معامل التحويل "abc" غير صالح',
  'معامل غير رقمي مرفوض'
);
select is(
  (select count(*) from public.items where code = 'U-NEW1'),
  0::bigint,
  'الحفظ ذري: الوحدة الخطأ لم تترك الصنف ولا وحداته'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-DISH', 'سائل أطباق وحدات اختبار', 'finished_good', 'عبوة',
      jsonb_build_object('sale_price', '18')),
      jsonb_build_array(
        jsonb_build_object('id', pg_temp.unit('U-DISH', 'كرتونة'), 'name', 'كرتونة', 'factor', '12', 'sale_price', '210',
                           'is_default', true, 'is_active', false),
        jsonb_build_object('id', pg_temp.unit('U-DISH', 'نصف كرتونة'), 'name', 'نصف كرتونة', 'factor', '6')))$$,
  'P0001', 'وحدة البيع الافتراضية يجب أن تكون وحدة نشطة',
  'وحدة البيع الافتراضية لا تكون معطّلة'
);
select throws_ok(
  $$update public.item_units set factor = 10 where id = pg_temp.unit('U-DISH', 'كرتونة')$$,
  '42501', null,
  'المحاسب لا يعدّل الوحدات مباشرة (الكتابة عبر حفظ البطاقة فقط)'
);
reset role;
select throws_ok(
  $$update public.items set default_sale_unit_id = pg_temp.unit('U-BOTTLE', 'كرتونة') where code = 'U-DISH'$$,
  '23503', null,
  'وحدة البيع الافتراضية من وحدات نفس الصنف فقط (مفتاح مركّب)'
);
set local role authenticated;

-- ---------------------------------------------------------------------
-- 5) الشراء بوحدة بديلة: السعر لوحدة الشراء، والمخزون والمتوسط بالوحدة الأساسية
-- ---------------------------------------------------------------------
insert into public.suppliers (name) values ('م وحدات اختبار');
select lives_ok(
  $$select public.post_purchase_invoice('1990-05-01', pg_temp.supp('م وحدات اختبار'), jsonb_build_array(
      pg_temp.pl('U-LABSA', '2', '8000', 'برميل'),
      pg_temp.pl('U-BOTTLE', '3', '100', 'كرتونة'),
      pg_temp.pl('U-SALT', '50', '5')))$$,
  'فاتورة مشتريات: برميلان LABSA، و3 كراتين عبوات، وملح بالوحدة الأساسية'
);
select results_eq(
  $$select i.code, l.unit_name, trim_scale(l.factor)::text, l.qty::text, l.base_qty::text, l.unit_price::text,
           l.line_total::text
    from public.purchase_invoice_lines l join public.items i on i.id = l.item_id
    where i.code like 'U-%' order by i.code collate "C"$$,
  $$values ('U-BOTTLE'::text, 'كرتونة'::text, '50'::text, '3.000'::text, '150.000'::text, '100.0000'::text, '300.00'::text),
           ('U-LABSA', 'برميل', '200', '2.000', '400.000', '8000.0000', '16000.00'),
           ('U-SALT', 'كجم', '1', '50.000', '50.000', '5.0000', '250.00')$$,
  'كل سطر يحفظ الوحدة ومعاملها والكمية الأساسية وقت الاعتماد'
);
select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('U-BOTTLE', 'U-LABSA', 'U-SALT') order by i.code collate "C"$$,
  $$values ('U-BOTTLE'::text, '150.000'::text, '300.00'::text, '2.0000'::text),
           ('U-LABSA', '400.000', '16000.00', '40.0000'),
           ('U-SALT', '50.000', '250.00', '5.0000')$$,
  'المخزون بالوحدة الأساسية: 400 كجم بمتوسط 40، و150 قطعة بمتوسط 2'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-05-02', pg_temp.supp('م وحدات اختبار'),
      jsonb_build_array(pg_temp.pl('U-LABSA', '1.001', '5', 'عبوة صغيرة')))$$,
  'P0001', 'السطر 1: الكمية بالوحدة الأساسية (0.125125) لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة',
  'التحويل للوحدة الأساسية دقيق بلا تقريب صامت'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-05-02', pg_temp.supp('م وحدات اختبار'),
      jsonb_build_array(jsonb_build_object('item_id', pg_temp.item('U-LABSA'), 'unit_id', pg_temp.unit('U-BOTTLE', 'كرتونة'),
                                           'qty', '1', 'unit_price', '1')))$$,
  'P0001', 'السطر 1: الوحدة المختارة ليست من وحدات هذا الصنف',
  'وحدة صنف آخر مرفوضة'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-05-02', pg_temp.supp('م وحدات اختبار'),
      jsonb_build_array(pg_temp.pl('U-LABSA', '1', '700', 'جركن قديم')))$$,
  'P0001', 'السطر 1: الوحدة جركن قديم معطّلة',
  'الوحدة المعطّلة مرفوضة'
);

-- ---------------------------------------------------------------------
-- 6) حماية التاريخ: المعامل والوحدة الأساسية ثابتان بعد الاستخدام، والاسم المحفوظ في السطر لا يتغير
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.save_item(pg_temp.card('U-LABSA', 'LABSA وحدات اختبار', 'raw_material', 'كجم'),
      jsonb_build_array(
        jsonb_build_object('id', pg_temp.unit('U-LABSA', 'برميل'), 'name', 'برميل', 'factor', '180'),
        jsonb_build_object('id', pg_temp.unit('U-LABSA', 'عبوة صغيرة'), 'name', 'عبوة صغيرة', 'factor', '0.125'),
        jsonb_build_object('id', pg_temp.unit('U-LABSA', 'جركن قديم'), 'name', 'جركن قديم', 'factor', '20',
                           'is_active', false)))$$,
  'P0001', 'لا يمكن تغيير معامل تحويل الوحدة برميل لأنها استُخدمت في مستندات أو وصفات',
  'معامل وحدة مستخدمة في فاتورة لا يتغير'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-LABSA', 'LABSA وحدات اختبار', 'raw_material', 'كجم'),
      jsonb_build_array(
        jsonb_build_object('id', pg_temp.unit('U-LABSA', 'عبوة صغيرة'), 'name', 'عبوة صغيرة', 'factor', '0.125')))$$,
  'P0001', 'لا يمكن حذف وحدة استُخدمت في مستندات أو وصفات. عطّلها بدل الحذف',
  'وحدة مستخدمة لا تُحذف'
);
select throws_ok(
  $$select public.save_item(pg_temp.card('U-LABSA', 'LABSA وحدات اختبار', 'raw_material', 'لتر'))$$,
  'P0001', 'لا يمكن تغيير الوحدة الأساسية لصنف عليه حركات أو مستندات',
  'الوحدة الأساسية لصنف مستخدم لا تتغير'
);
select lives_ok(
  $$select public.save_item(pg_temp.card('U-LABSA', 'LABSA وحدات اختبار', 'raw_material', 'كجم',
      jsonb_build_object('category_id', pg_temp.cat('خامات اختبار'), 'default_cost', '99')),
      jsonb_build_array(
        jsonb_build_object('id', pg_temp.unit('U-LABSA', 'برميل'), 'name', 'برميل 200 كجم', 'factor', '200'),
        jsonb_build_object('id', pg_temp.unit('U-LABSA', 'عبوة صغيرة'), 'name', 'عبوة صغيرة', 'factor', '0.25'),
        jsonb_build_object('id', pg_temp.unit('U-LABSA', 'جركن قديم'), 'name', 'جركن قديم', 'factor', '20',
                           'is_active', false)))$$,
  'إعادة تسمية وحدة مستخدمة، وتغيير معامل وحدة غير مستخدمة، وتغيير التكلفة الافتراضية مسموح'
);
select results_eq(
  $$select l.unit_name, trim_scale(l.factor)::text, l.base_qty::text,
           (select name from public.item_units where id = l.unit_id)
    from public.purchase_invoice_lines l where l.item_id = pg_temp.item('U-LABSA')$$,
  $$values ('برميل'::text, '200'::text, '400.000'::text, 'برميل 200 كجم'::text)$$,
  'السطر المعتمد يحتفظ باسم الوحدة ومعاملها وقت الاعتماد'
);
select results_eq(
  $$select * from pg_temp.stock('U-LABSA')$$,
  $$values ('400.000'::text, '16000.00'::text, '40.0000'::text)$$,
  'تغيير التكلفة الافتراضية (99) لا يمس الرصيد ولا المتوسط الفعلي (40)'
);
select lives_ok(
  $$select public.save_item(pg_temp.card('U-DISH', 'سائل أطباق وحدات اختبار', 'finished_good', 'زجاجة',
      jsonb_build_object('sale_price', '18', 'barcode', '6221000000017', 'default_cost', '9.5', 'min_stock', '20',
                         'category_id', pg_temp.cat('منظفات اختبار'))),
      jsonb_build_array(
        jsonb_build_object('id', pg_temp.unit('U-DISH', 'كرتونة'), 'name', 'كرتونة', 'factor', '12', 'sale_price', '210',
                           'is_default', true),
        jsonb_build_object('id', pg_temp.unit('U-DISH', 'نصف كرتونة'), 'name', 'نصف كرتونة', 'factor', '6',
                           'sale_price', '108')))$$,
  'الوحدة الأساسية لصنف لم يُستخدم تتغير'
);

-- ---------------------------------------------------------------------
-- 7) مخزون أول المدة: التكلفة المقترحة من البطاقة أو المعدّلة، وتُرسمل مرة واحدة على رأس المال
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_stock_opening('1990-01-01', jsonb_build_array(
      pg_temp.ol('U-DISH', '100', (select default_cost::text from public.items where code = 'U-DISH')),
      pg_temp.ol('U-SALT', '10', '5')), true)$$,
  'مخزون أول المدة: سائل الأطباق بالتكلفة المقترحة 9.5، والملح بتكلفة معدّلة 5 (الافتراضية 4)'
);
select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text, i.default_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('U-DISH', 'U-SALT') order by i.code collate "C"$$,
  $$values ('U-DISH'::text, '100.000'::text, '950.00'::text, '9.5000'::text, '9.5000'::text),
           ('U-SALT', '60.000', '300.00', '5.0000', '4.0000')$$,
  'الرصيد والمتوسط من التكلفة المعتمدة (5 للملح) لا من التكلفة الافتراضية (4)'
);
select results_eq(
  $$select a.code, l.debit::text, l.credit::text
    from public.journal_lines l join public.accounts a on a.id = l.account_id
    where l.entry_id = (select entry_id from public.active_openings() where part = 'inventory')
    order by a.code$$,
  $$values ('1301'::text, '50.00'::text, '0.00'::text), ('1303', '950.00', '0.00'), ('3101', '0.00', '1000.00')$$,
  'قيد مخزون أول المدة: م المخزون حسب النوع / د رأس المال بالقيمة مرة واحدة'
);
select throws_ok(
  $$select public.post_stock_opening('1990-01-01', jsonb_build_array(pg_temp.ol('U-BOTTLE', '1', '2')), true)$$,
  'P0001', 'مخزون أول المدة مسجّل بالفعل. للتصحيح ألغِ قيده ثم سجّله من جديد',
  'لا رسملة مزدوجة: مخزون أول المدة مرة واحدة'
);
select throws_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      jsonb_build_object('account_id', pg_temp.acc('1303'), 'debit', '950', 'credit', '0'),
      jsonb_build_object('account_id', pg_temp.acc('3101'), 'debit', '0', 'credit', '950')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 1303 - مخزون منتج تام. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'لا ازدواج بين الأرصدة الافتتاحية: حسابات المخزون مرفوضة في أرصدة الحسابات'
);

-- ---------------------------------------------------------------------
-- 8) حذف التصنيف والصنف
-- ---------------------------------------------------------------------
select throws_ok(
  $$delete from public.item_categories where name = 'منظفات اختبار'$$,
  '23503', null, 'تصنيف عليه أصناف لا يُحذف'
);
select lives_ok(
  $$delete from public.item_categories where name = 'تصنيف فارغ اختبار'$$,
  'تصنيف بلا أصناف يُحذف'
);
select lives_ok(
  $$select public.save_item(pg_temp.card('U-TEMP', 'صنف مؤقت اختبار', 'packaging', 'قطعة'),
      jsonb_build_array(jsonb_build_object('name', 'رزمة', 'factor', '10')))$$,
  'صنف مؤقت بوحدة بديلة'
);
select lives_ok(
  $$delete from public.items where code = 'U-TEMP'$$,
  'صنف بلا حركات يُحذف مع وحداته'
);
select is(
  (select count(*) from public.item_units u where not exists (select 1 from public.items i where i.id = u.item_id)),
  0::bigint,
  'لا وحدات بلا صنف'
);

-- ---------------------------------------------------------------------
-- 9) المطابقة وفحوص الـ commit
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
  $$values ('1301'::text, '16300.00'::text, '16300.00'::text),
           ('1302', '300.00', '300.00'),
           ('1303', '950.00', '950.00')$$,
  'كل حساب مخزون في الأستاذ = قيمة أصناف نوعه'
);

reset role;
select * from finish();
rollback;
