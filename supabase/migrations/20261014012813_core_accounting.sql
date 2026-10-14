-- =====================================================================
-- المرحلة 2: المحاسبة الأساسية
-- القيود اليومية، الترقيم بلا فجوات، التوازن، منع التعديل، قفل الفترة،
-- كشف الحساب، ميزان المراجعة، الأرصدة الافتتاحية للحسابات
-- =====================================================================

-- ---------------------------------------------------------------------
-- doc_counters: ترقيم متسلسل بلا فجوات لكل نوع (القاعدة 8)
-- ---------------------------------------------------------------------
create table public.doc_counters (
  kind text primary key,
  last_no bigint not null default 0 check (last_no >= 0)
);

insert into public.doc_counters (kind, last_no) values ('journal', 0);

-- ---------------------------------------------------------------------
-- journal_entries / journal_lines
-- ---------------------------------------------------------------------
create table public.journal_entries (
  id bigint generated always as identity primary key,
  entry_no bigint not null unique,
  entry_date date not null,
  description text not null check (btrim(description) <> ''),
  source_type text not null check (source_type in (
    'manual', 'opening', 'purchase', 'sale', 'voucher', 'production',
    'stock_adjustment', 'adjustment', 'closing', 'reversal'
  )),
  source_id bigint,
  reverses_entry_id bigint unique references public.journal_entries (id),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create index journal_entries_entry_date_idx on public.journal_entries (entry_date);
create index journal_entries_created_by_idx on public.journal_entries (created_by);

create table public.journal_lines (
  id bigint generated always as identity primary key,
  entry_id bigint not null references public.journal_entries (id),
  account_id bigint not null references public.accounts (id),
  debit numeric(18, 2) not null default 0,
  credit numeric(18, 2) not null default 0,
  description text,
  -- كل سطر إما مدين أو دائن وليس الاثنين (القاعدة 2)
  constraint journal_lines_one_side check (
    debit >= 0 and credit >= 0 and (debit > 0) <> (credit > 0)
  )
);

create index journal_lines_entry_id_idx on public.journal_lines (entry_id);
create index journal_lines_account_id_idx on public.journal_lines (account_id);

-- مبلغ بفاصل الآلاف لرسائل الخطأ
create function private.fmt_amount(p_amount numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(p_amount, 'FM999,999,999,999,999,990.00');
$$;

-- ---------------------------------------------------------------------
-- سلامة القيود داخل قاعدة البيانات (تسري على أي طريق كتابة)
-- ---------------------------------------------------------------------

-- قفل الفترة (القاعدة 4): يشمل كل القيود الحالية وقيود المستندات لاحقًا
create function private.check_period_open()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_lock date;
begin
  select lock_date into v_lock from public.settings where id = 1;
  if v_lock is not null and new.entry_date <= v_lock then
    raise exception 'لا يمكن التسجيل بتاريخ % لأن الفترة مقفولة حتى %',
      to_char(new.entry_date, 'DD/MM/YYYY'), to_char(v_lock, 'DD/MM/YYYY');
  end if;
  return new;
end;
$$;

create trigger check_period_open
  before insert on public.journal_entries
  for each row execute function private.check_period_open();

-- الترحيل فقط على حساب فرعي نشط، وسطور العملاء/الموردين تحتاج طرفًا (القاعدة 9)
create function private.validate_journal_line()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account public.accounts;
begin
  select * into v_account from public.accounts where id = new.account_id;
  if not found then
    raise exception 'الحساب غير موجود';
  end if;
  if not v_account.is_postable or not v_account.is_active then
    raise exception 'الترحيل مسموح فقط على حساب فرعي نشط: % - %', v_account.code, v_account.name;
  end if;
  -- حتى المرحلة 3 لا توجد جداول العملاء والموردين، فلا ترحيل على حسابيهما
  if exists (
    select 1 from public.system_accounts
    where account_id = new.account_id and key in ('receivables', 'payables')
  ) then
    raise exception 'لا يمكن الترحيل على حساب % - % بدون تحديد عميل أو مورد',
      v_account.code, v_account.name;
  end if;
  return new;
end;
$$;

create trigger validate_journal_line
  before insert on public.journal_lines
  for each row execute function private.validate_journal_line();

-- القيد متوازن دائمًا وفيه سطران على الأقل (القاعدة 2)، يُفحص عند الـ commit
create function private.check_entry_balanced()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_entry_id bigint;
  v_lines int;
  v_debit numeric;
  v_credit numeric;
begin
  if tg_table_name = 'journal_entries' then
    v_entry_id := new.id;
  else
    v_entry_id := new.entry_id;
  end if;

  select count(*), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
    into v_lines, v_debit, v_credit
  from public.journal_lines
  where entry_id = v_entry_id;

  if v_lines < 2 or v_debit <> v_credit or v_debit = 0 then
    raise exception 'القيد غير متوازن أو ناقص: مدين % ودائن % في % سطر',
      private.fmt_amount(v_debit), private.fmt_amount(v_credit), v_lines;
  end if;
  return null;
end;
$$;

create constraint trigger journal_entries_balanced
  after insert on public.journal_entries
  deferrable initially deferred
  for each row execute function private.check_entry_balanced();

create constraint trigger journal_lines_balanced
  after insert on public.journal_lines
  deferrable initially deferred
  for each row execute function private.check_entry_balanced();

-- القيد المعتمد لا يُعدَّل ولا يُحذف (القاعدة 3)
create function private.forbid_posted_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'لا يمكن تعديل أو حذف قيد معتمد. للتصحيح ألغِ القيد ثم أدخله من جديد';
end;
$$;

create trigger forbid_change
  before update or delete on public.journal_entries
  for each row execute function private.forbid_posted_change();

create trigger forbid_change
  before update or delete on public.journal_lines
  for each row execute function private.forbid_posted_change();

create trigger forbid_truncate
  before truncate on public.journal_entries
  for each statement execute function private.forbid_posted_change();

create trigger forbid_truncate
  before truncate on public.journal_lines
  for each statement execute function private.forbid_posted_change();

-- ---------------------------------------------------------------------
-- دوال الاعتماد الداخلية
-- ---------------------------------------------------------------------

-- الرقم التالي لنوع المستند. قفل الصف حتى الـ commit يمنع التكرار والفجوات.
create function private.next_doc_no(p_kind text)
returns bigint
language sql
set search_path = ''
as $$
  insert into public.doc_counters as c (kind, last_no) values (p_kind, 1)
  on conflict (kind) do update set last_no = c.last_no + 1
  returning last_no;
$$;

-- المستخدم الحالي لو كان له ملف (admin أو accountant)
create function private.require_staff()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'ليست لديك صلاحية لتنفيذ هذه العملية' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

-- مبلغ من نص: موجب، خانتان عشريتان كحد أقصى، بلا تقريب صامت. الفارغ = صفر.
create function private.parse_amount(p_value text, p_line int)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v numeric;
begin
  if p_value is null or btrim(p_value) = '' then
    return 0;
  end if;
  begin
    v := btrim(p_value)::numeric;
  exception when invalid_text_representation then
    raise exception 'السطر %: المبلغ "%" غير صالح', p_line, p_value;
  end;
  if v = 'NaN'::numeric or v < 0 then
    raise exception 'السطر %: المبلغ يجب أن يكون رقمًا موجبًا', p_line;
  end if;
  if v >= 1e16 then
    raise exception 'السطر %: المبلغ أكبر من الحد المسموح', p_line;
  end if;
  if scale(trim_scale(v)) > 2 then
    raise exception 'السطر %: المبلغ لا يزيد عن خانتين عشريتين', p_line;
  end if;
  return v;
end;
$$;

-- حسابات المخزون تتحرك من مستندات المخزون فقط (لا قيود يدوية ولا افتتاحية للحسابات)
create function private.assert_no_inventory_accounts(p_lines jsonb)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_code text;
  v_name text;
begin
  if jsonb_typeof(p_lines) is distinct from 'array' then
    return;
  end if;
  select a.code, a.name into v_code, v_name
  from jsonb_array_elements(p_lines) as l (value)
  join public.system_accounts s on s.account_id = (l.value ->> 'account_id')::bigint
  join public.accounts a on a.id = s.account_id
  where s.key in ('inventory_raw', 'inventory_packaging', 'inventory_finished')
  limit 1;
  if found then
    raise exception 'لا يمكن الترحيل يدويًا على حساب % - %. حسابات المخزون تتحرك من مستندات المخزون فقط',
      v_code, v_name;
  end if;
end;
$$;

-- الدالة الوحيدة التي تنشئ قيدًا: تتحقق ثم تكتب الرأس والسطور في نفس الـ transaction.
-- السطور: [{"account_id": 1, "debit": "100.00", "credit": "0", "description": "..."}]
create function private.post_entry(
  p_entry_date date,
  p_description text,
  p_source_type text,
  p_lines jsonb,
  p_source_id bigint default null,
  p_reverses_entry_id bigint default null
)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid := private.require_staff();
  v_line jsonb;
  v_no int := 0;
  v_debit numeric;
  v_credit numeric;
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
  v_entry_id bigint;
begin
  if p_entry_date is null then
    raise exception 'تاريخ القيد مطلوب';
  end if;
  if p_description is null or btrim(p_description) = '' then
    raise exception 'بيان القيد مطلوب';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'سطور القيد مطلوبة';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    if nullif(v_line ->> 'account_id', '') is null then
      raise exception 'السطر %: اختر الحساب', v_no;
    end if;
    v_debit := private.parse_amount(v_line ->> 'debit', v_no);
    v_credit := private.parse_amount(v_line ->> 'credit', v_no);
    if (v_debit > 0) = (v_credit > 0) then
      raise exception 'السطر %: أدخل مبلغًا في المدين أو في الدائن (واحدًا فقط)', v_no;
    end if;
    v_total_debit := v_total_debit + v_debit;
    v_total_credit := v_total_credit + v_credit;
  end loop;

  if v_no < 2 then
    raise exception 'القيد يحتاج سطرين على الأقل';
  end if;
  if v_total_debit <> v_total_credit then
    raise exception 'القيد غير متوازن: إجمالي المدين % وإجمالي الدائن %',
      private.fmt_amount(v_total_debit), private.fmt_amount(v_total_credit);
  end if;

  insert into public.journal_entries (
    entry_no, entry_date, description, source_type, source_id, reverses_entry_id, created_by
  )
  values (
    private.next_doc_no('journal'), p_entry_date, btrim(p_description), p_source_type,
    p_source_id, p_reverses_entry_id, v_user
  )
  returning id into v_entry_id;

  insert into public.journal_lines (entry_id, account_id, debit, credit, description)
  select v_entry_id,
         (l.value ->> 'account_id')::bigint,
         private.parse_amount(l.value ->> 'debit', l.ord::int),
         private.parse_amount(l.value ->> 'credit', l.ord::int),
         nullif(btrim(l.value ->> 'description'), '')
  from jsonb_array_elements(p_lines) with ordinality as l (value, ord)
  order by l.ord;

  return v_entry_id;
end;
$$;

-- ---------------------------------------------------------------------
-- دوال الاعتماد العامة (RPC): الطريق الوحيد للكتابة في القيود
-- ---------------------------------------------------------------------

-- قيد يومية يدوي أو قيد تسوية
create function public.post_journal_entry(
  p_entry_date date,
  p_description text,
  p_source_type text,
  p_lines jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_staff();
  if coalesce(p_source_type, '') not in ('manual', 'adjustment') then
    raise exception 'نوع القيد غير صالح';
  end if;
  perform private.assert_no_inventory_accounts(p_lines);
  return private.post_entry(p_entry_date, p_description, p_source_type, p_lines);
end;
$$;

-- الأرصدة الافتتاحية للحسابات: مرة واحدة، والفرق على رأس المال بعد التأكيد
create function public.post_opening_balances(
  p_entry_date date,
  p_lines jsonb,
  p_difference_to_capital boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line jsonb;
  v_no int := 0;
  v_debit numeric := 0;
  v_credit numeric := 0;
  v_diff numeric;
  v_lines jsonb := p_lines;
begin
  perform private.require_staff();

  -- قفل عدّاد القيود أولًا: أي اعتماد متزامن ينتظر ثم يرى ما سُجّل
  perform 1 from public.doc_counters where kind = 'journal' for update;

  if exists (
    select 1 from public.journal_entries o
    where o.source_type = 'opening'
      and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id)
  ) then
    raise exception 'الأرصدة الافتتاحية مسجّلة بالفعل. للتصحيح ألغِ القيد الافتتاحي ثم سجّلها من جديد';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'أدخل رصيدًا واحدًا على الأقل';
  end if;
  perform private.assert_no_inventory_accounts(p_lines);

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    v_debit := v_debit + private.parse_amount(v_line ->> 'debit', v_no);
    v_credit := v_credit + private.parse_amount(v_line ->> 'credit', v_no);
  end loop;

  v_diff := v_debit - v_credit;
  if v_diff <> 0 then
    if not coalesce(p_difference_to_capital, false) then
      raise exception 'الأرصدة غير متوازنة: المدين % والدائن % والفرق %. أكّد تسجيل الفرق على حساب رأس المال',
        private.fmt_amount(v_debit), private.fmt_amount(v_credit), private.fmt_amount(abs(v_diff));
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', (select account_id from public.system_accounts where key = 'capital'),
      'debit', case when v_diff < 0 then (-v_diff)::text else '0' end,
      'credit', case when v_diff > 0 then v_diff::text else '0' end,
      'description', 'فرق الأرصدة الافتتاحية'
    ));
  end if;

  return private.post_entry(p_entry_date, 'الأرصدة الافتتاحية', 'opening', v_lines);
end;
$$;

-- إلغاء قيد يدوي/تسوية/افتتاحي بقيد عكسي بنفس التاريخ (القاعدة 3)
create function public.cancel_journal_entry(p_entry_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.journal_entries;
  v_lines jsonb;
begin
  perform private.require_staff();

  -- قفل صف القيد يمنع إلغاءه مرتين في نفس اللحظة
  select * into v_entry from public.journal_entries where id = p_entry_id for update;
  if not found then
    raise exception 'القيد غير موجود';
  end if;
  if v_entry.source_type = 'reversal' then
    raise exception 'لا يمكن إلغاء قيد عكسي';
  end if;
  if v_entry.source_type not in ('manual', 'adjustment', 'opening') then
    raise exception 'هذا القيد يُلغى من خلال المستند المرتبط به';
  end if;
  if exists (select 1 from public.journal_entries where reverses_entry_id = p_entry_id) then
    raise exception 'القيد رقم % ملغى بالفعل', v_entry.entry_no;
  end if;

  select jsonb_agg(jsonb_build_object(
           'account_id', account_id,
           'debit', credit::text,
           'credit', debit::text,
           'description', description
         ) order by id)
    into v_lines
  from public.journal_lines
  where entry_id = p_entry_id;

  return private.post_entry(
    v_entry.entry_date,
    'إلغاء القيد رقم ' || v_entry.entry_no || ': ' || v_entry.description,
    'reversal',
    v_lines,
    null,
    p_entry_id
  );
end;
$$;

-- ---------------------------------------------------------------------
-- دوال القراءة (تُحسب من journal_lines فقط، القاعدة 10). RLS يسري عليها.
-- ---------------------------------------------------------------------

-- كشف حساب: رصيد أول المدة ثم الحركات برصيد جارٍ
create function public.account_statement(
  p_account_id bigint,
  p_from date default null,
  p_to date default null
)
returns table (
  entry_id bigint,
  entry_no bigint,
  entry_date date,
  source_type text,
  description text,
  debit numeric,
  credit numeric,
  balance numeric
)
language sql
stable
set search_path = ''
as $$
  with opening as (
    select coalesce(sum(l.debit - l.credit), 0) as amount
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    where l.account_id = p_account_id
      and p_from is not null
      and e.entry_date < p_from
  ),
  statement_rows as (
    select 0 as grp, null::bigint as line_id, null::bigint as entry_id, null::bigint as entry_no,
           p_from as entry_date, null::text as source_type, 'رصيد أول المدة' as description,
           null::numeric as debit, null::numeric as credit,
           (select amount from opening) as balance
    union all
    select 1, l.id, e.id, e.entry_no, e.entry_date, e.source_type,
           coalesce(l.description, e.description), l.debit, l.credit,
           (select amount from opening)
             + sum(l.debit - l.credit) over (order by e.entry_date, e.entry_no, l.id)
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    where l.account_id = p_account_id
      and (p_from is null or e.entry_date >= p_from)
      and (p_to is null or e.entry_date <= p_to)
  )
  select entry_id, entry_no, entry_date, source_type, description, debit, credit, balance
  from statement_rows
  order by grp, entry_date, entry_no, line_id;
$$;

-- ميزان المراجعة بالأرصدة: لكل حساب رصيده المدين أو الدائن حتى التاريخ
create function public.trial_balance(p_as_of date default null)
returns table (
  account_id bigint,
  code text,
  name text,
  type text,
  debit numeric,
  credit numeric
)
language sql
stable
set search_path = ''
as $$
  select a.id, a.code, a.name, a.type, greatest(b.amount, 0), greatest(-b.amount, 0)
  from (
    select l.account_id, sum(l.debit - l.credit) as amount
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    where p_as_of is null or e.entry_date <= p_as_of
    group by l.account_id
  ) b
  join public.accounts a on a.id = b.account_id
  where b.amount <> 0
  order by a.code;
$$;

-- قائمة القيود بالإجمالي وحالة الإلغاء
create function public.journal_entry_list(
  p_from date default null,
  p_to date default null,
  p_search text default null
)
returns table (
  id bigint,
  entry_no bigint,
  entry_date date,
  source_type text,
  description text,
  total numeric,
  reverses_entry_id bigint,
  reversed_by_entry_id bigint
)
language sql
stable
set search_path = ''
as $$
  select e.id, e.entry_no, e.entry_date, e.source_type, e.description,
         (select sum(l.debit) from public.journal_lines l where l.entry_id = e.id),
         e.reverses_entry_id,
         (select r.id from public.journal_entries r where r.reverses_entry_id = e.id)
  from public.journal_entries e
  where (p_from is null or e.entry_date >= p_from)
    and (p_to is null or e.entry_date <= p_to)
    and (
      coalesce(btrim(p_search), '') = ''
      or e.entry_no::text = btrim(p_search)
      or e.description ilike '%' || btrim(p_search) || '%'
    )
  order by e.entry_date desc, e.entry_no desc;
$$;

-- ---------------------------------------------------------------------
-- تحديث قواعد دليل الحسابات (المرحلة 1) بعد وجود القيود
-- ---------------------------------------------------------------------
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

create or replace function private.guard_account_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from public.system_accounts where account_id = old.id) then
    raise exception 'لا يمكن حذف حساب نظام';
  end if;
  if exists (select 1 from public.accounts where parent_id = old.id) then
    raise exception 'لا يمكن حذف حساب له حسابات فرعية';
  end if;
  if exists (select 1 from public.journal_lines where account_id = old.id) then
    raise exception 'لا يمكن حذف حساب عليه قيود. يمكنك تعطيله بدل الحذف';
  end if;
  return old;
end;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات و RLS: القراءة للمستخدمين، والكتابة عبر الدوال فقط
-- ---------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_admin() to authenticated;

revoke execute on function
  public.post_journal_entry(date, text, text, jsonb),
  public.post_opening_balances(date, jsonb, boolean),
  public.cancel_journal_entry(bigint),
  public.account_statement(bigint, date, date),
  public.trial_balance(date),
  public.journal_entry_list(date, date, text)
from public, anon;

grant execute on function
  public.post_journal_entry(date, text, text, jsonb),
  public.post_opening_balances(date, jsonb, boolean),
  public.cancel_journal_entry(bigint),
  public.account_statement(bigint, date, date),
  public.trial_balance(date),
  public.journal_entry_list(date, date, text)
to authenticated;

alter table public.doc_counters enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

revoke all on public.doc_counters, public.journal_entries, public.journal_lines
  from anon, authenticated;

grant select on public.journal_entries, public.journal_lines to authenticated;

create policy journal_entries_select on public.journal_entries
  for select to authenticated
  using (true);

create policy journal_lines_select on public.journal_lines
  for select to authenticated
  using (true);
