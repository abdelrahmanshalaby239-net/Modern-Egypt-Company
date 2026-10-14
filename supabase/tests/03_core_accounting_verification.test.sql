-- =====================================================================
-- تحقق المرحلة 2 (pgTAP): صلاحيات الدوال، إساءة استخدام الـ API، عزل
-- الأرصدة الافتتاحية، دقة الإلغاء والأرصدة الجارية ومطابقة ميزان المراجعة.
-- تعمل داخل transaction تُلغى في النهاية. قيود الاختبار بتاريخ 1990/1991.
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(32);

-- ---------------------------------------------------------------------
-- تهيئة معزولة داخل الـ transaction
-- ---------------------------------------------------------------------
update public.settings set lock_date = null where id = 1;

insert into auth.users (id, email, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', 'admin@test.local', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'accountant@test.local', 'authenticated', 'authenticated');
update public.profiles set role = 'admin' where id = '11111111-1111-1111-1111-111111111111';

-- لو في مشروع التطوير قيد افتتاحي فعلي، يُلغى داخل الاختبار فقط
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select public.cancel_journal_entry(o.id)
from public.journal_entries o
where o.source_type = 'opening'
  and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id);

create function pg_temp.acc(p_code text) returns bigint language sql stable as $$
  select id from public.accounts where code = p_code;
$$;

create function pg_temp.line(p_code text, p_debit text, p_credit text, p_description text default null)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'account_id', (select id from public.accounts where code = p_code),
    'debit', p_debit,
    'credit', p_credit,
    'description', p_description
  );
$$;

-- ---------------------------------------------------------------------
-- 1) صلاحيات الدوال و search_path (من كتالوج قاعدة البيانات)
-- ---------------------------------------------------------------------
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private') and p.proname <> 'rls_auto_enable'
     and not coalesce(p.proconfig @> array['search_path=""'], false)),
  0::bigint,
  'كل دوالنا تثبّت search_path فارغًا'
);

select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private') and p.proname <> 'rls_auto_enable'
     and has_function_privilege('anon', p.oid, 'EXECUTE')),
  0::bigint,
  'anon لا ينفّذ أي دالة من دوالنا'
);

select results_eq(
  $$select p.proname::text collate "default" from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prosecdef and p.proname <> 'rls_auto_enable'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    order by 1$$,
  $$values ('cancel_journal_entry'::text), ('cancel_production_order'), ('cancel_purchase_invoice'),
           ('cancel_sales_invoice'), ('cancel_stock_adjustment'), ('cancel_voucher'), ('delete_formula'),
           ('is_admin'), ('post_journal_entry'), ('post_opening_balances'), ('post_party_opening_balances'),
           ('post_production_order'), ('post_purchase_invoice'), ('post_sales_invoice'), ('post_stock_adjustment'),
           ('post_stock_opening'), ('post_voucher'), ('save_formula'), ('save_item')$$,
  'دوال SECURITY DEFINER المتاحة للمستخدم هي المقصودة فقط'
);

select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname in ('post_entry', 'next_doc_no', 'require_staff', 'parse_amount', 'assert_no_inventory_accounts',
                       'to_amount', 'assert_no_party_accounts', 'reverse_entry', 'create_voucher', 'to_qty',
                       'to_unit_price', 'lock_items', 'issue_cost', 'stock_in', 'stock_out', 'reverse_document_stock',
                       'inventory_account', 'item_label', 'check_item_stock', 'check_entry_inventory',
                       'create_item_stock', 'validate_item', 'parse_decimal', 'resolve_unit', 'to_base_qty',
                       'item_is_used', 'unit_is_used', 'validate_item_unit')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  0::bigint,
  'دوال الاعتماد والترقيم الداخلية غير قابلة للتنفيذ للمستخدم'
);

select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace,
     lateral aclexplode(c.relacl) a
   where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'S') and a.grantee = 'anon'::regrole),
  0::bigint,
  'anon بلا أي صلاحية على جداول وsequences الـ public'
);

select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace,
     lateral aclexplode(c.relacl) a
   where n.nspname = 'public' and c.relkind = 'S' and a.grantee = 'authenticated'::regrole),
  0::bigint,
  'المستخدم بلا صلاحية على الـ sequences'
);

select results_eq(
  $$select c.relname::text collate "default", a.privilege_type::text
    from pg_class c join pg_namespace n on n.oid = c.relnamespace, lateral aclexplode(c.relacl) a
    where n.nspname = 'public' and c.relname in ('journal_entries', 'journal_lines', 'doc_counters')
      and a.grantee = 'authenticated'::regrole
    order by 1, 2$$,
  $$values ('journal_entries'::text, 'SELECT'::text), ('journal_lines', 'SELECT')$$,
  'صلاحية المستخدم على جداول القيود قراءة فقط، ولا شيء على العدّادات'
);

-- ---------------------------------------------------------------------
-- 2) إساءة استخدام الـ API مباشرة
-- ---------------------------------------------------------------------
set local role authenticated;

select set_config('request.jwt.claims', '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated"}', true);
select throws_ok(
  $$select public.post_journal_entry('1991-02-01', 'x', 'manual', jsonb_build_array(
      pg_temp.line('6701', '1', '0'), pg_temp.line('1101', '0', '1')))$$,
  '42501', 'ليست لديك صلاحية لتنفيذ هذه العملية',
  'مستخدم بلا ملف (profile) لا يعتمد قيودًا'
);

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  $$select public.post_journal_entry('1991-02-01', 'x', 'manual', jsonb_build_array(
      pg_temp.line('6701', '1', '0'), pg_temp.line('1101', '0', '1')))$$,
  '42501', 'ليست لديك صلاحية لتنفيذ هذه العملية',
  'طلب بلا هوية مستخدم (sub) لا يعتمد قيودًا'
);

select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

select throws_ok($$select private.next_doc_no('journal')$$, '42501', null, 'المستخدم لا يستدعي دالة الترقيم مباشرة');

select throws_ok(
  $$select setval('public.journal_entries_id_seq', 1)$$,
  '42501', null, 'المستخدم لا يعدّل الـ sequences'
);

select throws_ok(
  $$select public.post_journal_entry('1991-02-01', 'x', 'reversal', jsonb_build_array(
      pg_temp.line('6701', '1', '0'), pg_temp.line('1101', '0', '1')))$$,
  'P0001', 'نوع القيد غير صالح',
  'لا يُنشأ قيد عكسي أو قيد مستند من شاشة القيد اليدوي'
);

select throws_ok(
  $$select public.post_journal_entry('1991-02-01', 'x', 'manual', '{"a": 1}'::jsonb)$$,
  'P0001', 'سطور القيد مطلوبة',
  'سطور ليست مصفوفة تُرفض'
);

select throws_ok(
  $$select public.post_journal_entry('1991-02-01', 'x', 'manual',
      '[{"account_id": "1 or 1=1", "debit": "1", "credit": "0"}, {"account_id": "2", "debit": "0", "credit": "1"}]'::jsonb)$$,
  '22P02', null,
  'رقم حساب غير رقمي يُرفض (لا حقن)'
);

select throws_ok(
  $$select public.post_journal_entry('1991-02-01', 'x', 'manual', jsonb_build_array(
      jsonb_build_object('account_id', pg_temp.acc('6701'), 'debit', true, 'credit', 0),
      pg_temp.line('1101', '0', '1')))$$,
  'P0001', 'السطر 1: المبلغ "true" غير صالح',
  'مبلغ منطقي (true) يُرفض'
);

select lives_ok(
  $$select public.post_journal_entry('1991-02-01', 'مبالغ JSON رقمية', 'manual', jsonb_build_array(
      jsonb_build_object('account_id', pg_temp.acc('6701'), 'debit', 12.5, 'credit', 0,
                         'created_by', '11111111-1111-1111-1111-111111111111', 'entry_id', 1),
      jsonb_build_object('account_id', pg_temp.acc('1101'), 'debit', 0, 'credit', 12.5)))$$,
  'مبالغ JSON رقمية مقبولة، والمفاتيح الإضافية تُتجاهل'
);

select results_eq(
  $$select e.created_by, l.debit, l.credit
    from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
    where e.description = 'مبالغ JSON رقمية'
    order by l.id$$,
  $$values ('22222222-2222-2222-2222-222222222222'::uuid, 12.50::numeric, 0.00::numeric),
           ('22222222-2222-2222-2222-222222222222'::uuid, 0.00, 12.50)$$,
  'created_by من الجلسة لا من الطلب، والمبالغ كما أُرسلت'
);

select throws_ok($$select public.cancel_journal_entry(-999)$$, 'P0001', 'القيد غير موجود', 'إلغاء قيد غير موجود يُرفض');

reset role;
insert into public.journal_entries (entry_no, entry_date, description, source_type, created_by)
values (-10, '1991-02-02', 'قيد مستند للاختبار', 'purchase', '22222222-2222-2222-2222-222222222222');
insert into public.journal_lines (entry_id, account_id, debit, credit)
select id, pg_temp.acc('6701'), 5, 0 from public.journal_entries where entry_no = -10
union all
select id, pg_temp.acc('1101'), 0, 5 from public.journal_entries where entry_no = -10;
set local role authenticated;

select throws_ok(
  $$select public.cancel_journal_entry((select id from public.journal_entries where entry_no = -10))$$,
  'P0001', 'هذا القيد يُلغى من خلال المستند المرتبط به',
  'قيد المستند لا يُلغى من شاشة القيود'
);

-- ---------------------------------------------------------------------
-- 3) عزل الأرصدة الافتتاحية (لا ازدواج مع أجزاء العملاء والموردين والمخزون)
-- ---------------------------------------------------------------------
select throws_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1201', '100', '0'), pg_temp.line('3101', '0', '100')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 1201 - العملاء. حسابات العملاء والموردين تتحرك من السندات والأرصدة الافتتاحية للأطراف فقط',
  'أرصدة الحسابات لا تقبل حساب العملاء (له جزء خاص في المرحلة 3)'
);

select throws_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('3101', '100', '0'), pg_temp.line('2101', '0', '100')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 2101 - الموردين. حسابات العملاء والموردين تتحرك من السندات والأرصدة الافتتاحية للأطراف فقط',
  'أرصدة الحسابات لا تقبل حساب الموردين (له جزء خاص في المرحلة 3)'
);

select throws_ok(
  $$select public.post_opening_balances('1990-01-01', jsonb_build_array(
      pg_temp.line('1303', '100', '0'), pg_temp.line('3101', '0', '100')))$$,
  'P0001', 'لا يمكن الترحيل يدويًا على حساب 1303 - مخزون منتج تام. حسابات المخزون تتحرك من مستندات المخزون فقط',
  'أرصدة الحسابات لا تقبل حساب المنتج التام (له جزء خاص في المرحلة 4)'
);

select public.post_opening_balances('1990-01-01', jsonb_build_array(
  pg_temp.line('1101', '100000', '0'), pg_temp.line('1501', '50000', '0'), pg_temp.line('3101', '0', '150000')));
select public.cancel_journal_entry((select max(id) from public.journal_entries where source_type = 'opening'));
select public.post_opening_balances('1990-01-01', jsonb_build_array(
  pg_temp.line('1101', '80000', '0'), pg_temp.line('3101', '0', '80000')));

select results_eq(
  $$select code, debit, credit from public.trial_balance('1990-12-31')$$,
  $$values ('1101'::text, '80000.00'::text, '0.00'::text), ('3101', '0.00', '80000.00')$$,
  'بعد إلغاء الأرصدة الافتتاحية وإعادة تسجيلها تُحسب مرة واحدة فقط'
);

-- ---------------------------------------------------------------------
-- 4) الإلغاء والأرصدة الجارية ومطابقة ميزان المراجعة
-- ---------------------------------------------------------------------
select public.post_journal_entry('1990-02-10', 'مصروفات متنوعة', 'manual', jsonb_build_array(
  pg_temp.line('6201', '300', '0', 'كهرباء'),
  pg_temp.line('6301', '200', '0', 'إيجار'),
  pg_temp.line('1101', '0', '450', 'دفعة أولى'),
  pg_temp.line('1101', '0', '50', 'دفعة ثانية')));

select results_eq(
  $$select description, credit, balance
    from public.account_statement(pg_temp.acc('1101'), '1990-02-01', '1990-02-28')$$,
  $$values ('رصيد أول المدة'::text, null::text, '80000.00'::text),
           ('دفعة أولى', '450.00', '79550.00'),
           ('دفعة ثانية', '50.00', '79500.00')$$,
  'سطران على نفس الحساب في قيد واحد: رصيد جارٍ لكل سطر بترتيبه وبملاحظته'
);

select results_eq(
  $$select (select count(*) from public.trial_balance('1990-02-10') where code = '6201'),
           (select count(*) from public.trial_balance('1990-02-09') where code = '6201'),
           (select count(*) from public.account_statement(pg_temp.acc('6201'), '1990-02-01', '1990-02-10')
            where entry_id is not null)$$,
  $$values (1::bigint, 0::bigint, 1::bigint)$$,
  'حدود التاريخ شاملة: قيد بتاريخ 10/02 يدخل في الميزان والكشف حتى 10/02'
);

reset role;
create temp table _tb_before as select * from public.trial_balance('1990-12-31');
grant select on _tb_before to public;
set local role authenticated;

select public.post_journal_entry('1990-03-01', 'قيد سيُلغى', 'manual', jsonb_build_array(
  pg_temp.line('6501', '75', '0'), pg_temp.line('1102', '0', '75')));
select public.cancel_journal_entry((select id from public.journal_entries where description = 'قيد سيُلغى'));

select results_eq(
  $$select * from public.trial_balance('1990-12-31')$$,
  $$select * from _tb_before order by code$$,
  'الإلغاء يعيد ميزان المراجعة كما كان تمامًا'
);

select public.cancel_journal_entry((select id from public.journal_entries where description = 'مصروفات متنوعة'));

select results_eq(
  $$select a.code, l.debit, l.credit, l.description
    from public.journal_lines l join public.accounts a on a.id = l.account_id
    where l.entry_id = (select id from public.journal_entries
                        where reverses_entry_id = (select id from public.journal_entries
                                                   where description = 'مصروفات متنوعة'))
    order by l.id$$,
  $$values ('6201'::text, 0.00::numeric, 300.00::numeric, 'كهرباء'::text),
           ('6301', 0.00, 200.00, 'إيجار'),
           ('1101', 450.00, 0.00, 'دفعة أولى'),
           ('1101', 50.00, 0.00, 'دفعة ثانية')$$,
  'عكس قيد متعدد السطور: نفس الحسابات والملاحظات بمبالغ معكوسة'
);

select is(
  (select s.balance
   from public.account_statement(pg_temp.acc('1101'), '1990-02-01', '1990-02-28')
        with ordinality as s (entry_id, entry_no, entry_date, source_type, description, debit, credit, balance, ord)
   order by s.ord desc limit 1),
  '80000.00',
  'بعد الإلغاء يعود الرصيد الجاري للخزينة إلى 80,000'
);

select public.post_journal_entry('1990-04-15', 'مصروف إداري', 'manual', jsonb_build_array(
  pg_temp.line('6701', '200', '0'), pg_temp.line('1101', '0', '200')));
select public.post_journal_entry('1990-04-30', 'إهلاك', 'adjustment', jsonb_build_array(
  pg_temp.line('6801', '500', '0'), pg_temp.line('1509', '0', '500')));

select is(
  (select count(*)
   from public.trial_balance('1990-12-31') t
   cross join lateral (
     select s.balance
     from public.account_statement(t.account_id, null, '1990-12-31')
          with ordinality as s (entry_id, entry_no, entry_date, source_type, description, debit, credit, balance, ord)
     order by s.ord desc limit 1
   ) last
   where last.balance::numeric <> t.debit::numeric - t.credit::numeric),
  0::bigint,
  'لكل حساب: الرصيد الختامي في كشف الحساب = رصيده في ميزان المراجعة'
);

select is(
  (select count(*)
   from public.trial_balance('1990-12-31') t
   cross join lateral (
     select (array_agg(s.balance::numeric order by s.ord))[1] as opening,
            (array_agg(s.balance::numeric order by s.ord desc))[1] as closing,
            coalesce(sum(s.debit::numeric) filter (where s.entry_id is not null), 0) as dr,
            coalesce(sum(s.credit::numeric) filter (where s.entry_id is not null), 0) as cr
     from public.account_statement(t.account_id, '1990-02-01', '1990-12-31')
          with ordinality as s (entry_id, entry_no, entry_date, source_type, description, debit, credit, balance, ord)
   ) k
   where k.closing <> k.opening + k.dr - k.cr
      or k.closing <> t.debit::numeric - t.credit::numeric),
  0::bigint,
  'لكل حساب: رصيد أول المدة + المدين − الدائن = الرصيد الختامي = رصيد الميزان'
);

select results_eq(
  $$select (select count(*) from public.trial_balance('1990-12-31') where code = '6201'),
           (select s.balance
            from public.account_statement(pg_temp.acc('6201'), null, '1990-12-31')
                 with ordinality as s (entry_id, entry_no, entry_date, source_type, description, debit, credit, balance, ord)
            order by s.ord desc limit 1)$$,
  $$values (0::bigint, '0.00'::text)$$,
  'حساب صار رصيده صفرًا بعد الإلغاء: يختفي من الميزان ورصيده الختامي صفر'
);

select results_eq(
  $$select sum(debit::numeric), sum(credit::numeric) from public.trial_balance('1990-12-31')$$,
  $$values (80500.00::numeric, 80500.00::numeric)$$,
  'إجمالي مدين الميزان = إجمالي دائنه = 80,500 بعد كل العمليات والإلغاءات'
);

reset role;

select * from finish();
rollback;
