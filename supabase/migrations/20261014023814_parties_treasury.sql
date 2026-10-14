-- =====================================================================
-- المرحلة 3: العملاء والموردون والخزينة
-- الأطراف، سندات القبض والصرف، كشف حساب طرف، الأرصدة الافتتاحية للأطراف،
-- وتفعيل القاعدة 9 (سطور العملاء والموردين تحمل الطرف)
-- =====================================================================

-- ---------------------------------------------------------------------
-- customers / suppliers (الرصيد يُقرأ من القيود)
-- ---------------------------------------------------------------------
create table public.customers (
  id bigint generated always as identity primary key,
  name text not null unique check (btrim(name) <> ''),
  phone text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.suppliers (
  id bigint generated always as identity primary key,
  name text not null unique check (btrim(name) <> ''),
  phone text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- journal_lines: الطرف على سطور العملاء والموردين (القاعدة 9)
-- ---------------------------------------------------------------------
alter table public.journal_lines
  add column customer_id bigint references public.customers (id),
  add column supplier_id bigint references public.suppliers (id),
  add constraint journal_lines_one_party check (customer_id is null or supplier_id is null);

create index journal_lines_customer_id_idx on public.journal_lines (customer_id)
  where customer_id is not null;
create index journal_lines_supplier_id_idx on public.journal_lines (supplier_id)
  where supplier_id is not null;

-- ---------------------------------------------------------------------
-- vouchers: سندات القبض والصرف. الحالة «ملغى» تُستنتج من القيد العكسي،
-- فالسند لا يُعدَّل أبدًا بعد الاعتماد (القاعدة 3)
-- ---------------------------------------------------------------------
create table public.vouchers (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('receipt', 'payment')),
  doc_no bigint not null,
  doc_date date not null,
  treasury_account_id bigint not null references public.accounts (id),
  party_kind text not null check (party_kind in ('customer', 'supplier', 'account')),
  customer_id bigint references public.customers (id),
  supplier_id bigint references public.suppliers (id),
  account_id bigint references public.accounts (id),
  amount numeric(18, 2) not null check (amount > 0),
  notes text,
  journal_entry_id bigint not null unique references public.journal_entries (id),
  created_at timestamptz not null default now(),
  unique (kind, doc_no),
  -- طرف واحد فقط ويطابق party_kind
  constraint vouchers_one_counterpart check (
    (customer_id is not null) = (party_kind = 'customer')
    and (supplier_id is not null) = (party_kind = 'supplier')
    and (account_id is not null) = (party_kind = 'account')
  ),
  constraint vouchers_distinct_accounts check (account_id <> treasury_account_id)
);

create index vouchers_doc_date_idx on public.vouchers (doc_date);
create index vouchers_treasury_account_id_idx on public.vouchers (treasury_account_id);
create index vouchers_customer_id_idx on public.vouchers (customer_id) where customer_id is not null;
create index vouchers_supplier_id_idx on public.vouchers (supplier_id) where supplier_id is not null;
create index vouchers_account_id_idx on public.vouchers (account_id) where account_id is not null;

-- ترقيم مستقل بلا فجوات لكل نوع سند (القاعدة 8)
insert into public.doc_counters (kind, last_no)
values ('receipt_voucher', 0), ('payment_voucher', 0);

-- المستند المعتمد لا يُعدَّل ولا يُحذف (القاعدة 3)
create function private.forbid_document_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'لا يمكن تعديل أو حذف مستند معتمد. للتصحيح ألغِ المستند ثم أدخله من جديد';
end;
$$;

create trigger forbid_change
  before update or delete on public.vouchers
  for each row execute function private.forbid_document_change();

create trigger forbid_truncate
  before truncate on public.vouchers
  for each statement execute function private.forbid_document_change();

-- ---------------------------------------------------------------------
-- القاعدة 9: سطر العملاء يحمل عميلًا، وسطر الموردين يحمل موردًا، ولا طرف على غيرهما
-- ---------------------------------------------------------------------
create or replace function private.validate_journal_line()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_key text;
begin
  select * into v_account from public.accounts where id = new.account_id;
  if not found then
    raise exception 'الحساب غير موجود';
  end if;
  if not v_account.is_postable or not v_account.is_active then
    raise exception 'الترحيل مسموح فقط على حساب فرعي نشط: % - %', v_account.code, v_account.name;
  end if;

  select key into v_key
  from public.system_accounts
  where account_id = new.account_id and key in ('receivables', 'payables');

  if v_key = 'receivables' then
    if new.customer_id is null then
      raise exception 'الترحيل على حساب % - % يتطلب تحديد العميل', v_account.code, v_account.name;
    end if;
    if new.supplier_id is not null then
      raise exception 'لا يُسمح بتحديد مورد على حساب % - %', v_account.code, v_account.name;
    end if;
  elsif v_key = 'payables' then
    if new.supplier_id is null then
      raise exception 'الترحيل على حساب % - % يتطلب تحديد المورد', v_account.code, v_account.name;
    end if;
    if new.customer_id is not null then
      raise exception 'لا يُسمح بتحديد عميل على حساب % - %', v_account.code, v_account.name;
    end if;
  elsif new.customer_id is not null or new.supplier_id is not null then
    raise exception 'لا يُسمح بتحديد عميل أو مورد على حساب % - %', v_account.code, v_account.name;
  end if;
  return new;
end;
$$;

-- لا يتغيّر ربط حساب العملاء أو الموردين بعد وجود قيود (حتى يطابق مجموع أرصدة الأطراف رصيد الحساب)
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

  if tg_op = 'UPDATE'
     and new.key in ('receivables', 'payables')
     and new.account_id is distinct from old.account_id
     and exists (
       select 1 from public.journal_lines where account_id in (old.account_id, new.account_id)
     ) then
    raise exception 'لا يمكن تغيير حساب % بعد وجود قيود على الحساب الحالي أو الجديد',
      case new.key when 'receivables' then 'العملاء' else 'الموردين' end;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- دوال داخلية
-- ---------------------------------------------------------------------

-- مبلغ من نص: موجب، خانتان عشريتان كحد أقصى، بلا تقريب صامت. الفارغ = صفر.
-- p_context يسبق الرسالة (مثل «السطر 2: »)
create function private.to_amount(p_value text, p_context text)
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
    raise exception '%المبلغ "%" غير صالح', p_context, p_value;
  end;
  if v = 'NaN'::numeric or v < 0 then
    raise exception '%المبلغ يجب أن يكون رقمًا موجبًا', p_context;
  end if;
  if v >= 1e16 then
    raise exception '%المبلغ أكبر من الحد المسموح', p_context;
  end if;
  if scale(trim_scale(v)) > 2 then
    raise exception '%المبلغ لا يزيد عن خانتين عشريتين', p_context;
  end if;
  return v;
end;
$$;

-- نفس الرسائل السابقة (السطر n: ...)
create or replace function private.parse_amount(p_value text, p_line int)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
begin
  return private.to_amount(p_value, 'السطر ' || p_line || ': ');
end;
$$;

-- حسابات العملاء والموردين لا تُستخدم في القيود اليدوية ولا في أرصدة الحسابات الافتتاحية
create function private.assert_no_party_accounts(p_lines jsonb)
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
  join public.system_accounts s on s.account_id = nullif(l.value ->> 'account_id', '')::bigint
  join public.accounts a on a.id = s.account_id
  where s.key in ('receivables', 'payables')
  limit 1;
  if found then
    raise exception 'لا يمكن الترحيل يدويًا على حساب % - %. حسابات العملاء والموردين تتحرك من السندات والأرصدة الافتتاحية للأطراف فقط',
      v_code, v_name;
  end if;
end;
$$;

-- جزء القيد الافتتاحي من سطوره: سطور بطرف = العملاء والموردين، وغير ذلك = الحسابات.
-- الأجزاء لا تشترك في أي حساب غير رأس المال، فالتمييز دقيق (المرحلة 4 تضيف المخزون).
create function private.opening_part(p_entry_id bigint)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when exists (
      select 1 from public.journal_lines
      where entry_id = p_entry_id and (customer_id is not null or supplier_id is not null)
    ) then 'parties'
    else 'accounts'
  end;
$$;

-- الدالة الوحيدة التي تنشئ قيدًا: تتحقق ثم تكتب الرأس والسطور في نفس الـ transaction.
-- السطور: [{"account_id": 1, "debit": "100.00", "credit": "0", "description": "...",
--           "customer_id": null, "supplier_id": null}]
create or replace function private.post_entry(
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

  insert into public.journal_lines (
    entry_id, account_id, debit, credit, description, customer_id, supplier_id
  )
  select v_entry_id,
         (l.value ->> 'account_id')::bigint,
         private.parse_amount(l.value ->> 'debit', l.ord::int),
         private.parse_amount(l.value ->> 'credit', l.ord::int),
         nullif(btrim(l.value ->> 'description'), ''),
         nullif(l.value ->> 'customer_id', '')::bigint,
         nullif(l.value ->> 'supplier_id', '')::bigint
  from jsonb_array_elements(p_lines) with ordinality as l (value, ord)
  order by l.ord;

  return v_entry_id;
end;
$$;

-- قيد عكسي بنفس التاريخ وسطور معكوسة بنفس الأطراف. قفل صف القيد يمنع الإلغاء مرتين.
create function private.reverse_entry(p_entry_id bigint, p_description text)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_entry public.journal_entries;
  v_lines jsonb;
begin
  select * into v_entry from public.journal_entries where id = p_entry_id for update;
  if not found then
    raise exception 'القيد غير موجود';
  end if;
  if v_entry.source_type = 'reversal' then
    raise exception 'لا يمكن إلغاء قيد عكسي';
  end if;
  if exists (select 1 from public.journal_entries where reverses_entry_id = p_entry_id) then
    raise exception 'القيد رقم % ملغى بالفعل', v_entry.entry_no;
  end if;

  select jsonb_agg(jsonb_build_object(
           'account_id', account_id,
           'debit', credit::text,
           'credit', debit::text,
           'description', description,
           'customer_id', customer_id,
           'supplier_id', supplier_id
         ) order by id)
    into v_lines
  from public.journal_lines
  where entry_id = p_entry_id;

  return private.post_entry(v_entry.entry_date, p_description, 'reversal', v_lines, null, p_entry_id);
end;
$$;

-- ---------------------------------------------------------------------
-- دوال المرحلة 2 بعد تفعيل الأطراف (نفس التوقيع)
-- ---------------------------------------------------------------------

-- قيد يومية يدوي أو قيد تسوية
create or replace function public.post_journal_entry(
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
  perform private.assert_no_party_accounts(p_lines);
  return private.post_entry(p_entry_date, p_description, p_source_type, p_lines);
end;
$$;

-- الأرصدة الافتتاحية للحسابات: مرة واحدة لجزء الحسابات، والفرق على رأس المال بعد التأكيد
create or replace function public.post_opening_balances(
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

  -- قفل عدّاد القيود أولًا: أي اعتماد افتتاحي متزامن ينتظر ثم يرى ما سُجّل
  perform 1 from public.doc_counters where kind = 'journal' for update;

  if exists (
    select 1 from public.journal_entries o
    where o.source_type = 'opening'
      and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id)
      and private.opening_part(o.id) = 'accounts'
  ) then
    raise exception 'الأرصدة الافتتاحية مسجّلة بالفعل. للتصحيح ألغِ القيد الافتتاحي ثم سجّلها من جديد';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'أدخل رصيدًا واحدًا على الأقل';
  end if;
  perform private.assert_no_inventory_accounts(p_lines);
  perform private.assert_no_party_accounts(p_lines);

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
create or replace function public.cancel_journal_entry(p_entry_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.journal_entries;
begin
  perform private.require_staff();

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

  return private.reverse_entry(
    p_entry_id,
    'إلغاء القيد رقم ' || v_entry.entry_no || ': ' || v_entry.description
  );
end;
$$;

-- ---------------------------------------------------------------------
-- دوال الاعتماد الجديدة (RPC)
-- ---------------------------------------------------------------------

-- الأرصدة الافتتاحية للعملاء والموردين: قيد واحد لكل الأطراف، مرة واحدة،
-- والفرق على رأس المال بعد التأكيد.
-- السطور: [{"customer_id": 1, "debit": "2700", "credit": ""}, {"supplier_id": 2, "debit": "", "credit": "10500"}]
create function public.post_party_opening_balances(
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
  v_customer_id bigint;
  v_supplier_id bigint;
  v_name text;
  v_debit numeric;
  v_credit numeric;
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
  v_diff numeric;
  v_seen_customers bigint[] := '{}';
  v_seen_suppliers bigint[] := '{}';
  v_receivables bigint := (select account_id from public.system_accounts where key = 'receivables');
  v_payables bigint := (select account_id from public.system_accounts where key = 'payables');
  v_lines jsonb := '[]'::jsonb;
begin
  perform private.require_staff();

  -- نفس قفل الأرصدة الافتتاحية للحسابات: الاعتماد المتزامن ينتظر ثم يرى ما سُجّل
  perform 1 from public.doc_counters where kind = 'journal' for update;

  if exists (
    select 1 from public.journal_entries o
    where o.source_type = 'opening'
      and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id)
      and private.opening_part(o.id) = 'parties'
  ) then
    raise exception 'أرصدة العملاء والموردين الافتتاحية مسجّلة بالفعل. للتصحيح ألغِ قيدها ثم سجّلها من جديد';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'أدخل رصيدًا واحدًا على الأقل';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    v_customer_id := nullif(v_line ->> 'customer_id', '')::bigint;
    v_supplier_id := nullif(v_line ->> 'supplier_id', '')::bigint;

    if (v_customer_id is null) = (v_supplier_id is null) then
      raise exception 'السطر %: حدد عميلًا أو موردًا (واحدًا فقط)', v_no;
    end if;

    if v_customer_id is not null then
      select name into v_name from public.customers where id = v_customer_id and is_active;
      if not found then
        raise exception 'السطر %: العميل غير موجود أو معطّل', v_no;
      end if;
      if v_customer_id = any (v_seen_customers) then
        raise exception 'السطر %: العميل "%" مكرر', v_no, v_name;
      end if;
      v_seen_customers := v_seen_customers || v_customer_id;
    else
      select name into v_name from public.suppliers where id = v_supplier_id and is_active;
      if not found then
        raise exception 'السطر %: المورد غير موجود أو معطّل', v_no;
      end if;
      if v_supplier_id = any (v_seen_suppliers) then
        raise exception 'السطر %: المورد "%" مكرر', v_no, v_name;
      end if;
      v_seen_suppliers := v_seen_suppliers || v_supplier_id;
    end if;

    v_debit := private.parse_amount(v_line ->> 'debit', v_no);
    v_credit := private.parse_amount(v_line ->> 'credit', v_no);
    if (v_debit > 0) = (v_credit > 0) then
      raise exception 'السطر %: أدخل الرصيد في المدين أو في الدائن (واحدًا فقط)', v_no;
    end if;
    v_total_debit := v_total_debit + v_debit;
    v_total_credit := v_total_credit + v_credit;

    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', case when v_customer_id is not null then v_receivables else v_payables end,
      'customer_id', v_customer_id,
      'supplier_id', v_supplier_id,
      'debit', v_debit::text,
      'credit', v_credit::text,
      'description', v_name
    ));
  end loop;

  v_diff := v_total_debit - v_total_credit;
  if v_diff <> 0 then
    if not coalesce(p_difference_to_capital, false) then
      raise exception 'الأرصدة غير متوازنة: المدين % والدائن % والفرق %. أكّد تسجيل الفرق على حساب رأس المال',
        private.fmt_amount(v_total_debit), private.fmt_amount(v_total_credit), private.fmt_amount(abs(v_diff));
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', (select account_id from public.system_accounts where key = 'capital'),
      'debit', case when v_diff < 0 then (-v_diff)::text else '0' end,
      'credit', case when v_diff > 0 then v_diff::text else '0' end,
      'description', 'فرق الأرصدة الافتتاحية'
    ));
  end if;

  return private.post_entry(p_entry_date, 'الأرصدة الافتتاحية للعملاء والموردين', 'opening', v_lines);
end;
$$;

-- سند قبض أو صرف: يُعتمد مع قيده في نفس الـ transaction (القاعدة 1).
-- القبض: م الخزينة/البنك / د الطرف. الصرف: م الطرف / د الخزينة/البنك.
-- الطرف: عميل (حساب العملاء + customer_id) أو مورد (حساب الموردين + supplier_id) أو حساب آخر.
create function public.post_voucher(
  p_kind text,
  p_doc_date date,
  p_treasury_account_id bigint,
  p_party_kind text,
  p_party_id bigint,
  p_amount text,
  p_notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_treasury public.accounts;
  v_amount numeric;
  v_label text;
  v_key text;
  v_counter_account bigint;
  v_customer_id bigint;
  v_supplier_id bigint;
  v_account_id bigint;
  v_notes text := nullif(btrim(p_notes), '');
  v_id bigint;
  v_no bigint;
  v_treasury_line jsonb;
  v_counter_line jsonb;
  v_entry_id bigint;
begin
  perform private.require_staff();

  if coalesce(p_kind, '') not in ('receipt', 'payment') then
    raise exception 'نوع السند غير صالح';
  end if;
  if p_doc_date is null then
    raise exception 'تاريخ السند مطلوب';
  end if;

  select * into v_treasury from public.accounts where id = p_treasury_account_id;
  if not found or not v_treasury.is_treasury then
    raise exception 'اختر خزينة أو بنكًا';
  end if;

  case coalesce(p_party_kind, '')
    when 'customer' then
      select 'العميل ' || name into v_label from public.customers where id = p_party_id and is_active;
      if not found then
        raise exception 'اختر عميلًا نشطًا';
      end if;
      v_customer_id := p_party_id;
      v_counter_account := (select account_id from public.system_accounts where key = 'receivables');
    when 'supplier' then
      select 'المورد ' || name into v_label from public.suppliers where id = p_party_id and is_active;
      if not found then
        raise exception 'اختر موردًا نشطًا';
      end if;
      v_supplier_id := p_party_id;
      v_counter_account := (select account_id from public.system_accounts where key = 'payables');
    when 'account' then
      select code || ' - ' || name into v_label from public.accounts where id = p_party_id;
      if not found then
        raise exception 'اختر الحساب';
      end if;
      if p_party_id = p_treasury_account_id then
        raise exception 'اختر حسابًا غير الخزينة أو البنك المختار';
      end if;
      select key into v_key
      from public.system_accounts
      where account_id = p_party_id
        and key in ('receivables', 'payables', 'inventory_raw', 'inventory_packaging', 'inventory_finished');
      if v_key in ('receivables', 'payables') then
        raise exception 'الحساب % حساب أطراف: اختر العميل أو المورد بدلًا منه', v_label;
      elsif v_key is not null then
        raise exception 'لا يمكن استخدام حساب المخزون % في السندات. حسابات المخزون تتحرك من مستندات المخزون فقط',
          v_label;
      end if;
      v_account_id := p_party_id;
      v_counter_account := p_party_id;
    else
      raise exception 'اختر نوع الطرف: عميل أو مورد أو حساب';
  end case;

  v_amount := private.to_amount(p_amount, '');
  if v_amount = 0 then
    raise exception 'المبلغ مطلوب ويجب أن يكون أكبر من صفر';
  end if;

  -- رقم السند ثم القيد (نفس الترتيب دائمًا). معرّف السند يُحجز أولًا ليُربط به القيد.
  v_id := nextval(pg_get_serial_sequence('public.vouchers', 'id'));
  v_no := private.next_doc_no(p_kind || '_voucher');

  v_treasury_line := jsonb_build_object(
    'account_id', p_treasury_account_id,
    'debit', case when p_kind = 'receipt' then v_amount::text else '0' end,
    'credit', case when p_kind = 'payment' then v_amount::text else '0' end
  );
  v_counter_line := jsonb_build_object(
    'account_id', v_counter_account,
    'debit', case when p_kind = 'payment' then v_amount::text else '0' end,
    'credit', case when p_kind = 'receipt' then v_amount::text else '0' end,
    'customer_id', v_customer_id,
    'supplier_id', v_supplier_id
  );

  v_entry_id := private.post_entry(
    p_doc_date,
    case p_kind when 'receipt' then 'سند قبض رقم ' else 'سند صرف رقم ' end
      || v_no || ' - ' || v_label || coalesce(' - ' || v_notes, ''),
    'voucher',
    case p_kind
      when 'receipt' then jsonb_build_array(v_treasury_line, v_counter_line)
      else jsonb_build_array(v_counter_line, v_treasury_line)
    end,
    v_id
  );

  insert into public.vouchers (
    id, kind, doc_no, doc_date, treasury_account_id, party_kind,
    customer_id, supplier_id, account_id, amount, notes, journal_entry_id
  )
  overriding system value
  values (
    v_id, p_kind, v_no, p_doc_date, p_treasury_account_id, p_party_kind,
    v_customer_id, v_supplier_id, v_account_id, v_amount, v_notes, v_entry_id
  );

  return v_id;
end;
$$;

-- إلغاء سند بقيد عكسي بنفس التاريخ (القاعدة 3)
create function public.cancel_voucher(p_voucher_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_voucher public.vouchers;
  v_title text;
begin
  perform private.require_staff();

  -- قفل صف السند يمنع إلغاءه مرتين في نفس اللحظة
  select * into v_voucher from public.vouchers where id = p_voucher_id for update;
  if not found then
    raise exception 'السند غير موجود';
  end if;
  v_title := case v_voucher.kind when 'receipt' then 'سند القبض' else 'سند الصرف' end;
  if exists (select 1 from public.journal_entries where reverses_entry_id = v_voucher.journal_entry_id) then
    raise exception '% رقم % ملغى بالفعل', v_title, v_voucher.doc_no;
  end if;

  return private.reverse_entry(v_voucher.journal_entry_id, 'إلغاء ' || v_title || ' رقم ' || v_voucher.doc_no);
end;
$$;

-- ---------------------------------------------------------------------
-- دوال القراءة (من journal_lines فقط، القاعدة 10). RLS يسري عليها، والمبالغ نصوص.
-- ---------------------------------------------------------------------

-- كشف حساب عميل أو مورد: رصيد أول المدة ثم الحركات برصيد جارٍ (مدين موجب)
create function public.party_statement(
  p_party_kind text,
  p_party_id bigint,
  p_from date default null,
  p_to date default null
)
returns table (
  entry_id bigint,
  entry_no bigint,
  entry_date date,
  source_type text,
  description text,
  debit text,
  credit text,
  balance text
)
language sql
stable
set search_path = ''
as $$
  with party_lines as (
    select l.id as line_id, l.entry_id, l.debit, l.credit,
           e.entry_no, e.entry_date, e.source_type, e.description
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    where (p_party_kind = 'customer' and l.customer_id = p_party_id)
       or (p_party_kind = 'supplier' and l.supplier_id = p_party_id)
  ),
  opening as (
    select coalesce(sum(debit - credit), 0) as amount
    from party_lines
    where p_from is not null and entry_date < p_from
  ),
  statement_rows as (
    select 0 as grp, null::bigint as line_id, null::bigint as entry_id, null::bigint as entry_no,
           p_from as entry_date, null::text as source_type, 'رصيد أول المدة' as description,
           null::numeric as debit, null::numeric as credit,
           (select amount from opening) as balance
    union all
    select 1, line_id, entry_id, entry_no, entry_date, source_type, description, debit, credit,
           (select amount from opening)
             + sum(debit - credit) over (order by entry_date, entry_no, line_id)
    from party_lines
    where (p_from is null or entry_date >= p_from)
      and (p_to is null or entry_date <= p_to)
  )
  select entry_id, entry_no, entry_date, source_type, description,
         round(debit, 2)::text, round(credit, 2)::text, round(balance, 2)::text
  from statement_rows
  order by grp, entry_date, entry_no, line_id;
$$;

-- رصيد كل عميل أو مورد عليه قيود (مدين موجب، دائن سالب)
create function public.party_balances(p_party_kind text, p_as_of date default null)
returns table (party_id bigint, balance text)
language sql
stable
set search_path = ''
as $$
  select b.party_id, round(b.amount, 2)::text
  from (
    select case p_party_kind when 'customer' then l.customer_id else l.supplier_id end as party_id,
           sum(l.debit - l.credit) as amount
    from public.journal_lines l
    join public.journal_entries e on e.id = l.entry_id
    where (p_as_of is null or e.entry_date <= p_as_of)
      and case p_party_kind
            when 'customer' then l.customer_id is not null
            when 'supplier' then l.supplier_id is not null
            else false
          end
    group by 1
  ) b
  order by b.party_id;
$$;

-- قائمة السندات بالطرف والحالة (ملغى = لقيده قيد عكسي)
create function public.voucher_list(
  p_kind text,
  p_from date default null,
  p_to date default null,
  p_search text default null
)
returns table (
  id bigint,
  doc_no bigint,
  doc_date date,
  treasury text,
  party_kind text,
  party_name text,
  amount text,
  notes text,
  journal_entry_id bigint,
  is_cancelled boolean
)
language sql
stable
set search_path = ''
as $$
  select v.id, v.doc_no, v.doc_date, t.code || ' - ' || t.name, v.party_kind,
         coalesce(c.name, s.name, a.code || ' - ' || a.name),
         round(v.amount, 2)::text, v.notes, v.journal_entry_id,
         exists (select 1 from public.journal_entries r where r.reverses_entry_id = v.journal_entry_id)
  from public.vouchers v
  join public.accounts t on t.id = v.treasury_account_id
  left join public.customers c on c.id = v.customer_id
  left join public.suppliers s on s.id = v.supplier_id
  left join public.accounts a on a.id = v.account_id
  where v.kind = p_kind
    and (p_from is null or v.doc_date >= p_from)
    and (p_to is null or v.doc_date <= p_to)
    and (
      coalesce(btrim(p_search), '') = ''
      or v.doc_no::text = btrim(p_search)
      or coalesce(c.name, s.name, a.name) ilike '%' || btrim(p_search) || '%'
      or v.notes ilike '%' || btrim(p_search) || '%'
    )
  order by v.doc_date desc, v.doc_no desc;
$$;

-- القيود الافتتاحية النشطة (غير الملغاة) وجزء كل منها
create function public.active_openings()
returns table (part text, entry_id bigint, entry_no bigint, entry_date date)
language sql
stable
set search_path = ''
as $$
  select private.opening_part(o.id), o.id, o.entry_no, o.entry_date
  from public.journal_entries o
  where o.source_type = 'opening'
    and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id)
  order by o.entry_no;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات و RLS: الأطراف للمدير والمحاسب، والسندات قراءة فقط (الكتابة عبر الدوال)
-- ---------------------------------------------------------------------
revoke execute on function
  private.forbid_document_change(),
  private.to_amount(text, text),
  private.assert_no_party_accounts(jsonb),
  private.opening_part(bigint),
  private.reverse_entry(bigint, text)
from public, anon, authenticated;

-- active_openings (SECURITY INVOKER) تحتاج تحديد الجزء؛ قراءة فقط وRLS يسري
grant execute on function private.opening_part(bigint) to authenticated;

revoke execute on function
  public.post_party_opening_balances(date, jsonb, boolean),
  public.post_voucher(text, date, bigint, text, bigint, text, text),
  public.cancel_voucher(bigint),
  public.party_statement(text, bigint, date, date),
  public.party_balances(text, date),
  public.voucher_list(text, date, date, text),
  public.active_openings()
from public, anon;

grant execute on function
  public.post_party_opening_balances(date, jsonb, boolean),
  public.post_voucher(text, date, bigint, text, bigint, text, text),
  public.cancel_voucher(bigint),
  public.party_statement(text, bigint, date, date),
  public.party_balances(text, date),
  public.voucher_list(text, date, date, text),
  public.active_openings()
to authenticated;

alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.vouchers enable row level security;

revoke all on public.customers, public.suppliers, public.vouchers from anon, authenticated;
revoke all on sequence public.customers_id_seq, public.suppliers_id_seq, public.vouchers_id_seq
  from anon, authenticated;

grant select, delete on public.customers, public.suppliers to authenticated;
grant insert (name, phone, address, notes, is_active), update (name, phone, address, notes, is_active)
  on public.customers, public.suppliers to authenticated;
grant select on public.vouchers to authenticated;

create policy customers_select on public.customers
  for select to authenticated
  using (true);

create policy customers_insert on public.customers
  for insert to authenticated
  with check (true);

create policy customers_update on public.customers
  for update to authenticated
  using (true)
  with check (true);

create policy customers_delete on public.customers
  for delete to authenticated
  using (true);

create policy suppliers_select on public.suppliers
  for select to authenticated
  using (true);

create policy suppliers_insert on public.suppliers
  for insert to authenticated
  with check (true);

create policy suppliers_update on public.suppliers
  for update to authenticated
  using (true)
  with check (true);

create policy suppliers_delete on public.suppliers
  for delete to authenticated
  using (true);

create policy vouchers_select on public.vouchers
  for select to authenticated
  using (true);
