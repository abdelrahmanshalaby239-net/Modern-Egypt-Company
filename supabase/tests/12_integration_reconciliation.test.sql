-- =====================================================================
-- اختبار التكامل والمطابقة (بعد المراحل 5–7): سيناريو واحد عبر كل المراحل — سنة مالية، مخزون أول المدة
-- بالتكلفة المقترحة أو المعدّلة، شراء ببرميل وكرتونة، إنتاج بالكرتونة، بيع بالكرتونة والقطعة، تسوية جرد،
-- سندات، قيد يدوي، قفل شهري، إلغاء شراء وإنتاج وبيع، ثم إقفال السنة. وفي كل نقطة فحص تُختبر ضمانات
-- المطابقة كلها. تعمل داخل transaction تُلغى في النهاية.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(37);

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
create function pg_temp.lock() returns text language sql stable as $$
  select lock_date::text from public.settings where id = 1;
$$;
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
-- سطر شراء أو بيع بوحدة (فارغ = الأساسية)
create function pg_temp.ul(p_code text, p_qty text, p_price text, p_unit text default null) returns jsonb
language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'unit_id', pg_temp.unit(p_code, p_unit),
                            'qty', p_qty, 'unit_price', p_price);
$$;
-- سطر وصفة أو استهلاك بوحدة
create function pg_temp.fl(p_code text, p_qty text, p_unit text default null) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'unit_id', pg_temp.unit(p_code, p_unit),
                            'qty_per_batch', p_qty, 'qty', p_qty);
$$;
create function pg_temp.stock(p_code text) returns table (qty text, value text) language sql stable as $$
  select qty::text, value::text from public.item_stock where item_id = pg_temp.item(p_code);
$$;
create function pg_temp.formula() returns bigint language sql stable as $$
  select id from public.formulas where name = 'سائل أطباق تكامل اختبار';
$$;
create function pg_temp.last_doc(p_table text) returns bigint language plpgsql stable as $$
declare v bigint;
begin
  execute format('select id from public.%I order by id desc limit 1', p_table) into v;
  return v;
end;
$$;

-- ضمانات المطابقة (خطة المراحل 5–7): الصنف = حركاته، سطور مخزون كل قيد = حركاته، كل حساب مخزون = قيمة
-- أصناف نوعه، العملاء = 1201 والموردون = 2101، الميزان متوازن، أرباح الأصناف = 4101 − 5101 من قيود المبيعات،
-- والمنتج التام المضاف = المواد المصروفة + التكاليف الإضافية لكل أمر إنتاج.
create function pg_temp.guarantees(p_from date, p_to date)
returns table (check_name text, ok boolean) language sql stable as $$
  with inv as (
    select s.account_id,
           case s.key when 'inventory_raw' then 'raw_material' when 'inventory_packaging' then 'packaging'
                      else 'finished_good' end as item_type
    from public.system_accounts s
    where s.key in ('inventory_raw', 'inventory_packaging', 'inventory_finished')
  ),
  entry_lines as (
    select l.entry_id, l.account_id, sum(l.debit - l.credit) as amount
    from public.journal_lines l join inv on inv.account_id = l.account_id
    group by l.entry_id, l.account_id
  ),
  entry_moves as (
    select m.journal_entry_id as entry_id, inv.account_id,
           sum(case when m.qty_in > 0 then m.total_cost else -m.total_cost end) as amount
    from public.stock_movements m join public.items i on i.id = m.item_id join inv on inv.item_type = i.type
    group by m.journal_entry_id, inv.account_id
  ),
  sale_entries as (
    select e.id from public.journal_entries e
    where e.entry_date between p_from and p_to
      and (e.source_type = 'sale'
           or exists (select 1 from public.journal_entries o where o.id = e.reverses_entry_id and o.source_type = 'sale'))
  )
  select '1. رصيد كل صنف = مجموع حركاته', not exists (
    select 1 from public.item_stock s
    left join (select item_id, sum(qty_in - qty_out) as qty,
                      sum(case when qty_in > 0 then total_cost else -total_cost end) as value
               from public.stock_movements group by item_id) m on m.item_id = s.item_id
    where s.qty <> coalesce(m.qty, 0) or s.value <> coalesce(m.value, 0))
  union all
  select '2. سطور المخزون في كل قيد = قيمة حركاته', not exists (
    select 1 from entry_lines l full join entry_moves m using (entry_id, account_id)
    where coalesce(l.amount, 0) <> coalesce(m.amount, 0))
  union all
  select '3. كل حساب مخزون = قيمة أصناف نوعه', not exists (
    select 1 from inv
    where (select coalesce(sum(debit - credit), 0) from public.journal_lines where account_id = inv.account_id)
          <> (select coalesce(sum(s.value), 0) from public.item_stock s join public.items i on i.id = s.item_id
              where i.type = inv.item_type))
  union all
  select '4أ. العملاء = حساب العملاء',
    (select coalesce(sum(balance::numeric), 0) from public.party_balances('customer'))
    = (select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l
       join public.system_accounts s on s.account_id = l.account_id and s.key = 'receivables')
  union all
  select '4ب. الموردون = حساب الموردين',
    (select coalesce(sum(balance::numeric), 0) from public.party_balances('supplier'))
    = (select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l
       join public.system_accounts s on s.account_id = l.account_id and s.key = 'payables')
  union all
  select '4ج. ميزان المراجعة متوازن',
    (select coalesce(sum(debit::numeric), 0) = coalesce(sum(credit::numeric), 0) from public.trial_balance())
  union all
  select '5. أرباح الأصناف = إيرادات المبيعات − تكلفتها من قيود المبيعات',
    (select coalesce(sum(profit::numeric), 0) from public.item_profit(p_from, p_to))
    = (select coalesce(sum(l.credit - l.debit), 0)
       from public.journal_lines l join public.system_accounts s on s.account_id = l.account_id
       where s.key in ('sales_revenue', 'cogs') and l.entry_id in (select id from sale_entries))
  union all
  select '7. المنتج التام المضاف = المواد المصروفة + التكاليف الإضافية', not exists (
    select 1 from public.production_orders o
    where o.total_cost <> o.materials_cost + o.extra_cost
       or o.total_cost <> (select coalesce(sum(m.total_cost), 0) from public.stock_movements m
                           where m.journal_entry_id = o.journal_entry_id and m.qty_in > 0)
       or o.materials_cost <> (select coalesce(sum(m.total_cost), 0) from public.stock_movements m
                               where m.journal_entry_id = o.journal_entry_id and m.qty_out > 0));
$$;
-- 6. صافي ربح قائمة الدخل = صف الربح غير المقفل في الميزانية (قبل الإقفال)
create function pg_temp.net_profit(p_from date, p_to date) returns table (income_statement text, balance_sheet text)
language sql stable as $$
  select (select coalesce(sum(case when section in ('sales', 'other_revenue') then amount::numeric
                                   else -amount::numeric end), 0)
          from public.income_statement(p_from, p_to))::text,
         (select amount from public.balance_sheet(p_to) where account_id is null);
$$;

-- ---------------------------------------------------------------------
-- السنة المالية والبيانات الأساسية
-- ---------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_admin();
select lives_ok(
  $$select public.save_open_fiscal_year('السنة المالية 1995', '1995-01-01', '1995-12-31')$$,
  'تعريف السنة المالية 1995'
);

select pg_temp.as_accountant();
select public.save_item(jsonb_build_object('code', 'I-LABSA', 'name', 'LABSA تكامل اختبار', 'type', 'raw_material',
  'unit', 'كجم'), jsonb_build_array(jsonb_build_object('name', 'برميل', 'factor', '200')));
select public.save_item(jsonb_build_object('code', 'I-SALT', 'name', 'ملح تكامل اختبار', 'type', 'raw_material',
  'unit', 'كجم', 'default_cost', '4.5'), '[]'::jsonb);
select public.save_item(jsonb_build_object('code', 'I-BOTTLE', 'name', 'عبوة تكامل اختبار', 'type', 'packaging',
  'unit', 'قطعة'), jsonb_build_array(jsonb_build_object('name', 'كرتونة', 'factor', '50')));
select public.save_item(jsonb_build_object('code', 'I-DISH', 'name', 'سائل أطباق تكامل اختبار', 'type', 'finished_good',
  'unit', 'عبوة', 'sale_price', '18', 'default_cost', '9'),
  jsonb_build_array(jsonb_build_object('name', 'كرتونة', 'factor', '12', 'sale_price', '200', 'is_default', true)));
insert into public.customers (name) values ('ع1 تكامل اختبار'), ('ع2 تكامل اختبار');
insert into public.suppliers (name) values ('م1 تكامل اختبار');

-- ---------------------------------------------------------------------
-- نقطة فحص 1: الأرصدة الافتتاحية ومخزون أول المدة والشراء بالوحدات
-- ---------------------------------------------------------------------
select public.post_opening_balances('1995-01-01', jsonb_build_array(
  pg_temp.line('1101', '200000', '0'), pg_temp.line('3101', '0', '200000')));
select lives_ok(
  $$select public.post_stock_opening('1995-01-01', jsonb_build_array(
      jsonb_build_object('item_id', pg_temp.item('I-SALT'), 'qty', '100',
                         'unit_cost', (select default_cost::text from public.items where code = 'I-SALT')),
      jsonb_build_object('item_id', pg_temp.item('I-DISH'), 'qty', '20', 'unit_cost', '9.5')), true)$$,
  'مخزون أول المدة: الملح بالتكلفة المقترحة 4.5، والمنتج بتكلفة معدّلة 9.5 (الافتراضية 9)'
);
select results_eq(
  $$select (select sum(credit - debit) from public.journal_lines where account_id = pg_temp.acc('3101'))::text,
           (select default_cost::text from public.items where code = 'I-DISH')$$,
  $$values ('200640.00'::text, '9.0000'::text)$$,
  'رأس المال = 200,000 + قيمة مخزون أول المدة 640 مرة واحدة، والتكلفة الافتراضية لم تتغير'
);
select public.post_purchase_invoice('1995-01-10', pg_temp.supp('م1 تكامل اختبار'), jsonb_build_array(
  pg_temp.ul('I-LABSA', '2', '8000', 'برميل'), pg_temp.ul('I-BOTTLE', '10', '100', 'كرتونة')),
  null, '5000', pg_temp.acc('1101'));
select results_eq(
  $$select (select qty || '/' || value from pg_temp.stock('I-LABSA')), (select qty || '/' || value from pg_temp.stock('I-BOTTLE'))$$,
  $$values ('400.000/16000.00'::text, '500.000/1000.00'::text)$$,
  'الشراء ببرميلين = 400 كجم، و10 كراتين = 500 قطعة (المخزون بالوحدة الأساسية)'
);
select lives_ok($$set constraints all immediate$$, 'نقطة فحص 1: فحوص الـ commit');
set constraints all deferred;
select results_eq(
  $$select check_name, ok from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  $$select check_name, true from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  'نقطة فحص 1: كل ضمانات المطابقة'
);

-- ---------------------------------------------------------------------
-- نقطة فحص 2: الإنتاج بالكرتونة بتكاليف إضافية على المصروفات المستحقة
-- ---------------------------------------------------------------------
select public.save_formula(null, 'سائل أطباق تكامل اختبار', pg_temp.item('I-DISH'), '10', pg_temp.unit('I-DISH', 'كرتونة'),
  jsonb_build_array(pg_temp.fl('I-LABSA', '9.6'), pg_temp.fl('I-SALT', '3'), pg_temp.fl('I-BOTTLE', '2.4', 'كرتونة')));
select lives_ok(
  $$select public.post_production_order('1995-02-05', pg_temp.formula(), '2', '20', pg_temp.unit('I-DISH', 'كرتونة'),
      jsonb_build_array(pg_temp.fl('I-LABSA', '19.2'), pg_temp.fl('I-SALT', '6'), pg_temp.fl('I-BOTTLE', '4.8', 'كرتونة')),
      '120', pg_temp.acc('2201'))$$,
  'إنتاج 20 كرتونة (240 عبوة) + تكاليف إضافية 120'
);
select results_eq(
  $$select materials_cost::text, total_cost::text, base_qty_produced::text, unit_cost::text
    from public.production_orders where id = pg_temp.last_doc('production_orders')$$,
  $$values ('1275.00'::text, '1395.00'::text, '240.000'::text, '5.8125'::text)$$,
  'المواد 768 + 27 + 480 = 1,275، والإجمالي 1,395، وتكلفة العبوة 5.8125'
);
select results_eq($$select * from pg_temp.stock('I-DISH')$$, $$values ('260.000'::text, '1585.00'::text)$$,
  'المنتج: 20 (أول المدة 190) + 240 (1,395) = 260 بقيمة 1,585');
select lives_ok($$set constraints all immediate$$, 'نقطة فحص 2: فحوص الـ commit');
set constraints all deferred;
select results_eq(
  $$select check_name, ok from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  $$select check_name, true from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  'نقطة فحص 2: كل ضمانات المطابقة'
);

-- ---------------------------------------------------------------------
-- نقطة فحص 3: البيع بالكرتونة والقطعة مع تحصيل جزئي، وسند قبض لاحق
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_sales_invoice('1995-02-10', pg_temp.cust('ع1 تكامل اختبار'), jsonb_build_array(
      pg_temp.ul('I-DISH', '10', '200', 'كرتونة'), pg_temp.ul('I-DISH', '6', '18')), null, '1000', pg_temp.acc('1101'))$$,
  'بيع 10 كراتين + 6 عبوات (126 عبوة) بـ 2,108، مقبوض منها 1,000'
);
select results_eq(
  $$select sum(cost_total)::text, (select qty || '/' || value from pg_temp.stock('I-DISH'))
    from public.sales_invoice_lines where invoice_id = pg_temp.last_doc('sales_invoices')$$,
  $$values ('768.12'::text, '134.000/816.88'::text)$$,
  'تكلفة 126 عبوة = 126 × 1,585 ÷ 260 = 768.12، والباقي 134 بقيمة 816.88'
);
select public.post_voucher('receipt', '1995-02-12', pg_temp.acc('1101'), 'customer', pg_temp.cust('ع1 تكامل اختبار'), '500');
select lives_ok($$set constraints all immediate$$, 'نقطة فحص 3: فحوص الـ commit');
set constraints all deferred;
select results_eq(
  $$select check_name, ok from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  $$select check_name, true from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  'نقطة فحص 3: كل ضمانات المطابقة'
);

-- ---------------------------------------------------------------------
-- نقطة فحص 4: تسوية جرد، سندات، قيد يدوي، قفل شهري
-- ---------------------------------------------------------------------
select public.post_stock_adjustment('1995-02-15', pg_temp.item('I-SALT'), '90');
select public.post_voucher('payment', '1995-02-20', pg_temp.acc('1101'), 'supplier', pg_temp.supp('م1 تكامل اختبار'), '3000');
select public.post_voucher('payment', '1995-02-20', pg_temp.acc('1101'), 'account', pg_temp.acc('6201'), '300');
select public.post_journal_entry('1995-02-25', 'أجور مستحقة', 'manual', jsonb_build_array(
  pg_temp.line('6101', '1000', '0'), pg_temp.line('2201', '0', '1000')));
select pg_temp.as_admin();
select lives_ok($$select public.lock_period('1995-01-31')$$, 'قفل يناير 1995');
select pg_temp.as_accountant();
select throws_ok(
  $$select public.post_voucher('payment', '1995-01-20', pg_temp.acc('1101'), 'account', pg_temp.acc('6201'), '10')$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 20/01/1995 لأن الفترة مقفولة حتى 31/01/1995',
  'لا تسجيل في يناير المقفول'
);
select results_eq($$select * from pg_temp.stock('I-SALT')$$, $$values ('90.000'::text, '405.00'::text)$$,
  'عجز الملح 4 كجم بمتوسط 4.5 = 18 على فروقات الجرد');
select lives_ok($$set constraints all immediate$$, 'نقطة فحص 4: فحوص الـ commit');
set constraints all deferred;
select results_eq(
  $$select check_name, ok from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  $$select check_name, true from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  'نقطة فحص 4: كل ضمانات المطابقة'
);

-- ---------------------------------------------------------------------
-- نقطة فحص 5: إلغاء شراء وإنتاج وبيع، وإعادة إدخال البيع بلا تحصيل مكرر
-- ---------------------------------------------------------------------
select public.post_purchase_invoice('1995-03-01', pg_temp.supp('م1 تكامل اختبار'),
  jsonb_build_array(pg_temp.ul('I-SALT', '50', '6')));
select public.post_production_order('1995-03-05', pg_temp.formula(), '1', '10', pg_temp.unit('I-DISH', 'كرتونة'),
  jsonb_build_array(pg_temp.fl('I-LABSA', '9.6'), pg_temp.fl('I-SALT', '3'), pg_temp.fl('I-BOTTLE', '2.4', 'كرتونة')));
select public.post_sales_invoice('1995-03-06', pg_temp.cust('ع2 تكامل اختبار'),
  jsonb_build_array(pg_temp.ul('I-DISH', '5', '200', 'كرتونة')), null, '400', pg_temp.acc('1102'));
select results_eq(
  $$select (select materials_cost::text from public.production_orders where id = pg_temp.last_doc('production_orders')),
           (select sum(cost_total)::text from public.sales_invoice_lines where invoice_id = pg_temp.last_doc('sales_invoices'))$$,
  $$values ('639.11'::text, '343.93'::text)$$,
  'إنتاج ثانٍ بمتوسط الملح الجديد (639.11)، وبيع 60 عبوة بالمتوسط الجديد (343.93)'
);
select lives_ok(
  $$select public.cancel_purchase_invoice(pg_temp.last_doc('purchase_invoices'))$$,
  'إلغاء فاتورة شراء الملح (صُرف جزء منه في الإنتاج والباقي يكفي)'
);
select lives_ok(
  $$select public.cancel_production_order(pg_temp.last_doc('production_orders'))$$,
  'إلغاء أمر الإنتاج الثاني (المنتج يكفي رغم البيع بعده)'
);
select lives_ok(
  $$select public.cancel_sales_invoice(pg_temp.last_doc('sales_invoices'))$$,
  'إلغاء فاتورة البيع الثانية (سند القبض 400 يبقى)'
);
select results_eq(
  $$select (select qty || '/' || value from pg_temp.stock('I-SALT')), (select qty || '/' || value from pg_temp.stock('I-DISH')),
           (select balance from public.party_balances('customer') where party_id = pg_temp.cust('ع2 تكامل اختبار'))$$,
  $$values ('90.000/405.00'::text, '134.000/816.88'::text, '-400.00'::text)$$,
  'بعد الإلغاءات: الملح والمنتج كما قبلها، والمقبوض 400 رصيد دائن للعميل ع2'
);
select lives_ok(
  $$select public.post_sales_invoice('1995-03-06', pg_temp.cust('ع2 تكامل اختبار'),
      jsonb_build_array(pg_temp.ul('I-DISH', '5', '200', 'كرتونة')), 'تصحيح')$$,
  'الفاتورة المصححة بمقبوض صفر'
);
select results_eq(
  $$select balance from public.party_balances('customer') where party_id = pg_temp.cust('ع2 تكامل اختبار')$$,
  $$values ('600.00'::text)$$,
  'رصيد ع2 = 1,000 − 400 (لا تحصيل مكرر)'
);
select lives_ok($$set constraints all immediate$$, 'نقطة فحص 5: فحوص الـ commit');
set constraints all deferred;
select results_eq(
  $$select check_name, ok from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  $$select check_name, true from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  'نقطة فحص 5: كل ضمانات المطابقة'
);

-- ---------------------------------------------------------------------
-- نقطة فحص 6: قبل الإقفال — صافي الربح متطابق في قائمة الدخل والميزانية ومعاينة الإقفال
-- ---------------------------------------------------------------------
select results_eq(
  $$select section, sum(amount::numeric)::text from public.income_statement('1995-01-01', '1995-12-31')
    group by section order by section$$,
  $$values ('cost_of_sales'::text, '1151.89'::text), ('expenses', '1300.00'), ('sales', '3108.00')$$,
  'قائمة الدخل: مبيعات 3,108، تكلفة مبيعات 1,133.89 + عجز جرد 18، مصروفات 1,300 (التكاليف الإضافية للإنتاج ليست مصروفًا)'
);
select results_eq(
  $$select income_statement, balance_sheet,
           (select credit from public.fiscal_year_closing_preview() where account_id = pg_temp.acc('3301'))
    from pg_temp.net_profit('1995-01-01', '1995-12-31')$$,
  $$values ('656.11'::text, '656.11'::text, '656.11'::text)$$,
  'صافي الربح 656.11 = ربح الميزانية غير المقفل = سطر الأرباح المرحّلة في معاينة الإقفال'
);
select results_eq(
  $$select sum(amount::numeric) filter (where section = 'asset') = sum(amount::numeric) filter (where section <> 'asset')
    from public.balance_sheet('1995-12-31')$$,
  $$values (true)$$,
  'الأصول = الخصوم + حقوق الملكية قبل الإقفال'
);

-- ---------------------------------------------------------------------
-- نقطة فحص 7: بعد الإقفال
-- ---------------------------------------------------------------------
select pg_temp.as_admin();
select lives_ok($$select public.close_fiscal_year()$$, 'إقفال السنة المالية 1995');
select results_eq(
  $$select (select count(*) from public.trial_balance('1995-12-31') where type in ('revenue', 'expense')),
           (select sum(credit - debit) from public.journal_lines where account_id = pg_temp.acc('3301'))::text,
           (select sum(amount::numeric) filter (where section = 'asset')
                   = sum(amount::numeric) filter (where section <> 'asset') from public.balance_sheet('1995-12-31')),
           pg_temp.lock()$$,
  $$values (0::bigint, '656.11'::text, true, '1995-12-31'::text)$$,
  'بعد الإقفال: الإيرادات والمصروفات صفر، الأرباح المرحّلة = صافي الربح، الميزانية متوازنة، والقفل = نهاية السنة'
);
select pg_temp.as_accountant();
select throws_ok(
  $$select public.post_sales_invoice('1995-12-31', pg_temp.cust('ع1 تكامل اختبار'),
      jsonb_build_array(pg_temp.ul('I-DISH', '1', '18')))$$,
  'P0001', 'لا يمكن التسجيل بتاريخ 31/12/1995 لأن الفترة مقفولة حتى 31/12/1995',
  'لا مستند بتاريخ ≤ نهاية السنة المقفلة'
);
select lives_ok($$set constraints all immediate$$, 'نقطة فحص 7: فحوص الـ commit');
set constraints all deferred;
select results_eq(
  $$select check_name, ok from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  $$select check_name, true from pg_temp.guarantees('1995-01-01', '1995-12-31')$$,
  'نقطة فحص 7: كل ضمانات المطابقة بعد الإقفال'
);

reset role;
select * from finish();
rollback;
