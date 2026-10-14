-- =====================================================================
-- المرحلة 7: القوائم المالية والقفل والإقفال — السنة المالية، القفل الشهري (للأمام فقط)، إقفال السنة بقيد
-- `closing`، قائمة الدخل، الميزانية العمومية، وملخص الشاشة الرئيسية (SPEC §6.7–§6.9 و§8).
-- ترحيل إضافي فقط (بلا DROP).
-- =====================================================================

-- ---------------------------------------------------------------------
-- أدوات مساعدة
-- ---------------------------------------------------------------------

-- آخر يوم في شهر التاريخ
create function private.month_end(p_date date)
returns date
language sql
immutable
set search_path = ''
as $$
  select (date_trunc('month', p_date::timestamp) + interval '1 month - 1 day')::date;
$$;

-- تاريخ اليوم بتوقيت القاهرة (القفل والإقفال لا يسبقان الواقع)
create function private.today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Africa/Cairo')::date;
$$;

create function private.require_admin()
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  perform private.require_staff();
  if not private.is_admin() then
    raise exception 'هذه العملية لمدير النظام فقط' using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- السنوات المالية: سنة مفتوحة واحدة، تبدأ أول شهر وتنتهي آخر شهر، بلا تداخل. تُكتب عبر الدوال فقط.
-- ---------------------------------------------------------------------
create table public.fiscal_years (
  id bigint generated always as identity primary key,
  name text not null unique check (btrim(name) <> '' and name = btrim(name)),
  start_date date not null,
  end_date date not null,
  is_closed boolean not null default false,
  closing_entry_id bigint unique references public.journal_entries (id),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint fiscal_years_dates check (end_date > start_date),
  constraint fiscal_years_month_start check (extract(day from start_date) = 1),
  constraint fiscal_years_month_end check (end_date = (date_trunc('month', end_date::timestamp) + interval '1 month - 1 day')::date),
  constraint fiscal_years_closed check (is_closed = (closed_at is not null)),
  constraint fiscal_years_no_overlap exclude using gist (daterange(start_date, end_date, '[]') with &&)
);

create unique index fiscal_years_one_open on public.fiscal_years ((true)) where not is_closed;

-- اسم تلقائي للسنة: «السنة المالية 2027» أو «السنة المالية 2026/2027»، ورقم إضافي لو الاسم مستخدم
create function private.fiscal_year_name(p_start date, p_end date)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_base text := 'السنة المالية ' || case
    when extract(year from p_start) = extract(year from p_end) then to_char(p_start, 'YYYY')
    else to_char(p_start, 'YYYY') || '/' || to_char(p_end, 'YYYY')
  end;
  v_name text := v_base;
  v_n int := 1;
begin
  while exists (select 1 from public.fiscal_years where name = v_name) loop
    v_n := v_n + 1;
    v_name := v_base || ' (' || v_n || ')';
  end loop;
  return v_name;
end;
$$;

-- تعريف السنة المالية المفتوحة أو تعديلها (المدير فقط).
-- أول سنة: لا قيود قبل بدايتها (إلا قيدًا ملغى مع عكسه، فصافيهما صفر)، وتاريخ القفل = اليوم السابق لبدايتها،
-- فلا يُسجَّل شيء خارج سنة مالية أبدًا. السنوات التالية تُنشأ بالإقفال، وبدايتها ثابتة. النهاية بعد تاريخ القفل.
-- يقفل عدّاد القيود أولًا (نفس ترتيب الاعتماد) فينتظر أي مستند يُعتمد الآن.
create function public.save_open_fiscal_year(p_name text, p_start date, p_end date)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_year public.fiscal_years;
  v_has_closed boolean;
  v_lock date;
  v_first date;
  v_id bigint;
begin
  perform private.require_admin();
  perform 1 from public.doc_counters where kind = 'journal' for update;

  if v_name = '' then
    raise exception 'اسم السنة المالية مطلوب';
  end if;
  if p_start is null or p_end is null then
    raise exception 'بداية السنة المالية ونهايتها مطلوبتان';
  end if;
  if extract(day from p_start) <> 1 then
    raise exception 'بداية السنة المالية يجب أن تكون أول يوم في شهر';
  end if;
  if p_end <> private.month_end(p_end) then
    raise exception 'نهاية السنة المالية يجب أن تكون آخر يوم في شهر';
  end if;
  if p_end <= p_start then
    raise exception 'نهاية السنة المالية يجب أن تكون بعد بدايتها';
  end if;
  if p_end > (p_start + interval '24 months' - interval '1 day')::date then
    raise exception 'السنة المالية لا تزيد عن 24 شهرًا';
  end if;

  select lock_date into v_lock from public.settings where id = 1 for update;
  select * into v_year from public.fiscal_years where not is_closed for update;
  v_has_closed := exists (select 1 from public.fiscal_years where is_closed);

  if v_has_closed and p_start is distinct from v_year.start_date then
    raise exception 'بداية السنة المالية تلي نهاية السنة المقفلة السابقة (%) ولا تتغير',
      to_char(v_year.start_date, 'DD/MM/YYYY');
  end if;

  -- أول سنة (جديدة أو بتغيير بدايتها)
  if not v_has_closed and (v_year.id is null or p_start <> v_year.start_date) then
    if v_lock is not null and v_lock >= p_start then
      raise exception 'الفترة مقفولة حتى %، فلا تبدأ السنة المالية قبل ذلك', to_char(v_lock, 'DD/MM/YYYY');
    end if;
    select min(e.entry_date) into v_first
    from public.journal_entries e
    where e.entry_date < p_start
      and e.reverses_entry_id is null
      and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = e.id);
    if v_first is not null then
      raise exception 'توجد قيود بتاريخ قبل بداية السنة المالية (أولها بتاريخ %). اختر بداية لا تتأخر عن أول قيد',
        to_char(v_first, 'DD/MM/YYYY');
    end if;
    v_lock := p_start - 1;
    update public.settings set lock_date = v_lock where id = 1;
  end if;

  if v_lock is not null and p_end <= v_lock then
    raise exception 'نهاية السنة المالية يجب أن تكون بعد تاريخ القفل %', to_char(v_lock, 'DD/MM/YYYY');
  end if;

  begin
    if v_year.id is null then
      insert into public.fiscal_years (name, start_date, end_date)
      values (v_name, p_start, p_end)
      returning id into v_id;
    else
      update public.fiscal_years set name = v_name, start_date = p_start, end_date = p_end where id = v_year.id;
      v_id := v_year.id;
    end if;
  exception when unique_violation then
    raise exception 'يوجد سنة مالية بنفس الاسم';
  end;

  return v_id;
end;
$$;

-- قفل شهري (المدير فقط): للأمام فقط، تاريخه آخر يوم في شهر انتهى، وقبل نهاية السنة المفتوحة (نهايتها تُقفل
-- بالإقفال، فيبقى قيد الإقفال ممكنًا بتاريخ نهاية السنة دون تجاوز القاعدة 4).
create function public.lock_period(p_date date)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year public.fiscal_years;
  v_lock date;
begin
  perform private.require_admin();
  perform 1 from public.doc_counters where kind = 'journal' for update;

  select * into v_year from public.fiscal_years where not is_closed;
  if not found then
    raise exception 'عرّف السنة المالية أولًا';
  end if;
  if p_date is null then
    raise exception 'تاريخ القفل مطلوب';
  end if;
  if p_date <> private.month_end(p_date) then
    raise exception 'تاريخ القفل يجب أن يكون آخر يوم في شهر';
  end if;
  select lock_date into v_lock from public.settings where id = 1 for update;
  if v_lock is not null and p_date <= v_lock then
    raise exception 'الفترة مقفولة بالفعل حتى %. القفل للأمام فقط', to_char(v_lock, 'DD/MM/YYYY');
  end if;
  if p_date >= v_year.end_date then
    raise exception 'القفل الشهري قبل نهاية السنة المالية (%). نهاية السنة تُقفل بإقفال السنة',
      to_char(v_year.end_date, 'DD/MM/YYYY');
  end if;
  if p_date > private.today() then
    raise exception 'لا يمكن قفل شهر لم ينتهِ بعد';
  end if;

  update public.settings set lock_date = p_date where id = 1;
  return p_date;
end;
$$;

-- ---------------------------------------------------------------------
-- الإقفال
-- ---------------------------------------------------------------------

-- سطور قيد الإقفال للسنة المفتوحة: كل حساب إيرادات أو مصروفات برصيده حتى نهاية السنة (القيود السابقة
-- كلها، والسنوات المقفلة صافيها صفر بقيود إقفالها) يُقفل في الأرباح المرحّلة. صافي الربح صفر = بلا سطر أرباح.
create function public.fiscal_year_closing_preview()
returns table (
  line_no int,
  account_id bigint,
  code text,
  name text,
  debit text,
  credit text
)
language sql
stable
set search_path = ''
as $$
  with y as (
    select end_date from public.fiscal_years where not is_closed
  ),
  b as (
    select a.id, a.code, a.name, sum(l.debit - l.credit) as amount
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    join public.accounts a on a.id = l.account_id
    where a.type in ('revenue', 'expense')
      and e.entry_date <= (select end_date from y)
    group by a.id, a.code, a.name
    having sum(l.debit - l.credit) <> 0
  ),
  re as (
    select a.id, a.code, a.name, -(select coalesce(sum(amount), 0) from b) as profit
    from public.system_accounts s join public.accounts a on a.id = s.account_id
    where s.key = 'retained_earnings'
  )
  select x.line_no, x.id, x.code, x.name, x.debit, x.credit
  from (
    select (row_number() over (order by b.code))::int as line_no, b.id, b.code, b.name,
           round(greatest(-b.amount, 0), 2)::text as debit, round(greatest(b.amount, 0), 2)::text as credit
    from b
    union all
    select (select count(*) from b)::int + 1, re.id, re.code, re.name,
           round(greatest(-re.profit, 0), 2)::text, round(greatest(re.profit, 0), 2)::text
    from re
    where re.profit <> 0
  ) x
  order by x.line_no;
$$;

-- إقفال السنة المفتوحة (المدير فقط، بعد انتهائها): قيد `closing` بتاريخ نهايتها (لو فيه أرصدة)، ثم تاريخ القفل
-- = نهايتها، والسنة مقفلة، وتُنشأ السنة التالية (12 شهرًا، نهايتها قابلة للتعديل وهي مفتوحة).
create function public.close_fiscal_year()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year public.fiscal_years;
  v_lines jsonb;
  v_entry_id bigint;
  v_next_start date;
  v_next_end date;
begin
  perform private.require_admin();
  perform 1 from public.doc_counters where kind = 'journal' for update;

  select * into v_year from public.fiscal_years where not is_closed for update;
  if not found then
    raise exception 'لا توجد سنة مالية مفتوحة';
  end if;
  if v_year.end_date > private.today() then
    raise exception 'لا يمكن إقفال السنة المالية قبل انتهائها في %', to_char(v_year.end_date, 'DD/MM/YYYY');
  end if;

  select jsonb_agg(jsonb_build_object('account_id', p.account_id, 'debit', p.debit, 'credit', p.credit,
                                      'description', 'إقفال ' || v_year.name)
                   order by p.line_no)
  into v_lines
  from public.fiscal_year_closing_preview() p;

  if v_lines is not null then
    v_entry_id := private.post_entry(
      v_year.end_date, 'قيد إقفال ' || v_year.name, 'closing', v_lines, v_year.id
    );
  end if;

  update public.fiscal_years
  set is_closed = true, closing_entry_id = v_entry_id, closed_at = now()
  where id = v_year.id;
  update public.settings set lock_date = v_year.end_date where id = 1;

  v_next_start := v_year.end_date + 1;
  v_next_end := private.month_end((v_next_start + interval '11 months')::date);
  insert into public.fiscal_years (name, start_date, end_date)
  values (private.fiscal_year_name(v_next_start, v_next_end), v_next_start, v_next_end);

  return v_year.id;
end;
$$;

-- قيد الإقفال لا يُلغى (السنة المقفلة لا تُعاد فتحها)، وباقي الرسائل كما هي
create or replace function public.cancel_journal_entry(p_entry_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.journal_entries;
  v_description text;
begin
  perform private.require_staff();

  select * into v_entry from public.journal_entries where id = p_entry_id for update;
  if not found then
    raise exception 'القيد غير موجود';
  end if;
  if v_entry.source_type = 'reversal' then
    raise exception 'لا يمكن إلغاء قيد عكسي';
  end if;
  if v_entry.source_type = 'closing' then
    raise exception 'لا يمكن إلغاء قيد الإقفال، فالسنة المقفلة لا تُعاد فتحها';
  end if;
  if v_entry.source_type not in ('manual', 'adjustment', 'opening') then
    raise exception 'هذا القيد يُلغى من خلال المستند المرتبط به';
  end if;

  v_description := 'إلغاء القيد رقم ' || v_entry.entry_no || ': ' || v_entry.description;
  if v_entry.source_type = 'opening' and private.opening_part(p_entry_id) = 'inventory' then
    return private.reverse_document_stock(p_entry_id, v_description);
  end if;
  return private.reverse_entry(p_entry_id, v_description);
end;
$$;

-- ---------------------------------------------------------------------
-- حماية القوائم المالية
-- ---------------------------------------------------------------------

-- سطور القيود: + قيد الإقفال على الإيرادات والمصروفات والأرباح المرحّلة فقط (دفاع إضافي؛ تنشئه
-- close_fiscal_year وحدها). باقي القواعد كما في المرحلة 6.
create or replace function private.validate_journal_line()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_keys text[];
  v_source text;
begin
  select * into v_account from public.accounts where id = new.account_id;
  if not found then
    raise exception 'الحساب غير موجود';
  end if;
  if not v_account.is_postable or not v_account.is_active then
    raise exception 'الترحيل مسموح فقط على حساب فرعي نشط: % - %', v_account.code, v_account.name;
  end if;

  v_keys := private.account_keys(new.account_id);
  select source_type into v_source from public.journal_entries where id = new.entry_id;

  -- حسابات المستندات تتحرك من مستنداتها فقط (SPEC §6.1 و§6.3)
  if v_keys && array['inventory_raw', 'inventory_packaging', 'inventory_finished']
     and v_source in ('manual', 'adjustment', 'voucher') then
    raise exception 'لا يمكن الترحيل على حساب % - % من قيد يدوي أو سند. حسابات المخزون تتحرك من مستندات المخزون فقط',
      v_account.code, v_account.name;
  end if;
  if v_keys && array['receivables', 'payables'] and v_source in ('manual', 'adjustment') then
    raise exception 'لا يمكن الترحيل يدويًا على حساب % - %. حسابات العملاء والموردين تتحرك من السندات والأرصدة الافتتاحية للأطراف فقط',
      v_account.code, v_account.name;
  end if;
  if v_keys && array['sales_revenue', 'cogs', 'inventory_adjustment'] and v_source = 'voucher' then
    raise exception 'لا يمكن استخدام حساب % - % في السندات. يتحرك من مستنداته فقط (فواتير المبيعات أو تسوية الجرد)',
      v_account.code, v_account.name;
  end if;

  -- القاعدة 9: سطر العملاء يحمل عميلًا، وسطر الموردين يحمل موردًا، ولا طرف على غيرهما
  if 'receivables' = any (v_keys) then
    if new.customer_id is null then
      raise exception 'الترحيل على حساب % - % يتطلب تحديد العميل', v_account.code, v_account.name;
    end if;
    if new.supplier_id is not null then
      raise exception 'لا يُسمح بتحديد مورد على حساب % - %', v_account.code, v_account.name;
    end if;
  elsif 'payables' = any (v_keys) then
    if new.supplier_id is null then
      raise exception 'الترحيل على حساب % - % يتطلب تحديد المورد', v_account.code, v_account.name;
    end if;
    if new.customer_id is not null then
      raise exception 'لا يُسمح بتحديد عميل على حساب % - %', v_account.code, v_account.name;
    end if;
  elsif new.customer_id is not null or new.supplier_id is not null then
    raise exception 'لا يُسمح بتحديد عميل أو مورد على حساب % - %', v_account.code, v_account.name;
  end if;

  if v_keys && array['sales_revenue', 'cogs'] and v_source in ('manual', 'adjustment') then
    raise exception 'لا يمكن الترحيل يدويًا على حساب % - %. إيرادات المبيعات وتكلفتها تتحرك من فواتير المبيعات فقط (لمطابقة تقرير أرباح الأصناف)',
      v_account.code, v_account.name;
  end if;
  if v_source = 'closing' and v_account.type not in ('revenue', 'expense')
     and not ('retained_earnings' = any (v_keys)) then
    raise exception 'قيد الإقفال يقتصر على حسابات الإيرادات والمصروفات والأرباح المرحّلة';
  end if;
  return new;
end;
$$;

-- حساب الأرباح المرحّلة ثابت بعد وجود قيود (يحمل نتائج السنوات المقفلة)
create or replace function private.validate_system_account()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_expected_type text;
begin
  v_expected_type := case new.key
    when 'payables' then 'liability'
    when 'sales_revenue' then 'revenue'
    when 'cogs' then 'expense'
    when 'inventory_adjustment' then 'expense'
    when 'capital' then 'equity'
    when 'retained_earnings' then 'equity'
    else 'asset' -- receivables + inventory_*
  end;

  select * into v_account from public.accounts where id = new.account_id;
  if not v_account.is_postable or not v_account.is_active then
    raise exception 'حساب النظام يجب أن يكون حسابًا فرعيًا نشطًا';
  end if;
  if v_account.type <> v_expected_type then
    raise exception 'نوع الحساب المختار لا يناسب هذا الحساب من حسابات النظام';
  end if;
  if v_account.is_treasury then
    raise exception 'لا يُربط حساب نظام بحساب خزينة أو بنك';
  end if;

  if tg_op = 'UPDATE'
     and new.key in ('receivables', 'payables', 'inventory_raw', 'inventory_packaging', 'inventory_finished',
                     'sales_revenue', 'cogs', 'retained_earnings')
     and new.account_id is distinct from old.account_id
     and exists (
       select 1 from public.journal_lines where account_id in (old.account_id, new.account_id)
     ) then
    raise exception 'لا يمكن تغيير حساب % بعد وجود قيود على الحساب الحالي أو الجديد',
      case new.key
        when 'receivables' then 'العملاء'
        when 'payables' then 'الموردين'
        when 'inventory_raw' then 'مخزون المواد الخام'
        when 'inventory_packaging' then 'مخزون مواد التعبئة والتغليف'
        when 'sales_revenue' then 'إيرادات المبيعات'
        when 'cogs' then 'تكلفة البضاعة المباعة'
        when 'retained_earnings' then 'الأرباح المرحّلة'
        else 'مخزون المنتج التام'
      end;
  end if;
  return new;
end;
$$;

-- الرقم الأول لكود حساب عليه قيود ثابت: قائمة الدخل تصنّف به (41 مبيعات، 5 تكلفة المبيعات، 6 مصروفات تشغيل).
-- باقي القواعد كما هي.
create or replace function private.validate_account()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent public.accounts;
  v_is_system boolean;
  v_has_children boolean;
  v_has_lines boolean;
begin
  if new.code is null or new.code !~ '^[0-9]+$' then
    raise exception 'كود الحساب يجب أن يكون أرقامًا فقط';
  end if;

  if new.name is null or btrim(new.name) = '' then
    raise exception 'اسم الحساب مطلوب';
  end if;

  if new.parent_id is not null then
    select * into v_parent from public.accounts where id = new.parent_id;
    if v_parent.is_postable then
      raise exception 'الحساب الأب يجب أن يكون حسابًا تجميعيًا (غير قابل للترحيل)';
    end if;
    if v_parent.type <> new.type then
      raise exception 'نوع الحساب يجب أن يطابق نوع الحساب الأب';
    end if;
  end if;

  if new.is_treasury and not (new.type = 'asset' and new.is_postable) then
    raise exception 'الخزينة أو البنك يجب أن يكون حساب أصول قابلًا للترحيل';
  end if;

  -- حساب النظام (العملاء والموردين والمخزون...) لا يكون خزينة، حتى لا يتحرك من السندات
  if new.is_treasury and tg_op = 'UPDATE'
     and exists (select 1 from public.system_accounts where account_id = new.id) then
    raise exception 'حساب النظام لا يكون خزينة أو بنكًا';
  end if;

  if tg_op = 'UPDATE' then
    v_has_children := exists (select 1 from public.accounts where parent_id = new.id);
    v_is_system := exists (select 1 from public.system_accounts where account_id = new.id);
    v_has_lines := exists (select 1 from public.journal_lines where account_id = new.id);

    if new.parent_id is distinct from old.parent_id and new.parent_id is not null
       and exists (
         with recursive sub as (
           select id from public.accounts where id = new.id
           union all
           select a.id from public.accounts a join sub on a.parent_id = sub.id
         )
         select 1 from sub where id = new.parent_id
       ) then
      raise exception 'لا يمكن جعل الحساب تابعًا لنفسه أو لأحد حساباته الفرعية';
    end if;

    if v_has_children and new.is_postable then
      raise exception 'لا يمكن جعل حساب له حسابات فرعية قابلًا للترحيل';
    end if;

    if v_has_children and new.type <> old.type then
      raise exception 'لا يمكن تغيير نوع حساب له حسابات فرعية';
    end if;

    if v_has_lines and not new.is_postable then
      raise exception 'لا يمكن جعل حساب عليه قيود حسابًا تجميعيًا';
    end if;

    if v_has_lines and new.type <> old.type then
      raise exception 'لا يمكن تغيير نوع حساب عليه قيود';
    end if;

    if v_has_lines and left(new.code, 1) <> left(old.code, 1) then
      raise exception 'لا يمكن تغيير الرقم الأول لكود حساب عليه قيود (يحدد مكانه في القوائم المالية)';
    end if;

    if v_is_system then
      if not new.is_active then
        raise exception 'لا يمكن تعطيل حساب نظام';
      end if;
      if not new.is_postable then
        raise exception 'حساب النظام يجب أن يبقى قابلًا للترحيل';
      end if;
      if new.type <> old.type then
        raise exception 'لا يمكن تغيير نوع حساب نظام';
      end if;
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- القوائم المالية والشاشة الرئيسية (قراءة بصلاحية المستخدم، والمبالغ نصًا)
-- ---------------------------------------------------------------------

-- قائمة الدخل لفترة (بدون قيود الإقفال): المبيعات (إيرادات 41)، تكلفة المبيعات (مصروفات 5: تكلفة البضاعة
-- المباعة وفروقات الجرد)، مصروفات التشغيل (باقي المصروفات)، والإيرادات الأخرى (باقي الإيرادات). المبلغ
-- بطبيعته (الإيراد دائن − مدين، والمصروف مدين − دائن). تكلفة الإنتاج تبقى في المخزون حتى البيع، فلا تتكرر.
create function public.income_statement(p_from date default null, p_to date default null)
returns table (
  section text,
  account_id bigint,
  code text,
  name text,
  amount text
)
language sql
stable
set search_path = ''
as $$
  select case
           when a.type = 'revenue' and a.code like '41%' then 'sales'
           when a.type = 'revenue' then 'other_revenue'
           when a.code like '5%' then 'cost_of_sales'
           else 'expenses'
         end,
         a.id, a.code, a.name,
         round(case when a.type = 'revenue' then sum(l.credit - l.debit) else sum(l.debit - l.credit) end, 2)::text
  from public.journal_lines l
  join public.journal_entries e on e.id = l.entry_id
  join public.accounts a on a.id = l.account_id
  where a.type in ('revenue', 'expense')
    and e.source_type <> 'closing'
    and (p_from is null or e.entry_date >= p_from)
    and (p_to is null or e.entry_date <= p_to)
  group by a.id, a.code, a.name, a.type
  having sum(l.debit - l.credit) <> 0
  order by a.code;
$$;

-- الميزانية العمومية بتاريخ: الأصول (مدين − دائن) والخصوم وحقوق الملكية (دائن − مدين)، وصف «أرباح لم
-- تُقفل بعد» = صافي الإيرادات والمصروفات حتى التاريخ (السنوات المقفلة صافيها صفر بقيود إقفالها).
create function public.balance_sheet(p_as_of date default null)
returns table (
  section text,
  account_id bigint,
  code text,
  name text,
  amount text
)
language sql
stable
set search_path = ''
as $$
  with b as (
    select a.id, a.code, a.name, a.type, sum(l.debit - l.credit) as amount
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    join public.accounts a on a.id = l.account_id
    where p_as_of is null or e.entry_date <= p_as_of
    group by a.id, a.code, a.name, a.type
  )
  select x.section, x.id, x.code, x.name, x.amount
  from (
    select b.type as section, b.id, b.code, b.name,
           round(case when b.type = 'asset' then b.amount else -b.amount end, 2)::text as amount
    from b
    where b.type in ('asset', 'liability', 'equity') and b.amount <> 0
    union all
    select 'equity', null, null, 'أرباح (خسائر) لم تُقفل بعد',
           round(-coalesce((select sum(amount) from b where type in ('revenue', 'expense')), 0), 2)::text
  ) x
  order by case x.section when 'asset' then 1 when 'liability' then 2 else 3 end, x.code nulls last;
$$;

-- الشاشة الرئيسية (SPEC §8): أرصدة الخزائن والبنوك، العملاء، الموردين، المخزون من الأستاذ، ومبيعات الشهر
-- وصافي ربحه (بنفس تعريف قائمة الدخل، بتوقيت القاهرة)، وعدد الأصناف تحت الحد الأدنى.
create function public.dashboard_summary()
returns table (
  treasury text,
  receivables text,
  payables text,
  inventory text,
  month_sales text,
  month_net_profit text,
  low_stock_items bigint,
  month_start date,
  month_end date
)
language sql
stable
set search_path = ''
as $$
  with m as (
    select date_trunc('month', (now() at time zone 'Africa/Cairo'))::date as month_start
  ),
  bal as (
    select l.account_id, sum(l.debit - l.credit) as amount
    from public.journal_lines l
    group by l.account_id
  ),
  sys as (
    select s.key, coalesce(b.amount, 0) as amount
    from public.system_accounts s left join bal b on b.account_id = s.account_id
  ),
  month_lines as (
    select a.type, a.code, l.debit, l.credit
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    join public.accounts a on a.id = l.account_id
    where a.type in ('revenue', 'expense')
      and e.source_type <> 'closing'
      and e.entry_date >= (select month_start from m)
      and e.entry_date < ((select month_start from m) + interval '1 month')::date
  )
  select
    round((select coalesce(sum(b.amount), 0) from bal b join public.accounts a on a.id = b.account_id
           where a.is_treasury), 2)::text,
    round((select coalesce(sum(amount), 0) from sys where key = 'receivables'), 2)::text,
    round(-(select coalesce(sum(amount), 0) from sys where key = 'payables'), 2)::text,
    round((select coalesce(sum(amount), 0) from sys
           where key in ('inventory_raw', 'inventory_packaging', 'inventory_finished')), 2)::text,
    round((select coalesce(sum(credit - debit), 0) from month_lines where type = 'revenue' and code like '41%'), 2)::text,
    round((select coalesce(sum(credit - debit), 0) from month_lines), 2)::text,
    (select count(*) from public.items i join public.item_stock s on s.item_id = i.id
     where i.is_active and i.min_stock > 0 and s.qty < i.min_stock),
    (select month_start from m),
    ((select month_start from m) + interval '1 month - 1 day')::date;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات و RLS
-- ---------------------------------------------------------------------
revoke execute on function
  public.save_open_fiscal_year(text, date, date),
  public.lock_period(date),
  public.fiscal_year_closing_preview(),
  public.close_fiscal_year(),
  public.income_statement(date, date),
  public.balance_sheet(date),
  public.dashboard_summary()
from public, anon;

grant execute on function
  public.save_open_fiscal_year(text, date, date),
  public.lock_period(date),
  public.fiscal_year_closing_preview(),
  public.close_fiscal_year(),
  public.income_statement(date, date),
  public.balance_sheet(date),
  public.dashboard_summary()
to authenticated;

revoke execute on function
  private.month_end(date), private.today(), private.require_admin(), private.fiscal_year_name(date, date)
from public, anon, authenticated;

alter table public.fiscal_years enable row level security;
revoke all on public.fiscal_years from anon, authenticated;
revoke all on sequence public.fiscal_years_id_seq from anon, authenticated;
grant select on public.fiscal_years to authenticated;
create policy fiscal_years_select on public.fiscal_years for select to authenticated using (true);
