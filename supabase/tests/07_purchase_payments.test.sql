-- =====================================================================
-- اختبارات سداد فاتورة المشتريات (المرحلة 4، تعديل): آجل بالكامل، سداد جزئي، سداد كامل،
-- رفض الزيادة عن الإجمالي، سند الصرف المربوط، إلغاء كل شيء عند الفشل، الإلغاء مع بقاء السداد
-- دفعة مقدمة للمورد، والمطابقة مع الأستاذ. تعمل داخل transaction تُلغى في النهاية.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(40);

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

create function pg_temp.pl(p_code text, p_qty text, p_price text) returns jsonb language sql stable as $$
  select jsonb_build_object('item_id', pg_temp.item(p_code), 'qty', p_qty, 'unit_price', p_price);
$$;

-- الفاتورة رقم n (نسبةً لبداية الاختبار) وقيدها وقيد سندها
create function pg_temp.pi(p_n int) returns bigint language sql stable as $$
  select id from public.purchase_invoices where doc_no = (select purchase_no from pg_temp._base) + p_n;
$$;

create function pg_temp.pi_entry(p_n int) returns bigint language sql stable as $$
  select journal_entry_id from public.purchase_invoices where id = pg_temp.pi(p_n);
$$;

create function pg_temp.pi_voucher_entry(p_n int) returns bigint language sql stable as $$
  select v.journal_entry_id from public.vouchers v
  join public.purchase_invoices p on p.payment_voucher_id = v.id
  where p.id = pg_temp.pi(p_n);
$$;

create function pg_temp.reversal_of(p_entry bigint) returns bigint language sql stable as $$
  select id from public.journal_entries where reverses_entry_id = p_entry;
$$;

create function pg_temp.entry_lines(p_entry bigint)
returns table (code text, debit text, credit text, party text) language sql stable as $$
  select a.code, l.debit::text, l.credit::text, s.name
  from public.journal_lines l
  join public.accounts a on a.id = l.account_id
  left join public.suppliers s on s.id = l.supplier_id
  where l.entry_id = p_entry
  order by l.id;
$$;

-- رصيد المورد الحالي من القيود (مدين موجب = دفعة مقدمة، دائن سالب = مستحق له)
create function pg_temp.sbal(p_name text) returns text language sql stable as $$
  select balance from public.party_balances('supplier') where party_id = pg_temp.supp(p_name);
$$;

-- لقطة من كل ما يكتبه اعتماد الفاتورة (للتأكد أن الفشل لا يترك أثرًا ولا يستهلك أرقامًا)
create function pg_temp.state()
returns table (invoices bigint, entries bigint, lines bigint, movements bigint, vouchers bigint,
               raw_qty text, raw_value text, purchase_no bigint, payment_no bigint, journal_no bigint)
language sql stable as $$
  select (select count(*) from public.purchase_invoices),
         (select count(*) from public.journal_entries),
         (select count(*) from public.journal_lines),
         (select count(*) from public.stock_movements),
         (select count(*) from public.vouchers),
         (select qty::text from public.item_stock where item_id = pg_temp.item('P-RAW')),
         (select value::text from public.item_stock where item_id = pg_temp.item('P-RAW')),
         (select last_no from public.doc_counters where kind = 'purchase_invoice'),
         (select last_no from public.doc_counters where kind = 'payment_voucher'),
         (select last_no from public.doc_counters where kind = 'journal');
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

insert into public.items (code, name, type, unit) values
  ('P-RAW', 'خام سداد اختبار', 'raw_material', 'كجم'),
  ('P-PACK', 'تعبئة سداد اختبار', 'packaging', 'قطعة');
insert into public.suppliers (name) values ('م سداد اختبار'), ('م مقدم اختبار');
select public.post_opening_balances('1990-01-01', jsonb_build_array(
  pg_temp.line('1101', '50000', '0'), pg_temp.line('1102', '10000', '0'), pg_temp.line('3101', '0', '60000')));

-- ---------------------------------------------------------------------
-- 1) آجل بالكامل: المدفوع الافتراضي صفر، ولا سند
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_purchase_invoice('1990-04-01', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '10', '40')))$$,
  'فاتورة آجلة بالكامل (بدون مبلغ مدفوع)'
);

select results_eq(
  $$select total::text, paid_amount::text, payment_voucher_id is null
    from public.purchase_invoices where id = pg_temp.pi(1)$$,
  $$values ('400.00'::text, '0.00'::text, true)$$,
  'المدفوع الافتراضي صفر ولا سند صرف'
);

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.pi_entry(1))$$,
  $$values ('1301'::text, '400.00'::text, '0.00'::text, null::text),
           ('2101', '0.00', '400.00', 'م سداد اختبار')$$,
  'الفاتورة الآجلة: الإجمالي كله على حساب المورد'
);

select lives_ok(
  $$select public.post_purchase_invoice('1990-04-02', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-PACK', '100', '2')), 'آجلة', '0', pg_temp.acc('1101'))$$,
  'مدفوع صفر صراحةً مع اختيار خزينة'
);

select results_eq(
  $$select (select paid_amount::text from public.purchase_invoices where id = pg_temp.pi(2)),
           (select payment_voucher_id is null from public.purchase_invoices where id = pg_temp.pi(2)),
           (select count(*) from public.vouchers
            where kind = 'payment' and doc_no > (select payment_no from pg_temp._base))$$,
  $$values ('0.00'::text, true, 0::bigint)$$,
  'المدفوع صفر لا ينشئ سند صرف ولا يستهلك رقم سند'
);

-- ---------------------------------------------------------------------
-- 2) سداد جزئي: الإجمالي على المورد، وسند صرف بالمدفوع فقط
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_purchase_invoice('1990-04-03', pg_temp.supp('م سداد اختبار'), jsonb_build_array(
      pg_temp.pl('P-RAW', '10', '50'), pg_temp.pl('P-PACK', '50', '2')), null, '300', pg_temp.acc('1101'))$$,
  'فاتورة 600 مدفوع منها 300 الآن'
);

select results_eq(
  $$select p.total::text, p.paid_amount::text, v.kind, v.doc_no - (select payment_no from pg_temp._base),
           v.amount::text, v.notes, s.name, a.code, v.doc_date = p.doc_date
    from public.purchase_invoices p
    join public.vouchers v on v.id = p.payment_voucher_id
    join public.suppliers s on s.id = v.supplier_id
    join public.accounts a on a.id = v.treasury_account_id
    where p.id = pg_temp.pi(3)$$,
  $$select '600.00'::text, '300.00'::text, 'payment'::text, 1::bigint, '300.00'::text,
           'سداد جزئي لفاتورة مشتريات رقم ' || ((select purchase_no from pg_temp._base) + 3),
           'م سداد اختبار'::text, '1101'::text, true$$,
  'سند صرف مربوط بالمدفوع فقط وبنفس تاريخ الفاتورة'
);

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.pi_entry(3))$$,
  $$values ('1301'::text, '500.00'::text, '0.00'::text, null::text),
           ('1302', '100.00', '0.00', null),
           ('2101', '0.00', '600.00', 'م سداد اختبار')$$,
  'قيد الفاتورة: كامل الإجمالي دائن على المورد'
);

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.pi_voucher_entry(3))$$,
  $$values ('2101'::text, '300.00'::text, '0.00'::text, 'م سداد اختبار'::text),
           ('1101', '0.00', '300.00', null)$$,
  'قيد السند: يسدد المدفوع فقط من حساب المورد'
);

select is(pg_temp.sbal('م سداد اختبار'), '-900.00', 'رصيد المورد = 400 + 200 + (600 − 300) دائن');

-- ---------------------------------------------------------------------
-- 3) سداد كامل من البنك
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_purchase_invoice('1990-04-04', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '5', '60')), null, '300', pg_temp.acc('1102'))$$,
  'فاتورة 300 مدفوعة بالكامل من البنك'
);

select results_eq(
  $$select p.paid_amount::text, v.amount::text, v.notes, a.code, v.doc_no - (select payment_no from pg_temp._base)
    from public.purchase_invoices p
    join public.vouchers v on v.id = p.payment_voucher_id
    join public.accounts a on a.id = v.treasury_account_id
    where p.id = pg_temp.pi(4)$$,
  $$select '300.00'::text, '300.00'::text,
           'سداد فاتورة مشتريات رقم ' || ((select purchase_no from pg_temp._base) + 4), '1102'::text, 2::bigint$$,
  'سداد كامل: سند بكامل الإجمالي من البنك والرقم التالي'
);

select is(pg_temp.sbal('م سداد اختبار'), '-900.00', 'الفاتورة المدفوعة بالكامل لا تغير رصيد المورد');

-- ---------------------------------------------------------------------
-- 4) الرفض، وإلغاء كل شيء عند الفشل (حتى بعد ترحيل قيد الفاتورة)
-- ---------------------------------------------------------------------
reset role;
create temp table _snap as select * from pg_temp.state();
set local role authenticated;

select throws_ok(
  $$select public.post_purchase_invoice('1990-04-05', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '1', '40')), null, '40.01', pg_temp.acc('1101'))$$,
  'P0001', 'المدفوع الآن 40.01 أكبر من إجمالي الفاتورة 40.00',
  'المدفوع أكبر من إجمالي الفاتورة مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-04-05', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '1', '40')), null, '10')$$,
  'P0001', 'اختر الخزينة أو البنك المدفوع منه',
  'مبلغ مدفوع بلا خزينة مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-04-05', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '1', '40')), null, '-5', pg_temp.acc('1101'))$$,
  'P0001', 'المدفوع الآن: المبلغ يجب أن يكون رقمًا موجبًا',
  'المدفوع السالب مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-04-05', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '1', '40')), null, '10.005', pg_temp.acc('1101'))$$,
  'P0001', 'المدفوع الآن: المبلغ لا يزيد عن خانتين عشريتين',
  'المدفوع بثلاث خانات عشرية مرفوض'
);
select throws_ok(
  $$select public.post_purchase_invoice('1990-04-05', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '1', '40')), null, 'abc', pg_temp.acc('1101'))$$,
  'P0001', 'المدفوع الآن: المبلغ "abc" غير صالح',
  'المدفوع غير الرقمي مرفوض'
);
-- الخزينة تُفحص عند إنشاء السند، أي بعد ترحيل قيد الفاتورة وحركات المخزون داخل نفس الدالة
select throws_ok(
  $$select public.post_purchase_invoice('1990-04-05', pg_temp.supp('م سداد اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '1', '40')), null, '10', pg_temp.acc('1501'))$$,
  'P0001', 'اختر خزينة أو بنكًا',
  'الدفع من حساب ليس خزينة مرفوض'
);

reset role;
select results_eq(
  $$select * from pg_temp.state()$$,
  $$select * from _snap$$,
  'الفشل لا يترك فاتورة ولا قيدًا ولا سندًا ولا حركة مخزون، ولا يستهلك أرقامًا'
);
set local role authenticated;

select results_eq(
  $$select doc_no - (select purchase_no from pg_temp._base), total, paid_amount, payment_voucher_id is not null,
           is_cancelled
    from public.purchase_invoice_list(null, null, 'م سداد اختبار')
    order by doc_no$$,
  $$values (1::bigint, '400.00'::text, '0.00'::text, false, false),
           (2, '200.00', '0.00', false, false),
           (3, '600.00', '300.00', true, false),
           (4, '300.00', '300.00', true, false)$$,
  'قائمة الفواتير: الإجمالي والمدفوع عند الاعتماد'
);

-- ---------------------------------------------------------------------
-- 5) سند لاحق غير مخصص لفاتورة: يغيّر رصيد المورد لا المدفوع عند الاعتماد
-- ---------------------------------------------------------------------
select lives_ok(
  $$select public.post_voucher('payment', '1990-04-10', pg_temp.acc('1101'), 'supplier',
      pg_temp.supp('م سداد اختبار'), '100', 'دفعة عامة')$$,
  'سند صرف مستقل للمورد'
);

select results_eq(
  $$select (select paid_amount::text from public.purchase_invoices where id = pg_temp.pi(3)),
           pg_temp.sbal('م سداد اختبار')$$,
  $$values ('300.00'::text, '-800.00'::text)$$,
  'المدفوع عند الاعتماد ثابت، ورصيد المورد الحالي يتغير بالسند المستقل'
);

-- ---------------------------------------------------------------------
-- 6) إلغاء فاتورة مدفوعة جزئيًا: السداد يبقى ولا يُلغى تلقائيًا
-- ---------------------------------------------------------------------
select lives_ok($$select public.cancel_purchase_invoice(pg_temp.pi(3))$$, 'إلغاء الفاتورة المدفوعة جزئيًا');

select results_eq(
  $$select * from pg_temp.entry_lines(pg_temp.reversal_of(pg_temp.pi_entry(3)))$$,
  $$values ('1301'::text, '0.00'::text, '500.00'::text, null::text),
           ('1302', '0.00', '100.00', null),
           ('2101', '600.00', '0.00', 'م سداد اختبار')$$,
  'القيد العكسي يلغي كامل الإجمالي من حساب المورد'
);

select results_eq(
  $$select pg_temp.reversal_of(pg_temp.pi_voucher_entry(3)) is null,
           (select paid_amount::text from public.purchase_invoices where id = pg_temp.pi(3)),
           (select is_cancelled from public.purchase_invoice_list(null, null, 'م سداد اختبار') l
            where l.id = pg_temp.pi(3)),
           pg_temp.sbal('م سداد اختبار')$$,
  $$values (true, '300.00'::text, true, '-200.00'::text)$$,
  'سند السداد الجزئي يبقى ساريًا ويُخصم من رصيد المورد بعد الإلغاء'
);

select results_eq(
  $$select i.code, s.qty::text, s.value::text, s.avg_cost::text
    from public.item_stock s join public.items i on i.id = s.item_id
    where i.code in ('P-RAW', 'P-PACK')
    order by i.code collate "C"$$,
  $$values ('P-PACK'::text, '100.000'::text, '200.00'::text, '2.0000'::text),
           ('P-RAW', '15.000', '700.00', '46.6667')$$,
  'الإلغاء يُخرج الكميات بتكلفتها الأصلية (المخزون لا يتأثر بطريقة السداد)'
);

-- الفاتورة المصححة تُدخل بمدفوع صفر: السداد السابق باقٍ في رصيد المورد فلا يتكرر
select lives_ok(
  $$select public.post_purchase_invoice('1990-04-03', pg_temp.supp('م سداد اختبار'), jsonb_build_array(
      pg_temp.pl('P-RAW', '10', '50'), pg_temp.pl('P-PACK', '40', '2')), 'تصحيح الفاتورة الملغاة', '0')$$,
  'إعادة إدخال الفاتورة المصححة بدون سداد جديد'
);

select results_eq(
  $$select pg_temp.sbal('م سداد اختبار'),
           (select count(*) from public.vouchers
            where kind = 'payment' and doc_no > (select payment_no from pg_temp._base))$$,
  $$values ('-780.00'::text, 3::bigint)$$,
  'رصيد المورد = الفواتير السارية 1,480 − المدفوع 700، بلا سداد مكرر'
);

-- مورد بفاتورة مدفوعة بالكامل ثم ملغاة: السداد يصبح دفعة مقدمة (رصيد مدين)
select lives_ok(
  $$select public.post_purchase_invoice('1990-04-06', pg_temp.supp('م مقدم اختبار'),
      jsonb_build_array(pg_temp.pl('P-RAW', '5', '50')), null, '250', pg_temp.acc('1101'))$$,
  'فاتورة مدفوعة بالكامل لمورد آخر'
);
select lives_ok($$select public.cancel_purchase_invoice(pg_temp.pi(6))$$, 'إلغاء الفاتورة المدفوعة بالكامل');

select results_eq(
  $$select pg_temp.sbal('م مقدم اختبار'), pg_temp.reversal_of(pg_temp.pi_voucher_entry(6)) is null$$,
  $$values ('250.00'::text, true)$$,
  'السداد يبقى دفعة مقدمة للمورد (رصيد مدين 250) ولا يُلغى تلقائيًا'
);

-- ---------------------------------------------------------------------
-- 7) داخل قاعدة البيانات: المدفوع لا يتجاوز الإجمالي، ويوجد سند لكل مدفوع
-- ---------------------------------------------------------------------
reset role;

select throws_ok(
  $$insert into public.purchase_invoices (doc_no, doc_date, supplier_id, total, paid_amount, journal_entry_id)
    values (-1, '1990-04-01', pg_temp.supp('م سداد اختبار'), 10, 20, pg_temp.pi_entry(1))$$,
  '23514', null,
  'إدخال مباشر بمدفوع أكبر من الإجمالي مرفوض'
);
select throws_ok(
  $$insert into public.purchase_invoices (doc_no, doc_date, supplier_id, total, paid_amount, journal_entry_id)
    values (-2, '1990-04-01', pg_temp.supp('م سداد اختبار'), 10, 5, pg_temp.pi_entry(1))$$,
  '23514', null,
  'إدخال مباشر بمدفوع بلا سند صرف مرفوض'
);

set local role authenticated;

-- ---------------------------------------------------------------------
-- 8) المطابقة
-- ---------------------------------------------------------------------
select lives_ok($$set constraints all immediate$$, 'كل ما سبق يجتاز فحوص الـ commit بصلاحية المستخدم');
set constraints all deferred;

select results_eq(
  $$select (select sum(balance::numeric) from public.party_balances('supplier'))::text,
           (select sum(debit - credit) from public.journal_lines where account_id = pg_temp.acc('2101'))::text$$,
  $$values ('-530.00'::text, '-530.00'::text)$$,
  'أرصدة الموردين (−780 و+250) = رصيد حساب الموردين في الأستاذ'
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
  $$values ('1301'::text, '1200.00'::text, '1200.00'::text),
           ('1302', '280.00', '280.00'),
           ('1303', '0', '0')$$,
  'كل حساب مخزون في الأستاذ = قيمة أصناف نوعه (السداد لا يمس المخزون)'
);

select results_eq(
  $$select code, debit, credit from public.trial_balance('1990-12-31') where code in ('1101', '1102')$$,
  $$values ('1101'::text, '49350.00'::text, '0.00'::text), ('1102', '9700.00', '0.00')$$,
  'الخزينة نقصت بالمدفوع فعلًا فقط (300 + 100 + 250)، والبنك 300'
);

select results_eq(
  $$select sum(debit::numeric)::text, sum(credit::numeric)::text from public.trial_balance('1990-12-31')$$,
  $$values ('60530.00'::text, '60530.00'::text)$$,
  'ميزان المراجعة متوازن (60,530)'
);

select results_eq(
  $$select (select count(*) from public.purchase_invoices where doc_no > (select purchase_no from pg_temp._base)),
           (select max(doc_no) - (select purchase_no from pg_temp._base) from public.purchase_invoices),
           (select count(*) from public.vouchers where kind = 'payment' and doc_no > (select payment_no from pg_temp._base)),
           (select max(doc_no) - (select payment_no from pg_temp._base) from public.vouchers where kind = 'payment')$$,
  $$values (6::bigint, 6::bigint, 4::bigint, 4::bigint)$$,
  'ترقيم الفواتير وسندات الصرف متسلسل بلا فجوات'
);

reset role;

select * from finish();
rollback;
