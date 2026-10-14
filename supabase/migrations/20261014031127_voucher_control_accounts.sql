-- =====================================================================
-- المرحلة 3 (تحقق): حماية حسابات النظام من السندات داخل قاعدة البيانات
-- - حساب النظام لا يكون خزينة، ولا يُربط مفتاح نظام بحساب خزينة.
-- - سطور القيود: حسابات المستندات حسب نوع القيد (المخزون لا يأتي من قيد يدوي أو سند،
--   والعملاء/الموردين لا يأتون من قيد يدوي، وإيرادات المبيعات وتكلفتها وفروقات الجرد لا تأتي من سند).
-- - السند نفسه: خزينته حساب خزينة غير نظامي، وحسابه الآخر ليس حساب مستندات.
-- =====================================================================

-- لا يُطبَّق لو يوجد حساب نظام معلَّم كخزينة (يجب تصحيحه أولًا)
do $$
begin
  if exists (
    select 1 from public.accounts a join public.system_accounts s on s.account_id = a.id
    where a.is_treasury
  ) then
    raise exception 'يوجد حساب نظام معلَّم كخزينة أو بنك. أزل العلامة أولًا';
  end if;
end;
$$;

-- مفاتيح النظام المربوطة بحساب (قد يُربط أكثر من مفتاح بنفس الحساب)
create function private.account_keys(p_account_id bigint)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(key), '{}') from public.system_accounts where account_id = p_account_id;
$$;

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

-- سطر القيد: حساب فرعي نشط، حسابات المستندات حسب نوع القيد، والطرف على العملاء/الموردين فقط
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
  return new;
end;
$$;

-- السند نفسه (أي طريق إدخال): خزينته حساب خزينة غير نظامي، وحسابه الآخر ليس حساب مستندات
create function private.validate_voucher()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_treasury public.accounts;
begin
  select * into v_treasury from public.accounts where id = new.treasury_account_id;
  if not found or not v_treasury.is_treasury or not v_treasury.is_postable
     or cardinality(private.account_keys(new.treasury_account_id)) > 0 then
    raise exception 'خزينة السند يجب أن تكون حساب خزينة أو بنك';
  end if;
  if new.account_id is not null
     and private.account_keys(new.account_id) && array[
       'receivables', 'payables', 'inventory_raw', 'inventory_packaging', 'inventory_finished',
       'sales_revenue', 'cogs', 'inventory_adjustment'
     ] then
    raise exception 'لا يمكن استخدام حساب نظام يتحرك من مستنداته كحساب آخر في السند';
  end if;
  return new;
end;
$$;

create trigger validate_voucher
  before insert on public.vouchers
  for each row execute function private.validate_voucher();

create or replace function public.post_voucher(
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
  v_keys text[];
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
  if not found or not v_treasury.is_treasury
     or cardinality(private.account_keys(p_treasury_account_id)) > 0 then
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
      -- حسابات المستندات لا تُختار كحساب آخر (نفس القاعدة في trigger السند وسطور القيد)
      v_keys := private.account_keys(p_party_id);
      if v_keys && array['receivables', 'payables'] then
        raise exception 'الحساب % حساب أطراف: اختر العميل أو المورد بدلًا منه', v_label;
      elsif v_keys && array['inventory_raw', 'inventory_packaging', 'inventory_finished'] then
        raise exception 'لا يمكن استخدام حساب المخزون % في السندات. حسابات المخزون تتحرك من مستندات المخزون فقط',
          v_label;
      elsif v_keys && array['sales_revenue', 'cogs', 'inventory_adjustment'] then
        raise exception 'لا يمكن استخدام الحساب % في السندات. يتحرك من مستنداته فقط (فواتير المبيعات أو تسوية الجرد)',
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

revoke execute on function
  private.account_keys(bigint),
  private.validate_voucher()
from public, anon, authenticated;
