-- =====================================================================
-- اختبارات المرحلة 4: الأصناف والمخزون والمشتريات (pgTAP)
-- الصلاحيات، متوسط التكلفة المرجح المتحرك، فاتورة المشتريات و«مدفوع الآن»، تسوية الجرد،
-- مخزون أول المدة، الإلغاء وفرق التكلفة، منع الرصيد السالب، فحوص الـ commit، والمطابقة مع الأستاذ.
-- تعمل داخل transaction تُلغى في النهاية. البيانات بتاريخ 1990 وأكواد الأصناف تبدأ بـ T-.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(126);

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
select (select last_no from public.doc_counters where kind = 'purchase_invoice') as purchase_no,
       (select last_no from public.doc_counters where kind = 'stock_adjustment') as adjustment_no,
       (select last_no from public.doc_counters where kind = 'payment_voucher') as payment_no;
grant select on _base to public;

create function pg_temp.acc(p_code text) returns bigint language sql stable as $$
  select id from public.accounts where code = p_code;
$$;

create function pg_temp.item(p_code text) returns bigint language sql stable as $$
  select id from public.items where code = p_code;
$$;

create function pg_temp.supp(p_name text) returns bigint language sql stable as $$
  select id from public.suppliers where name = p_name;
$$;

create function pg_temp.line(p_code text, p_debit text, p_credit text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'account_id', (select id from public.accounts where code = p_code),
    'debit', p_debit,
    'credit', p_credit
  );
$$;

-- سطر فاتورة مشتريات / سطر مخزون أول المدة
create function pg_temp.pl(p_code text, p_qty text, p_price text) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'qty', p_qty, 'unit_price', p_price);
$$;

create function pg_temp.ol(p_code text, p_qty text, p_cost text) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'qty', p_qty, 'unit_cost', p_cost);
$$;

-- الفاتورة / التسوية رقم n (نسبةً لبداية الاختبار) وقيدها
create function pg_temp.pi(p_n int) returns bigint language sql stable as $$
  select id from public.purchase_invoices where doc_no = (select purchase_no from pg_temp._base) + p_n;
$$;

create function pg_temp.pi_entry(p_n int) returns bigint language sql stable as $$
  select journal_entry_id from public.purchase_invoices where id = pg_temp.pi(p_n);
$$;

create function pg_temp.sa(p_n int) returns bigint language sql stable as $$
  select id from public.stock_adjustments where doc_no = (select adjustment_no from pg_temp._base) + p_n;
$$;

create function pg_temp.sa_entry(p_n int) returns bigint language sql stable as $$
  select journal_entry_id from public.stock_adjustments where id = pg_temp.sa(p_n);
$$;

create function pg_temp.reversal_of(p_entry bigint) returns bigint language sql stable as $$
  select id from public.journal_entries where reverses_entry_id = p_entry;
$$;

-- سطور قيد بترتيب إدخالها (الحساب، مدين، دائن، المورد)
create function pg_temp.entry_lines(p_entry bigint)
returns table (code text, debit text, credit text, party text) language sql stable as $$
  select a.code, l.debit::text, l.credit::text, s.name
  from public.journal_lines l
  join public.accounts a on a.id = l.account_id
  left join public.suppliers s on s.id = l.supplier_id
  where l.entry_id = p_entry
  order by l.id;
$$;

-- رصيد الصنف (كمية، قيمة، متوسط)
create function pg_temp.stock(p_code text)
returns table (qty text, value text, avg_cost text) language sql stable as $$
  select qty::text, value::text, avg_cost::text from public.item_stock where item_id = pg_temp.item(p_code);
$$;

-- إدخال مباشر كمالك الجدول ثم فحص الـ commit فورًا (لاختبار الفحوص المؤجلة)
create function pg_temp.inventory_line_without_movement() returns void language plpgsql as $$
declare
  v_entry bigint;
begin
  insert into public.journal_entries (entry_no, entry_date, description, source_type, created_by)
  values (-201, '1990-04-01', 'مخزون بلا حركة', 'purchase', '22222222-2222-2222-2222-222222222222')
  returning id into v_entry;
  insert into public.journal_lines (entry_id, account_id, debit, credit, supplier_id)
  values (v_entry, pg_temp.acc('1301'), 45, 0, null),
         (v_entry, pg_temp.acc('2101'), 0, 45, pg_temp.supp('م1 اختبار'));
  set constraints all immediate;
end;
$$;

create function pg_temp.movement_without_stock() returns void language plpgsql as $$
declare
  v_entry bigint;
begin
  insert into public.journal_entries (entry_no, entry_date, description, source_type, created_by)
  values (-202, '1990-04-01', 'حركة بلا رصيد', 'purchase', '22222222-2222-2222-2222-222222222222')
  returning id into v_entry;
  insert into public.journal_lines (entry_id, account_id, debit, credit, supplier_id)
  values (v_entry, pg_temp.acc('1301'), 45, 0, null),
         (v_entry, pg_temp.acc('2101'), 0, 45, pg_temp.supp('م1 اختبار'));
  insert into public.stock_movements (
    item_id, movement_date, kind, qty_in, unit_cost, total_cost, source_type, journal_entry_id
  )
  values (pg_temp.item('T-LABSA'), '1990-04-01', 'purchase', 1, 45, 45, 'purchase', v_entry);
  set constraints all immediate;
end;
$$;

create function pg_temp.edit_stock() returns void language plpgsql as $$
begin
  update public.item_stock set value = value + 1 where item_id = pg_temp.item('T-LABSA');
  set constraints all immediate;
end;
$$;

create function pg_temp.movement_wrong_type() returns void language plpgsql as $$
declare
  v_entry bigint;
begin
  insert into public.journal_entries (entry_no, entry_date, description, source_type, created_by)
  values (-203, '1990-04-01', 'حركة على حساب نوع آخر', 'purchase', '22222222-2222-2222-2222-222222222222')
  returning id into v_entry;
  insert into public.journal_lines (entry_id, account_id, debit, credit, supplier_id)
  values (v_entry, pg_temp.acc('1301'), 2, 0, null),
         (v_entry, pg_temp.acc('2101'), 0, 2, pg_temp.supp('م1 اختبار'));
  insert into public.stock_movements (
    item_id, movement_date, kind, qty_in, unit_cost, total_cost, source_type, journal_entry_id
  )
  values (pg_temp.item('T-BOTTLE'), '1990-04-01', 'purchase', 1, 2, 2, 'purchase', v_entry);
  update public.item_stock set qty = qty + 1, value = value + 2 where item_id = pg_temp.item('T-BOTTLE');
  set constraints all immediate;
end;
$$;

-- ---------------------------------------------------------------------
-- 1) الصلاحيات: anon
-- ---------------------------------------------------------------------
set local role anon;

select throws_ok($$select * from public.items$$, '42501', null, 'anon لا يقرأ الأصناف');
select throws_ok($$select * from public.stock_movements$$, '42501', null, 'anon لا يقرأ حركات المخزون');
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-10', 1, '[]'::jsonb)$$,
  '42501', null, 'anon لا يعتمد فواتير مشتريات'
);
select throws_ok($$select * from public.stock_balances()$$, '42501', null, 'anon لا يقرأ أرصدة المخزون');

reset role;

-- ---------------------------------------------------------------------
-- 2) المحاسب يدير الأصناف (أعمدة محددة)، والمخزون والمستندات قراءة فقط
-- ---------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select lives_ok(
  $$insert into public.items (code, name, type, unit, sale_price, is_active) values
      ('T-LABSA', 'LABSA اختبار', 'raw_material', 'كجم', null, true),
      ('T-SLES', 'SLES اختبار', 'raw_material', 'كجم', null, true),
      ('T-SALT', 'ملح اختبار', 'raw_material', 'كجم', null, true),
      ('T-BOTTLE', 'عبوة 1 لتر بغطاء اختبار', 'packaging', 'قطعة', null, true),
      ('T-DISH', 'سائل أطباق 1 لتر اختبار', 'finished_good', 'عبوة', 18, true),
      ('T-GLY', 'جلسرين اختبار', 'raw_material', 'كجم', null, true),
      ('T-RES1', 'مادة فرق 1 اختبار', 'raw_material', 'كجم', null, true),
      ('T-RES2', 'مادة فرق 2 اختبار', 'raw_material', 'كجم', null, true),
      ('T-NEW', 'صنف بلا حركة اختبار', 'finished_good', 'عبوة', null, true),
      ('T-OLD', 'صنف معطل اختبار', 'raw_material', 'كجم', null, false)$$,
  'المحاسب يضيف أصنافًا'
);

select is(
  (select count(*) from public.item_stock s join public.items i on i.id = s.item_id
   where i.code like 'T-%' and s.qty = 0 and s.value = 0 and s.avg_cost = 0),
  10::bigint,
  'لكل صنف جديد صف رصيد صفري تلقائيًا'
);

select throws_ok(
  $$insert into public.items (code, name, type, unit) values ('T-LABSA', 'مكرر', 'raw_material', 'كجم')$$,
  '23505', null, 'كود الصنف لا يتكرر'
);
select throws_ok(
  $$insert into public.items (code, name, type, unit) values ('T-BAD', 'نوع خطأ', 'service', 'كجم')$$,
  '23514', null, 'نوع الصنف من القائمة فقط'
);
select throws_ok(
  $$insert into public.item_stock (item_id, qty, value) values (pg_temp.item('T-LABSA'), 1, 1)$$,
  '42501', null, 'المحاسب لا يكتب في أرصدة الأصناف مباشرة'
);
select throws_ok(
  $$update public.item_stock set qty = 1 where item_id = pg_temp.item('T-LABSA')$$,
  '42501', null, 'المحاسب لا يعدّل أرصدة الأصناف مباشرة'
);
select throws_ok(
  $$insert into public.stock_movements (item_id, movement_date, kind, qty_in, total_cost, source_type, journal_entry_id)
    values (pg_temp.item('T-LABSA'), '1990-01-01', 'purchase', 1, 1, 'purchase', 1)$$,
  '42501', null, 'المحاسب لا يكتب حركات مخزون مباشرة'
);
select throws_ok(
  $$insert into public.purchase_invoices (doc_no, doc_date, supplier_id, total, journal_entry_id)
    values (1, '1990-01-01', 1, 1, 1)$$,
  '42501', null, 'المحاسب لا يكتب فواتير مشتريات مباشرة'
);
select throws_ok(
  $$select private.stock_in(pg_temp.item('T-LABSA'), 1, 1, '1990-01-01', 'purchase', 'purchase', null, 1)$$,
  '42501', null, 'دوال المخزون الداخلية غير متاحة للمستخدم'
);

select lives_ok(
  $$insert into public.suppliers (name, is_active) values ('م1 اختبار', true), ('م2 معطل اختبار', false)$$,
  'المحاسب يضيف الموردين'
);

-- ---------------------------------------------------------------------
-- 3) SPEC §11 الخطوات 1–3: أرصدة افتتاحية، فاتورة مشتريات آجل، سند صرف للمورد
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1101', '100000', '0'),
      pg_temp.line('1501', '50000', '0'),
      pg_temp.line('3101', '0', '150000')))$$,
  'الخطوة 1: الأرصدة الافتتاحية للحسابات'
);

select lives_ok(
  $$select public.post_purchase_invoice('1990-01-10', pg_temp.supp('م1 اختبار'), jsonb_build_array(
      pg_temp.pl('T-LABSA', '100', '40'),
      pg_temp.pl('T-SLES', '100', '50'),
      pg_temp.pl('T-SALT', '100', '5'),
      pg_temp.pl('T-BOTTLE', '500', '2')), 'فاتورة الخطوة 2')$$,
  'الخطوة 2: فاتورة مشتريات آجل من م1'
);

select results_eq(
  $$select p.doc_no - (select purchase_no from pg_temp._base), p.doc_date, p.total::text,
           p.payment_voucher_id is null, e.source_type, e.source_id = p.id
    from public.purchase_invoices p
    join public.journal_entries e on e.id = p.journal_entry_id
    where p.id = pg_temp.pi(1)$$,
  $$values (1::bigint, '1990-01-10'::date, '10500.00'::text, true, 'purchase'::text, true)$$,
  'الفاتورة: الرقم التالي، الإجمالي 10,500، آجل، قيد مشتريات مربوط بها'
);

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.pi_entry(1))$$,
  $$values ('1301'::text, '9500.00'::text, '0.00'::text, null::text),
           ('1302', '1000.00', '0.00', null),
           ('2101', '0.00', '10500.00', 'م1 اختبار')$$,
  'قيد الفاتورة: م مخزون خام 9,500 + م مخزون تعبئة 1,000 / د الموردين 10,500 بالمورد'
);

select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('T-LABSA', 'T-SLES', 'T-SALT', 'T-BOTTLE')
    order by i.code collate "C"$$,
  $$values ('T-BOTTLE'::text, '500.000'::text, '1000.00'::text, '2.0000'::text),
           ('T-LABSA', '100.000', '4000.00', '40.0000'),
           ('T-SALT', '100.000', '500.00', '5.0000'),
           ('T-SLES', '100.000', '5000.00', '50.0000')$$,
  'أرصدة الأصناف ومتوسطاتها بعد الفاتورة: 40 و50 و5 و2'
);

select results_eq(
  $$select i.code, m.kind, m.qty_in::text, m.qty_out::text, m.unit_cost::text, m.total_cost::text,
           m.source_type, m.source_id = pg_temp.pi(1)
    from public.stock_movements m join public.items i on i.id = m.item_id
    where m.journal_entry_id = pg_temp.pi_entry(1)
    order by i.code collate "C"$$,
  $$values ('T-BOTTLE'::text, 'purchase'::text, '500.000'::text, '0.000'::text, '2.0000'::text, '1000.00'::text, 'purchase'::text, true),
           ('T-LABSA', 'purchase', '100.000', '0.000', '40.0000', '4000.00', 'purchase', true),
           ('T-SALT', 'purchase', '100.000', '0.000', '5.0000', '500.00', 'purchase', true),
           ('T-SLES', 'purchase', '100.000', '0.000', '50.0000', '5000.00', 'purchase', true)$$,
  'حركات إضافة بنفس قيد الفاتورة وتكلفة كل سطر'
);

select results_eq(
  $$select i.code, l.qty::text, l.unit_price::text, l.line_total::text
    from public.purchase_invoice_lines l join public.items i on i.id = l.item_id
    where l.invoice_id = pg_temp.pi(1)
    order by i.code collate "C"$$,
  $$values ('T-BOTTLE'::text, '500.000'::text, '2.0000'::text, '1000.00'::text),
           ('T-LABSA', '100.000', '40.0000', '4000.00'),
           ('T-SALT', '100.000', '5.0000', '500.00'),
           ('T-SLES', '100.000', '50.0000', '5000.00')$$,
  'سطور الفاتورة محفوظة بالكمية والسعر والإجمالي'
);

select lives_ok(
  $$select public.post_voucher('payment', '1990-01-15', pg_temp.acc('1101'), 'supplier',
      pg_temp.supp('م1 اختبار'), '5000', 'دفعة للمورد')$$,
  'الخطوة 3: سند صرف 5,000 للمورد م1'
);

select results_eq(
  $$select code, debit, credit from public.trial_balance('1990-01-31')$$,
  $$values ('1101'::text, '95000.00'::text, '0.00'::text),
           ('1301', '9500.00', '0.00'),
           ('1302', '1000.00', '0.00'),
           ('1501', '50000.00', '0.00'),
           ('2101', '0.00', '5500.00'),
           ('3101', '0.00', '150000.00')$$,
  'بعد الخطوات 1–3: مخزون خام 9,500 وتعبئة 1,000 والموردين 5,500 والميزان متوازن (155,500)'
);

select is(
  (select balance from public.party_balances('supplier') where party_id = pg_temp.supp('م1 اختبار')),
  '-5500.00',
  'رصيد المورد م1 دائن 5,500'
);

select lives_ok($$set constraints all immediate$$, 'فحوص الـ commit (التوازن والمخزون) تنجح بصلاحية المستخدم نفسه');
set constraints all deferred;

-- ---------------------------------------------------------------------
-- 4) مخزون أول المدة (الجزء الثالث من الأرصدة الافتتاحية)
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.post_stock_opening('1990-01-01', jsonb_build_array(
      pg_temp.ol('T-GLY', '10', '12.345'), pg_temp.ol('T-DISH', '20', '9.5')))$$,
  'P0001', 'الأرصدة غير متوازنة: المدين 313.45 والدائن 0.00 والفرق 313.45. أكّد تسجيل الفرق على حساب رأس المال',
  'مخزون أول المدة يحتاج تأكيد تسجيل قيمته على رأس المال'
);
select throws_ok(
  $$select public.post_stock_opening('1990-01-01', jsonb_build_array(pg_temp.ol('T-GLY', '5', '0')), true)$$,
  'P0001', 'السطر 1: قيمة الصنف يجب أن تكون أكبر من صفر',
  'سطر مخزون أول المدة بلا قيمة مرفوض'
);
select lives_ok(
  $$select public.post_stock_opening('1990-01-01', jsonb_build_array(
      pg_temp.ol('T-GLY', '10', '12.345'), pg_temp.ol('T-DISH', '20', '9.5')), true)$$,
  'مخزون أول المدة بعد التأكيد'
);

reset role;
create temp table _inv_open as
select entry_id as id from public.active_openings() where part = 'inventory';
grant select on _inv_open to public;
set local role authenticated;

select results_eq(
  $$select a.code, l.debit::text, l.credit::text
    from public.journal_lines l join public.accounts a on a.id = l.account_id
    where l.entry_id = (select id from pg_temp._inv_open)
    order by a.code$$,
  $$values ('1301'::text, '123.45'::text, '0.00'::text),
           ('1303', '190.00', '0.00'),
           ('3101', '0.00', '313.45')$$,
  'قيد مخزون أول المدة: م حساب كل نوع / د رأس المال'
);

select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text, m.kind, m.source_type,
           m.source_id = m.journal_entry_id
    from public.stock_movements m
    join public.items i on i.id = m.item_id
    join public.item_stock s on s.item_id = m.item_id
    where m.journal_entry_id = (select id from pg_temp._inv_open)
    order by i.code collate "C"$$,
  $$values ('T-DISH'::text, '20.000'::text, '190.00'::text, '9.5000'::text, 'opening'::text, 'opening'::text, true),
           ('T-GLY', '10.000', '123.45', '12.3450', 'opening', 'opening', true)$$,
  'حركات افتتاحية مربوطة بالقيد، والأرصدة والمتوسطات (12.345 بأربع خانات)'
);

select results_eq(
  $$select part from public.active_openings() order by entry_no$$,
  $$values ('accounts'::text), ('inventory')$$,
  'جزء المخزون يتعايش مع جزء الحسابات'
);

select throws_ok(
  $$select public.post_stock_opening('1990-01-01', jsonb_build_array(pg_temp.ol('T-SALT', '1', '1')), true)$$,
  'P0001', 'مخزون أول المدة مسجّل بالفعل. للتصحيح ألغِ قيده ثم سجّله من جديد',
  'مخزون أول المدة مرة واحدة'
);

-- ---------------------------------------------------------------------
-- 5) فاتورة ثانية «مدفوع الآن» ومتوسط مرجح جديد، ورفض المدخلات الخطأ
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-LABSA', '100', '50')), null, '5000', pg_temp.acc('1501'))$$,
  'P0001', 'اختر خزينة أو بنكًا',
  '«مدفوع الآن» من حساب ليس خزينة مرفوض'
);

select lives_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'), jsonb_build_array(
      pg_temp.pl('T-LABSA', '100', '50'), pg_temp.pl('T-SALT', '3', '7')), null, '5021', pg_temp.acc('1101'))$$,
  'فاتورة مدفوعة بالكامل الآن من الخزينة'
);

select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('T-LABSA', 'T-SALT')
    order by i.code collate "C"$$,
  $$values ('T-LABSA'::text, '200.000'::text, '9000.00'::text, '45.0000'::text),
           ('T-SALT', '103.000', '521.00', '5.0583')$$,
  'المتوسط الجديد = إجمالي القيمة ÷ إجمالي الكمية (45، و521 ÷ 103 = 5.0583)'
);

select results_eq(
  $$select v.kind, v.doc_no - (select payment_no from pg_temp._base), v.amount::text, v.notes, s.name, a.code,
           not exists (select 1 from public.journal_entries r where r.reverses_entry_id = v.journal_entry_id)
    from public.purchase_invoices p
    join public.vouchers v on v.id = p.payment_voucher_id
    join public.suppliers s on s.id = v.supplier_id
    join public.accounts a on a.id = v.treasury_account_id
    where p.id = pg_temp.pi(2)$$,
  $$select 'payment'::text, 2::bigint, '5021.00'::text,
           'سداد فاتورة مشتريات رقم ' || ((select purchase_no from pg_temp._base) + 2),
           'م1 اختبار'::text, '1101'::text, true$$,
  'سند صرف تلقائي بكامل الفاتورة، مربوط بها ومرقّم بعد سند الخطوة 3'
);

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.pi_entry(2))$$,
  $$values ('1301'::text, '5021.00'::text, '0.00'::text, null::text),
           ('2101', '0.00', '5021.00', 'م1 اختبار')$$,
  'قيد الفاتورة المدفوعة: م مخزون خام / د الموردين بالمورد'
);

select results_eq(
  $$select * from pg_temp.entry_lines(
      (select v.journal_entry_id from public.vouchers v join public.purchase_invoices p on p.payment_voucher_id = v.id
       where p.id = pg_temp.pi(2)))$$,
  $$values ('2101'::text, '5021.00'::text, '0.00'::text, 'م1 اختبار'::text),
           ('1101', '0.00', '5021.00', null)$$,
  'قيد السند: م الموردين بالمورد / د الخزينة'
);

select is(
  (select balance from public.party_balances('supplier') where party_id = pg_temp.supp('م1 اختبار')),
  '-5500.00',
  'رصيد المورد لا يتغير بفاتورة مدفوعة الآن'
);

select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-DISH', '10', '9')))$$,
  'P0001', 'السطر 1: فاتورة المشتريات للخامات ومواد التعبئة فقط، والصنف T-DISH - سائل أطباق 1 لتر اختبار منتج تام',
  'المنتج التام لا يُشترى بفاتورة مشتريات'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م2 معطل اختبار'),
      jsonb_build_array(pg_temp.pl('T-LABSA', '1', '40')))$$,
  'P0001', 'اختر موردًا نشطًا',
  'مورد معطّل مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-OLD', '1', '40')))$$,
  'P0001', 'السطر 1: الصنف T-OLD - صنف معطل اختبار معطّل',
  'صنف معطّل مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'), jsonb_build_array(
      pg_temp.pl('T-LABSA', '1', '40'), pg_temp.pl('T-SALT', '1', '5'), pg_temp.pl('T-LABSA', '2', '40')))$$,
  'P0001', 'السطر 3: الصنف T-LABSA - LABSA اختبار مكرر في الفاتورة',
  'الصنف لا يتكرر في الفاتورة'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-LABSA', '1.2345', '40')))$$,
  'P0001', 'السطر 1: الكمية لا تزيد عن ثلاث خانات عشرية',
  'الكمية بأربع خانات عشرية مرفوضة (بلا تقريب صامت)'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-LABSA', '1', '40.12345')))$$,
  'P0001', 'السطر 1: سعر الوحدة لا يزيد عن أربع خانات عشرية',
  'سعر الوحدة بخمس خانات عشرية مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-LABSA', '0', '40')))$$,
  'P0001', 'السطر 1: الكمية يجب أن تكون أكبر من صفر',
  'الكمية صفر مرفوضة'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-LABSA', '1', '-40')))$$,
  'P0001', 'السطر 1: سعر الوحدة يجب أن يكون رقمًا موجبًا',
  'السعر السالب مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-LABSA', '0.001', '1')))$$,
  'P0001', 'السطر 1: إجمالي السطر يجب أن يكون أكبر من صفر',
  'سطر إجماليه أقل من قرش مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'), '[]'::jsonb)$$,
  'P0001', 'أضف صنفًا واحدًا على الأقل',
  'فاتورة بلا سطور مرفوضة'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-01-20', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(jsonb_build_object('item_id', -1, 'qty', '1', 'unit_price', '1')))$$,
  'P0001', 'السطر 1: اختر الصنف',
  'صنف غير موجود مرفوض'
);

select results_eq(
  $$select (select count(*) from public.purchase_invoices where doc_no > (select purchase_no from pg_temp._base)),
           (select max(doc_no) - (select purchase_no from pg_temp._base) from public.purchase_invoices),
           (select count(*) from public.vouchers
            where kind = 'payment' and doc_no > (select payment_no from pg_temp._base))$$,
  $$values (2::bigint, 2::bigint, 2::bigint)$$,
  'المحاولات المرفوضة لا تستهلك أرقام فواتير ولا سندات'
);

-- ---------------------------------------------------------------------
-- 6) تسوية الجرد: العجز بالمتوسط الحالي، والزيادة بآخر متوسط
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_stock_adjustment('1990-02-01', pg_temp.item('T-LABSA'), '184', 'جرد فبراير')$$,
  'تسوية عجز LABSA (200 ← 184)'
);

select results_eq(
  $$select doc_no - (select adjustment_no from pg_temp._base), system_qty::text, counted_qty::text,
           unit_cost::text, total_cost::text
    from public.stock_adjustments where id = pg_temp.sa(1)$$,
  $$values (1::bigint, '200.000'::text, '184.000'::text, '45.0000'::text, '720.00'::text)$$,
  'العجز 16 بمتوسط 45 = 720'
);

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.sa_entry(1))$$,
  $$values ('5201'::text, '720.00'::text, '0.00'::text, null::text),
           ('1301', '0.00', '720.00', null)$$,
  'قيد العجز: م فروقات الجرد / د المخزون'
);

select results_eq(
  $$select * from pg_temp.stock('T-LABSA')$$,
  $$values ('184.000'::text, '8280.00'::text, '45.0000'::text)$$,
  'الصرف لا يغير المتوسط'
);

select lives_ok(
  $$select public.post_stock_adjustment('1990-02-01', pg_temp.item('T-SALT'), '102')$$,
  'تسوية عجز ملح (103 ← 102)'
);

select results_eq(
  $$select a.total_cost::text, a.unit_cost::text, s.qty::text, s.value::text, s.avg_cost::text
    from public.stock_adjustments a join public.item_stock s on s.item_id = a.item_id
    where a.id = pg_temp.sa(2)$$,
  $$values ('5.06'::text, '5.0600'::text, '102.000'::text, '515.94'::text, '5.0582'::text)$$,
  'الصرف = كمية × القيمة ÷ الرصيد مقربًا للقرش (521 ÷ 103 = 5.06)، والقيمة الباقية دقيقة'
);

select lives_ok(
  $$select public.post_stock_adjustment('1990-02-01', pg_temp.item('T-BOTTLE'), '510')$$,
  'تسوية زيادة عبوات (500 ← 510)'
);

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.sa_entry(3))$$,
  $$values ('1302'::text, '20.00'::text, '0.00'::text, null::text),
           ('5201', '0.00', '20.00', null)$$,
  'قيد الزيادة: م المخزون / د فروقات الجرد بآخر متوسط (10 × 2)'
);

select results_eq(
  $$select * from pg_temp.stock('T-BOTTLE')$$,
  $$values ('510.000'::text, '1020.00'::text, '2.0000'::text)$$,
  'رصيد العبوات بعد الزيادة'
);

select throws_ok(
  $$select public.post_stock_adjustment('1990-02-01', pg_temp.item('T-NEW'), '5')$$,
  'P0001', 'لا توجد تكلفة حالية للصنف T-NEW - صنف بلا حركة اختبار. سجّل مخزون أول المدة أو فاتورة مشتريات أولًا',
  'زيادة على صنف بلا تكلفة مرفوضة'
);
select throws_ok(
  $$select public.post_stock_adjustment('1990-02-01', pg_temp.item('T-LABSA'), '184')$$,
  'P0001', 'لا فرق بين الكمية الفعلية ورصيد النظام (184)',
  'تسوية بلا فرق مرفوضة'
);
select throws_ok(
  $$select public.post_stock_adjustment('1990-02-01', pg_temp.item('T-LABSA'), '-1')$$,
  'P0001', 'الكمية الفعلية: الكمية يجب أن تكون صفرًا أو أكثر',
  'الكمية الفعلية السالبة مرفوضة'
);
select throws_ok(
  $$select public.post_stock_adjustment('1990-02-01', pg_temp.item('T-LABSA'), '1.2345')$$,
  'P0001', 'الكمية الفعلية: الكمية لا تزيد عن ثلاث خانات عشرية',
  'الكمية الفعلية بأربع خانات مرفوضة'
);
select throws_ok(
  $$select public.post_stock_adjustment('1990-02-01', pg_temp.item('T-OLD'), '1')$$,
  'P0001', 'الصنف T-OLD - صنف معطل اختبار معطّل',
  'تسوية صنف معطّل مرفوضة'
);

select lives_ok($$set constraints all immediate$$, 'فحوص الـ commit تنجح بعد التسويات');
set constraints all deferred;

-- ---------------------------------------------------------------------
-- 7) الإلغاء: قيد عكسي وحركات عكسية بنفس التكلفة، والسند يبقى
-- ---------------------------------------------------------------------
select lives_ok($$select public.cancel_stock_adjustment(pg_temp.sa(2))$$, 'إلغاء تسوية العجز (ملح)');

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.reversal_of(pg_temp.sa_entry(2)))$$,
  $$values ('5201'::text, '0.00'::text, '5.06'::text, null::text),
           ('1301', '5.06', '0.00', null)$$,
  'القيد العكسي عكس سطور التسوية'
);

select results_eq(
  $$select s.qty::text, s.value::text, s.avg_cost::text, m.kind, m.qty_in::text, m.total_cost::text, m.movement_date
    from public.item_stock s
    join public.stock_movements m on m.item_id = s.item_id
    where s.item_id = pg_temp.item('T-SALT')
      and m.reverses_movement_id = (select id from public.stock_movements
                                    where journal_entry_id = pg_temp.sa_entry(2))$$,
  $$values ('103.000'::text, '521.00'::text, '5.0583'::text, 'reversal'::text, '1.000'::text, '5.06'::text, '1990-02-01'::date)$$,
  'الحركة العكسية بنفس التاريخ والتكلفة، والرصيد والمتوسط يعودان كما كانا'
);

select throws_ok(
  $$select public.cancel_stock_adjustment(pg_temp.sa(2))$$,
  'P0001', 'تسوية الجرد رقم ' || ((select adjustment_no from pg_temp._base) + 2) || ' ملغاة بالفعل',
  'لا تُلغى التسوية مرتين'
);

select lives_ok($$select public.cancel_stock_adjustment(pg_temp.sa(3))$$, 'إلغاء تسوية الزيادة (عبوات)');

select results_eq(
  $$select (select count(*) from public.journal_lines where entry_id = pg_temp.reversal_of(pg_temp.sa_entry(3))),
           s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s where s.item_id = pg_temp.item('T-BOTTLE')$$,
  $$values (2::bigint, '500.000'::text, '1000.00'::text, '2.0000'::text)$$,
  'إلغاء الزيادة بلا فرق تكلفة، والرصيد يعود 500 بقيمة 1,000'
);

select throws_ok(
  $$select public.cancel_journal_entry(pg_temp.pi_entry(1))$$,
  'P0001', 'هذا القيد يُلغى من خلال المستند المرتبط به',
  'قيد الفاتورة لا يُلغى من شاشة القيود'
);

select lives_ok($$select public.cancel_purchase_invoice(pg_temp.pi(2))$$, 'إلغاء الفاتورة المدفوعة الآن');

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.reversal_of(pg_temp.pi_entry(2)))$$,
  $$values ('1301'::text, '0.00'::text, '5021.00'::text, null::text),
           ('2101', '5021.00', '0.00', 'م1 اختبار')$$,
  'القيد العكسي للفاتورة بنفس الحسابات والمورد'
);

select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('T-LABSA', 'T-SALT')
    order by i.code collate "C"$$,
  $$values ('T-LABSA'::text, '84.000'::text, '3280.00'::text, '39.0476'::text),
           ('T-SALT', '100.000', '500.00', '5.0000')$$,
  'الإلغاء يُخرج تكلفة الفاتورة الأصلية (5,000 و21) والمتوسط يُحسب من الباقي'
);

select results_eq(
  $$select not exists (select 1 from public.journal_entries r
                       where r.reverses_entry_id = (select v.journal_entry_id from public.vouchers v
                                                    where v.id = (select payment_voucher_id from public.purchase_invoices
                                                                  where id = pg_temp.pi(2)))),
           (select balance from public.party_balances('supplier') where party_id = pg_temp.supp('م1 اختبار'))$$,
  $$values (true, '-479.00'::text)$$,
  'سند «مدفوع الآن» يبقى ساريًا بعد إلغاء الفاتورة (يُلغى منفصلًا عند الحاجة)'
);

select throws_ok(
  $$select public.cancel_purchase_invoice(pg_temp.pi(2))$$,
  'P0001', 'فاتورة المشتريات رقم ' || ((select purchase_no from pg_temp._base) + 2) || ' ملغاة بالفعل',
  'لا تُلغى الفاتورة مرتين'
);

-- الإلغاء الذي يسبب رصيدًا سالبًا مرفوض
select public.post_purchase_invoice('1990-02-05', pg_temp.supp('م1 اختبار'),
  jsonb_build_array(pg_temp.pl('T-SLES', '10', '60')));
select public.post_stock_adjustment('1990-02-06', pg_temp.item('T-SLES'), '5');

select results_eq(
  $$select a.total_cost::text, s.qty::text, s.value::text, s.avg_cost::text
    from public.stock_adjustments a join public.item_stock s on s.item_id = a.item_id
    where a.id = pg_temp.sa(4)$$,
  $$values ('5345.45'::text, '5.000'::text, '254.55'::text, '50.9100'::text)$$,
  'عجز 105 بمتوسط 5,600 ÷ 110 = 5,345.45'
);

select throws_ok(
  $$select public.cancel_purchase_invoice(pg_temp.pi(3))$$,
  'P0001', 'لا يمكن الإلغاء: المتبقي من الصنف T-SLES - SLES اختبار هو 5 فقط، وكمية المستند 10',
  'إلغاء فاتورة صُرفت كميتها مرفوض (رصيد سالب)'
);

-- فرق تكلفة الإلغاء: الكمية تصير صفرًا والقيمة الباقية أقل من تكلفة الفاتورة
select public.post_purchase_invoice('1990-03-01', pg_temp.supp('م1 اختبار'),
  jsonb_build_array(pg_temp.pl('T-RES1', '10', '10')));
select public.post_purchase_invoice('1990-03-02', pg_temp.supp('م1 اختبار'),
  jsonb_build_array(pg_temp.pl('T-RES1', '10', '20')));
select public.post_stock_adjustment('1990-03-03', pg_temp.item('T-RES1'), '10');

select results_eq(
  $$select a.total_cost::text, s.qty::text, s.value::text, s.avg_cost::text
    from public.stock_adjustments a join public.item_stock s on s.item_id = a.item_id
    where a.id = pg_temp.sa(5)$$,
  $$values ('150.00'::text, '10.000'::text, '150.00'::text, '15.0000'::text)$$,
  'مادة فرق 1: متوسط 15 وصرف 10 بقيمة 150'
);

select lives_ok($$select public.cancel_purchase_invoice(pg_temp.pi(5))$$, 'إلغاء الفاتورة الأغلى بعد الصرف');

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.reversal_of(pg_temp.pi_entry(5)))$$,
  $$values ('1301'::text, '0.00'::text, '200.00'::text, null::text),
           ('2101', '200.00', '0.00', 'م1 اختبار'),
           ('1301', '50.00', '0.00', null),
           ('5201', '0.00', '50.00', null)$$,
  'القيد العكسي بالتكلفة الأصلية 200 + فرق 50: م المخزون / د فروقات الجرد'
);

select results_eq(
  $$select s.qty::text, s.value::text, s.avg_cost::text, m.qty_out::text, m.total_cost::text
    from public.item_stock s
    join public.stock_movements m on m.item_id = s.item_id and m.kind = 'reversal'
    where s.item_id = pg_temp.item('T-RES1')$$,
  $$values ('0.000'::text, '0.00'::text, '15.0000'::text, '10.000'::text, '150.00'::text)$$,
  'الحركة العكسية تُخرج القيمة الباقية بالضبط: الرصيد صفر بقيمة صفر (آخر متوسط محفوظ)'
);

select is(
  (select count(*) from public.journal_lines
   where entry_id = pg_temp.reversal_of(pg_temp.pi_entry(5))
     and description = 'فرق تكلفة الإلغاء (المخزون المتبقي بمتوسط مختلف)'),
  2::bigint,
  'سطرا فرق التكلفة موصوفان'
);

-- فرق التكلفة في الاتجاه الآخر: القيمة الباقية أكبر من تكلفة الفاتورة
select public.post_purchase_invoice('1990-03-01', pg_temp.supp('م1 اختبار'),
  jsonb_build_array(pg_temp.pl('T-RES2', '10', '30')));
select public.post_purchase_invoice('1990-03-02', pg_temp.supp('م1 اختبار'),
  jsonb_build_array(pg_temp.pl('T-RES2', '10', '10')));
select public.post_stock_adjustment('1990-03-03', pg_temp.item('T-RES2'), '10');

select results_eq(
  $$select a.total_cost::text, s.qty::text, s.value::text, s.avg_cost::text
    from public.stock_adjustments a join public.item_stock s on s.item_id = a.item_id
    where a.id = pg_temp.sa(6)$$,
  $$values ('200.00'::text, '10.000'::text, '200.00'::text, '20.0000'::text)$$,
  'مادة فرق 2: متوسط 20 وصرف 10 بقيمة 200'
);

select lives_ok($$select public.cancel_purchase_invoice(pg_temp.pi(7))$$, 'إلغاء الفاتورة الأرخص بعد الصرف');

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.reversal_of(pg_temp.pi_entry(7)))$$,
  $$values ('1301'::text, '0.00'::text, '100.00'::text, null::text),
           ('2101', '100.00', '0.00', 'م1 اختبار'),
           ('1301', '0.00', '100.00', null),
           ('5201', '100.00', '0.00', null)$$,
  'القيد العكسي بالتكلفة الأصلية 100 + فرق 100: م فروقات الجرد / د المخزون'
);

select results_eq(
  $$select * from pg_temp.stock('T-RES2')$$,
  $$values ('0.000'::text, '0.00'::text, '20.0000'::text)$$,
  'مادة فرق 2: الرصيد صفر بقيمة صفر'
);

-- إلغاء مخزون أول المدة مع حركاته
select public.post_stock_adjustment('1990-02-10', pg_temp.item('T-DISH'), '15');

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.sa_entry(7))$$,
  $$values ('5201'::text, '47.50'::text, '0.00'::text, null::text),
           ('1303', '0.00', '47.50', null)$$,
  'عجز المنتج التام على حساب مخزون المنتج التام'
);

select throws_ok(
  $$select public.cancel_journal_entry((select id from pg_temp._inv_open))$$,
  'P0001', 'لا يمكن الإلغاء: المتبقي من الصنف T-DISH - سائل أطباق 1 لتر اختبار هو 15 فقط، وكمية المستند 20',
  'إلغاء مخزون أول المدة بعد الصرف منه مرفوض'
);

select lives_ok($$select public.cancel_stock_adjustment(pg_temp.sa(7))$$, 'إلغاء عجز المنتج التام');
select lives_ok(
  $$select public.cancel_journal_entry((select id from pg_temp._inv_open))$$,
  'إلغاء قيد مخزون أول المدة من شاشة القيود'
);

select results_eq(
  $$select a.code, l.debit::text, l.credit::text
    from public.journal_lines l join public.accounts a on a.id = l.account_id
    where l.entry_id = pg_temp.reversal_of((select id from pg_temp._inv_open))
    order by a.code$$,
  $$values ('1301'::text, '0.00'::text, '123.45'::text),
           ('1303', '0.00', '190.00'),
           ('3101', '313.45', '0.00')$$,
  'القيد العكسي لمخزون أول المدة بلا فرق تكلفة'
);

select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('T-DISH', 'T-GLY')
    order by i.code collate "C"$$,
  $$values ('T-DISH'::text, '0.000'::text, '0.00'::text, '9.5000'::text),
           ('T-GLY', '0.000', '0.00', '12.3450')$$,
  'حركات مخزون أول المدة عُكست'
);

select results_eq(
  $$select part from public.active_openings() order by entry_no$$,
  $$values ('accounts'::text)$$,
  'بعد الإلغاء لا يبقى جزء مخزون نشط'
);

select lives_ok(
  $$select public.post_stock_opening('1990-01-01', jsonb_build_array(pg_temp.ol('T-DISH', '20', '10')), true)$$,
  'إعادة تسجيل مخزون أول المدة بعد إلغائه'
);

select results_eq(
  $$select (select string_agg(part, ',' order by entry_no) from public.active_openings()),
           s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s where s.item_id = pg_temp.item('T-DISH')$$,
  $$values ('accounts,inventory'::text, '20.000'::text, '200.00'::text, '10.0000'::text)$$,
  'مخزون أول المدة الجديد ساري'
);

-- قفل الفترة
reset role;
update public.settings set lock_date = '1990-02-28' where id = 1;
set local role authenticated;

select throws_ok(
  $$select public.cancel_stock_adjustment(pg_temp.sa(1))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 01/02/1990 لأن الفترة مقفولة حتى 28/02/1990',
  'إلغاء مستند مخزون في فترة مقفولة مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-02-15', pg_temp.supp('م1 اختبار'),
      jsonb_build_array(pg_temp.pl('T-LABSA', '1', '40')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 15/02/1990 لأن الفترة مقفولة حتى 28/02/1990',
  'فاتورة مشتريات في فترة مقفولة مرفوضة'
);
select throws_ok(
  $$select public.post_stock_adjustment('1990-02-20', pg_temp.item('T-LABSA'), '80')$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 20/02/1990 لأن الفترة مقفولة حتى 28/02/1990',
  'تسوية جرد في فترة مقفولة مرفوضة'
);

reset role;
update public.settings set lock_date = null where id = 1;
set local role authenticated;

select results_eq(
  $$select (select count(*) from public.purchase_invoices where doc_no > (select purchase_no from pg_temp._base)),
           (select max(doc_no) - (select purchase_no from pg_temp._base) from public.purchase_invoices),
           (select count(*) from public.stock_adjustments where doc_no > (select adjustment_no from pg_temp._base)),
           (select max(doc_no) - (select adjustment_no from pg_temp._base) from public.stock_adjustments)$$,
  $$values (7::bigint, 7::bigint, 7::bigint, 7::bigint)$$,
  'ترقيم الفواتير والتسويات متسلسل بلا فجوات'
);

-- ---------------------------------------------------------------------
-- 8) قواعد الأصناف
-- ---------------------------------------------------------------------
select throws_ok(
  $$update public.items set type = 'packaging' where code = 'T-LABSA'$$,
  'P0001', 'لا يمكن تغيير نوع صنف عليه حركات أو مستندات',
  'نوع الصنف ثابت بعد الحركات (يحدد حساب المخزون)'
);
select lives_ok(
  $$update public.items set type = 'raw_material', sale_price = null where code = 'T-NEW'$$,
  'نوع صنف بلا حركات يتغير'
);
select throws_ok(
  $$delete from public.items where code = 'T-LABSA'$$,
  '23503', null,
  'صنف عليه حركات لا يُحذف'
);
select lives_ok(
  $$delete from public.items where code = 'T-NEW'$$,
  'صنف بلا حركات يُحذف مع صف رصيده'
);

-- ---------------------------------------------------------------------
-- 9) دوال القراءة
-- ---------------------------------------------------------------------
select results_eq(
  $$select code, qty, avg_cost, value from public.stock_balances()
    where code like 'T-%' order by code collate "C"$$,
  $$values ('T-BOTTLE'::text, '500.000'::text, '2.0000'::text, '1000.00'::text),
           ('T-DISH', '20.000', '10.0000', '200.00'),
           ('T-GLY', '0.000', '12.3450', '0.00'),
           ('T-LABSA', '84.000', '39.0476', '3280.00'),
           ('T-OLD', '0.000', '0.0000', '0.00'),
           ('T-RES1', '0.000', '15.0000', '0.00'),
           ('T-RES2', '0.000', '20.0000', '0.00'),
           ('T-SALT', '100.000', '5.0000', '500.00'),
           ('T-SLES', '5.000', '50.9100', '254.55')$$,
  'أرصدة المخزون: كمية ومتوسط وقيمة لكل صنف'
);

select results_eq(
  $$select kind,
           doc_no - case source_type when 'purchase' then (select purchase_no from pg_temp._base)
                                      when 'stock_adjustment' then (select adjustment_no from pg_temp._base) end,
           qty_in, qty_out, total_cost, balance_qty, balance_value
    from public.item_movements(pg_temp.item('T-LABSA'), '1990-01-15', null)$$,
  $$values (null::text, null::bigint, null::text, null::text, null::text, '100.000'::text, '4000.00'::text),
           ('purchase', 2, '100.000', '0.000', '5000.00', '200.000', '9000.00'),
           ('reversal', 2, '0.000', '100.000', '5000.00', '100.000', '4000.00'),
           ('stock_adjustment', 1, '0.000', '16.000', '720.00', '84.000', '3280.00')$$,
  'حركة صنف: رصيد أول الفترة ثم رصيد جارٍ بالتاريخ، والحركة العكسية بتاريخ المستند'
);

select results_eq(
  $$select doc_no - (select purchase_no from pg_temp._base), total, is_cancelled, payment_voucher_id is not null
    from public.purchase_invoice_list(null, null, 'م1 اختبار')
    order by doc_no$$,
  $$values (1::bigint, '10500.00'::text, false, false),
           (2, '5021.00', true, true),
           (3, '600.00', false, false),
           (4, '100.00', false, false),
           (5, '200.00', true, false),
           (6, '300.00', false, false),
           (7, '100.00', true, false)$$,
  'قائمة فواتير المشتريات بحالة الإلغاء والسند المرتبط'
);

select results_eq(
  $$select doc_no - (select adjustment_no from pg_temp._base), item_code, system_qty, counted_qty, total_cost,
           is_cancelled
    from public.stock_adjustment_list(null, null, 'T-')
    order by doc_no$$,
  $$values (1::bigint, 'T-LABSA'::text, '200.000'::text, '184.000'::text, '720.00'::text, false),
           (2, 'T-SALT', '103.000', '102.000', '5.06', true),
           (3, 'T-BOTTLE', '500.000', '510.000', '20.00', true),
           (4, 'T-SLES', '110.000', '5.000', '5345.45', false),
           (5, 'T-RES1', '20.000', '10.000', '150.00', false),
           (6, 'T-RES2', '20.000', '10.000', '200.00', false),
           (7, 'T-DISH', '20.000', '15.000', '47.50', true)$$,
  'قائمة تسويات الجرد بحالة الإلغاء'
);

select lives_ok($$set constraints all immediate$$, 'كل ما سبق يجتاز فحوص الـ commit بصلاحية المستخدم');
set constraints all deferred;

-- ---------------------------------------------------------------------
-- 10) المطابقة
-- ---------------------------------------------------------------------
select is_empty(
  $$select s.item_id
    from public.item_stock s
    left join (select item_id, sum(qty_in - qty_out) as qty,
                      sum(case when qty_in > 0 then total_cost else -total_cost end) as value
               from public.stock_movements group by item_id) m on m.item_id = s.item_id
    where s.qty <> coalesce(m.qty, 0) or s.value <> coalesce(m.value, 0)$$,
  'رصيد كل صنف = مجموع حركاته (كمية وقيمة)'
);

select is_empty(
  $$with inv as (
      select account_id, case key when 'inventory_raw' then 'raw_material'
                                  when 'inventory_packaging' then 'packaging' else 'finished_good' end as item_type
      from public.system_accounts where key in ('inventory_raw', 'inventory_packaging', 'inventory_finished')
    ),
    gl as (
      select l.entry_id, l.account_id, sum(l.debit - l.credit) as amount
      from public.journal_lines l join inv on inv.account_id = l.account_id
      group by l.entry_id, l.account_id
    ),
    mv as (
      select m.journal_entry_id as entry_id, inv.account_id,
             sum(case when m.qty_in > 0 then m.total_cost else -m.total_cost end) as amount
      from public.stock_movements m
      join public.items i on i.id = m.item_id
      join inv on inv.item_type = i.type
      group by m.journal_entry_id, inv.account_id
    )
    select * from gl full join mv using (entry_id, account_id)
    where coalesce(gl.amount, 0) <> coalesce(mv.amount, 0)$$,
  'كل قيد: سطور حسابات المخزون = قيمة حركاته لكل نوع'
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
  $$values ('1301'::text, '4034.55'::text, '4034.55'::text),
           ('1302', '1000.00', '1000.00'),
           ('1303', '200.00', '200.00')$$,
  'رصيد كل حساب مخزون في الأستاذ = قيمة أصناف نوعه'
);

select results_eq(
  $$select (select sum(balance::numeric) from public.party_balances('supplier'))::text,
           (select sum(debit - credit) from public.journal_lines where account_id = pg_temp.acc('2101'))::text,
           (select balance from public.party_balances('supplier') where party_id = pg_temp.supp('م1 اختبار'))$$,
  $$values ('-1479.00'::text, '-1479.00'::text, '-1479.00'::text)$$,
  'أرصدة الموردين = رصيد حساب الموردين في الأستاذ'
);

select results_eq(
  $$select sum(debit::numeric)::text, sum(credit::numeric)::text from public.trial_balance()$$,
  $$values ('151679.00'::text, '151679.00'::text)$$,
  'ميزان المراجعة متوازن (151,679)'
);

-- ---------------------------------------------------------------------
-- 11) داخل قاعدة البيانات: الإدخال المباشر (كمالك الجداول) يُرفض عند الـ commit أو فورًا
-- ---------------------------------------------------------------------
reset role;

select throws_ok(
  $$select pg_temp.inventory_line_without_movement()$$,
  'P0001', 'قيد المخزون لا يطابق حركات المخزون على حساب 1301 - مخزون مواد خام (القيد رقم -201)',
  'سطر على حساب مخزون بلا حركات مخزون مرفوض'
);
set constraints all deferred;

select throws_like(
  $$select pg_temp.movement_without_stock()$$,
  'رصيد الصنف T-LABSA - LABSA اختبار لا يطابق مجموع حركاته%',
  'حركة مخزون بلا تحديث رصيد الصنف مرفوضة'
);
set constraints all deferred;

select throws_ok(
  $$select pg_temp.edit_stock()$$,
  'P0001', 'رصيد الصنف T-LABSA - LABSA اختبار لا يطابق مجموع حركاته (الرصيد 84.000 بقيمة 3,281.00، والحركات 84.000 بقيمة 3,280.00)',
  'تعديل رصيد الصنف مباشرة مرفوض'
);
set constraints all deferred;

select throws_like(
  $$select pg_temp.movement_wrong_type()$$,
  'قيد المخزون لا يطابق حركات المخزون على حساب % (القيد رقم -203)',
  'حركة صنف تعبئة مقابل سطر مخزون خام مرفوضة'
);
set constraints all deferred;

select throws_ok(
  $$select private.issue_cost(pg_temp.item('T-LABSA'), 84.001)$$,
  'P0001', 'الكمية المتاحة من الصنف T-LABSA - LABSA اختبار هي 84 فقط',
  'الصرف بأكثر من الرصيد مرفوض (تستخدمه مستندات الصرف في المراحل التالية)'
);

select throws_ok(
  $$update public.item_stock set qty = 0 where item_id = pg_temp.item('T-LABSA')$$,
  '23514', null,
  'رصيد بكمية صفر وقيمة موجبة مرفوض'
);

select throws_ok(
  $$update public.stock_movements set total_cost = 0 where journal_entry_id = pg_temp.pi_entry(1)$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'حركات المخزون لا تُعدَّل'
);
select throws_ok(
  $$delete from public.purchase_invoices where id = pg_temp.pi(1)$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'فاتورة المشتريات لا تُحذف'
);
select throws_ok(
  $$update public.purchase_invoice_lines set qty = 1 where invoice_id = pg_temp.pi(1)$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'سطور فاتورة المشتريات لا تُعدَّل'
);
select throws_ok(
  $$delete from public.stock_adjustments where id = pg_temp.sa(1)$$,
  'P0001', 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد',
  'تسوية الجرد لا تُحذف'
);

select * from finish();
rollback;
