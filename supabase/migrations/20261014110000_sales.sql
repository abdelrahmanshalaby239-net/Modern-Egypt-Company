-- =====================================================================
-- المرحلة 6: المبيعات — فاتورة المبيعات بالوحدات، تكلفة المبيعات بمتوسط التكلفة وقت البيع، التحصيل
-- الكامل أو الجزئي أو الآجل بسند قبض تلقائي (SPEC §6.2)، الإلغاء، وتقرير أرباح الأصناف (SPEC §8).
-- ترحيل إضافي فقط (بلا DROP).
-- =====================================================================

-- ---------------------------------------------------------------------
-- فواتير المبيعات (ثابتة بعد الاعتماد، و«ملغاة» = لقيدها قيد عكسي)
-- ---------------------------------------------------------------------
create table public.sales_invoices (
  id bigint generated always as identity primary key,
  doc_no bigint not null unique,
  doc_date date not null,
  customer_id bigint not null references public.customers (id),
  total numeric(18, 2) not null check (total > 0),
  -- المقبوض عند الاعتماد (تاريخي، لا يتغير بسندات لاحقة)
  paid_amount numeric(18, 2) not null default 0,
  notes text,
  journal_entry_id bigint not null unique references public.journal_entries (id),
  receipt_voucher_id bigint unique references public.vouchers (id),
  created_at timestamptz not null default now(),
  constraint sales_invoices_paid_amount_range check (paid_amount >= 0 and paid_amount <= total),
  constraint sales_invoices_paid_has_voucher check ((paid_amount > 0) = (receipt_voucher_id is not null))
);

create index sales_invoices_doc_date_idx on public.sales_invoices (doc_date);
create index sales_invoices_customer_id_idx on public.sales_invoices (customer_id);

-- الصنف قد يتكرر في الفاتورة بوحدات مختلفة (مثل كراتين + قطع)، وتكلفة الصنف تُحسب مرة واحدة لكل
-- كميته الأساسية وتُوزَّع على سطوره. unit_cost = متوسط تكلفة الوحدة الأساسية وقت البيع، و cost_total
-- تكلفة السطر المحفوظة (ربح السطر = line_total − cost_total، ولا يُعاد حسابه بمتوسط اليوم).
create table public.sales_invoice_lines (
  id bigint generated always as identity primary key,
  invoice_id bigint not null references public.sales_invoices (id),
  item_id bigint not null references public.items (id),
  unit_id bigint,
  unit_name text not null check (btrim(unit_name) <> ''),
  factor numeric(18, 6) not null check (factor > 0),
  qty numeric(18, 3) not null check (qty > 0),
  base_qty numeric(18, 3) not null check (base_qty > 0),
  unit_price numeric(18, 2) not null check (unit_price >= 0),
  line_total numeric(18, 2) not null check (line_total > 0),
  unit_cost numeric(18, 4) not null check (unit_cost >= 0),
  cost_total numeric(18, 2) not null check (cost_total >= 0),
  constraint sales_invoice_lines_item_unit unique nulls not distinct (invoice_id, item_id, unit_id),
  constraint sales_invoice_lines_base_unit_factor check (unit_id is not null or factor = 1),
  constraint sales_invoice_lines_base_qty check (base_qty = qty * factor),
  constraint sales_invoice_lines_total check (line_total = round(qty * unit_price, 2)),
  constraint sales_invoice_lines_unit_fkey foreign key (unit_id, item_id) references public.item_units (id, item_id)
);

create index sales_invoice_lines_item_id_idx on public.sales_invoice_lines (item_id);
create index sales_invoice_lines_unit_id_idx on public.sales_invoice_lines (unit_id);

insert into public.doc_counters (kind, last_no) values ('sales_invoice', 0)
on conflict (kind) do nothing;

create trigger forbid_change before update or delete on public.sales_invoices
  for each row execute function private.forbid_document_change();
create trigger forbid_truncate before truncate on public.sales_invoices
  for each statement execute function private.forbid_document_change();
create trigger forbid_change before update or delete on public.sales_invoice_lines
  for each row execute function private.forbid_document_change();
create trigger forbid_truncate before truncate on public.sales_invoice_lines
  for each statement execute function private.forbid_document_change();

-- ---------------------------------------------------------------------
-- الصنف أو الوحدة مستخدمان: + فواتير المبيعات
-- ---------------------------------------------------------------------
create or replace function private.item_is_used(p_item_id bigint)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.stock_movements where item_id = p_item_id)
      or exists (select 1 from public.purchase_invoice_lines where item_id = p_item_id)
      or exists (select 1 from public.stock_adjustments where item_id = p_item_id)
      or exists (select 1 from public.formulas where finished_item_id = p_item_id)
      or exists (select 1 from public.formula_lines where item_id = p_item_id)
      or exists (select 1 from public.production_orders where finished_item_id = p_item_id)
      or exists (select 1 from public.production_lines where item_id = p_item_id)
      or exists (select 1 from public.sales_invoice_lines where item_id = p_item_id);
$$;

create or replace function private.unit_is_used(p_unit_id bigint)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.purchase_invoice_lines where unit_id = p_unit_id)
      or exists (select 1 from public.formulas where batch_unit_id = p_unit_id)
      or exists (select 1 from public.formula_lines where unit_id = p_unit_id)
      or exists (select 1 from public.production_orders where unit_id = p_unit_id)
      or exists (select 1 from public.production_lines where unit_id = p_unit_id)
      or exists (select 1 from public.sales_invoice_lines where unit_id = p_unit_id);
$$;

-- ---------------------------------------------------------------------
-- سطور القيود: إيرادات المبيعات وتكلفتها لا تُرحَّل بقيد يدوي أو تسوية (قرار صاحب المشروع)، فيطابق
-- تقرير أرباح الأصناف الحسابين. الأرصدة الافتتاحية مسموحة (بداية منتصف السنة). باقي القواعد كما هي.
-- ---------------------------------------------------------------------
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
  return new;
end;
$$;

-- حسابا إيرادات المبيعات وتكلفتها ثابتان بعد وجود قيود (مثل الأطراف والمخزون)، حتى يطابق تقرير أرباح
-- الأصناف الحسابين دائمًا
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
                     'sales_revenue', 'cogs')
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
        else 'مخزون المنتج التام'
      end;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- اعتماد فاتورة المبيعات (SPEC §6.1 و§6.2): م العملاء + العميل / د إيرادات المبيعات بالإجمالي، و
-- م تكلفة المبيعات / د مخزون المنتج التام بمتوسط التكلفة وقت البيع. والمقبوض الآن (صفر حتى الإجمالي)
-- بسند قبض مربوط في نفس الـ transaction. ترتيب الأقفال: الأصناف ← عدّاد الفواتير ← عدّاد سندات القبض
-- ← عدّاد القيود. الكمية الأساسية لكل صنف تُجمع من سطوره وتُصرف بحركة واحدة.
-- السطور: [{"item_id": 1, "unit_id": null, "qty": "150", "unit_price": "18"}]
-- ---------------------------------------------------------------------
create function public.post_sales_invoice(
  p_doc_date date,
  p_customer_id bigint,
  p_lines jsonb,
  p_notes text default null,
  p_received_amount text default null,
  p_received_treasury_account_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer text;
  v_line jsonb;
  v_no int := 0;
  v_item public.items;
  v_unit record;
  v_qty numeric;
  v_base numeric;
  v_price numeric;
  v_total numeric;
  v_keys text[] := '{}';
  v_key text;
  v_lock bigint[];
  v_parsed jsonb := '[]'::jsonb;
  v_need jsonb := '{}'::jsonb;
  v_order bigint[] := '{}';
  v_item_id bigint;
  v_item_base numeric;
  v_stock public.item_stock;
  v_cost numeric;
  v_costs jsonb := '{}'::jsonb;
  v_cum jsonb := '{}'::jsonb;
  v_prev numeric;
  v_next numeric;
  v_line_cost numeric;
  v_sum numeric := 0;
  v_cogs numeric := 0;
  v_received numeric;
  v_notes text := nullif(btrim(p_notes), '');
  v_id bigint;
  v_doc_no bigint;
  v_lines jsonb;
  v_entry_id bigint;
  v_voucher_id bigint;
  v_step jsonb;
begin
  perform private.require_staff();

  if p_doc_date is null then
    raise exception 'تاريخ الفاتورة مطلوب';
  end if;
  select name into v_customer from public.customers where id = p_customer_id and is_active;
  if not found then
    raise exception 'اختر عميلًا نشطًا';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'أضف صنفًا واحدًا على الأقل';
  end if;

  select coalesce(array_agg(distinct x), '{}') into v_lock
  from (select nullif(value ->> 'item_id', '')::bigint as x from jsonb_array_elements(p_lines)) s
  where x is not null;
  perform private.lock_items(v_lock);

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    select * into v_item from public.items where id = nullif(v_line ->> 'item_id', '')::bigint;
    if not found then
      raise exception 'السطر %: اختر الصنف', v_no;
    end if;
    if not v_item.is_active then
      raise exception 'السطر %: الصنف % معطّل', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.type <> 'finished_good' then
      raise exception 'السطر %: فاتورة المبيعات للمنتج التام فقط، والصنف % ليس منتجًا تامًا',
        v_no, v_item.code || ' - ' || v_item.name;
    end if;

    select * into v_unit
    from private.resolve_unit(v_item.id, nullif(v_line ->> 'unit_id', '')::bigint, 'السطر ' || v_no || ': ');
    v_key := v_item.id || ':' || coalesce(v_unit.unit_id::text, '');
    if v_key = any (v_keys) then
      raise exception 'السطر %: الصنف % بنفس الوحدة مكرر في الفاتورة', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    v_keys := v_keys || v_key;

    v_qty := private.to_qty(v_line ->> 'qty', 'السطر ' || v_no || ': ');
    v_price := private.parse_decimal(v_line ->> 'unit_price', 'السطر ' || v_no || ': سعر البيع', 2, 1e16);
    if v_price is null then
      raise exception 'السطر %: سعر البيع مطلوب', v_no;
    end if;
    v_base := private.to_base_qty(v_qty, v_unit.factor, 'السطر ' || v_no || ': ');
    v_total := round(v_qty * v_price, 2);
    if v_total <= 0 then
      raise exception 'السطر %: إجمالي السطر يجب أن يكون أكبر من صفر', v_no;
    end if;
    if v_total >= 1e16 then
      raise exception 'السطر %: إجمالي السطر أكبر من الحد المسموح', v_no;
    end if;
    v_sum := v_sum + v_total;

    v_parsed := v_parsed || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'unit_id', v_unit.unit_id, 'unit_name', v_unit.unit_name, 'factor', v_unit.factor,
      'qty', v_qty, 'base_qty', v_base, 'unit_price', v_price, 'total', v_total));
    if not (v_item.id = any (v_order)) then
      v_order := v_order || v_item.id;
    end if;
    v_need := jsonb_set(v_need, array[v_item.id::text],
      to_jsonb(coalesce((v_need ->> v_item.id::text)::numeric, 0) + v_base));
  end loop;
  if v_sum >= 1e16 then
    raise exception 'إجمالي الفاتورة أكبر من الحد المسموح';
  end if;

  -- الرصيد يكفي لكل صنف (كل وحداته معًا)، ثم تكلفته بمتوسط التكلفة الآن
  foreach v_item_id in array v_order loop
    v_item_base := (v_need ->> v_item_id::text)::numeric;
    select * into v_stock from public.item_stock where item_id = v_item_id;
    if v_item_base > v_stock.qty then
      select * into v_item from public.items where id = v_item_id;
      raise exception 'الكمية المطلوبة من الصنف % هي % % والمتاح % % فقط (النقص %)',
        v_item.code || ' - ' || v_item.name, trim_scale(v_item_base), v_item.unit,
        trim_scale(v_stock.qty), v_item.unit, trim_scale(v_item_base - v_stock.qty);
    end if;
    v_cost := private.issue_cost(v_item_id, v_item_base);
    v_costs := jsonb_set(v_costs, array[v_item_id::text], to_jsonb(v_cost));
    v_cogs := v_cogs + v_cost;
  end loop;

  -- المقبوض الآن: صفر (آجل بالكامل، الافتراضي) حتى إجمالي الفاتورة، ولا يزيد عنه أبدًا
  v_received := private.to_amount(p_received_amount, 'المقبوض الآن: ');
  if v_received > v_sum then
    raise exception 'المقبوض الآن % أكبر من إجمالي الفاتورة %',
      private.fmt_amount(v_received), private.fmt_amount(v_sum);
  end if;
  if v_received > 0 and p_received_treasury_account_id is null then
    raise exception 'اختر الخزينة أو البنك المقبوض فيه';
  end if;

  v_id := nextval(pg_get_serial_sequence('public.sales_invoices', 'id'));
  v_doc_no := private.next_doc_no('sales_invoice');
  if v_received > 0 then
    perform 1 from public.doc_counters where kind = 'receipt_voucher' for update;
  end if;

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', (select account_id from public.system_accounts where key = 'receivables'),
      'debit', v_sum::text, 'credit', '0', 'customer_id', p_customer_id),
    jsonb_build_object(
      'account_id', (select account_id from public.system_accounts where key = 'sales_revenue'),
      'debit', '0', 'credit', v_sum::text));
  if v_cogs > 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object(
        'account_id', (select account_id from public.system_accounts where key = 'cogs'),
        'debit', v_cogs::text, 'credit', '0', 'description', 'تكلفة المبيعات'),
      jsonb_build_object(
        'account_id', private.inventory_account('finished_good'),
        'debit', '0', 'credit', v_cogs::text, 'description', 'تكلفة المبيعات'));
  end if;

  v_entry_id := private.post_entry(
    p_doc_date,
    'فاتورة مبيعات رقم ' || v_doc_no || ' - العميل ' || v_customer || coalesce(' - ' || v_notes, ''),
    'sale',
    v_lines,
    v_id
  );

  -- سند القبض بالمبلغ المقبوض فقط: م الخزينة أو البنك / د العملاء + العميل
  if v_received > 0 then
    v_voucher_id := private.create_voucher(
      'receipt', p_doc_date, p_received_treasury_account_id, 'customer', p_customer_id, v_received::text,
      case when v_received = v_sum then 'تحصيل فاتورة مبيعات رقم ' else 'تحصيل جزئي لفاتورة مبيعات رقم ' end
        || v_doc_no
    );
  end if;

  insert into public.sales_invoices (
    id, doc_no, doc_date, customer_id, total, paid_amount, notes, journal_entry_id, receipt_voucher_id
  )
  overriding system value
  values (v_id, v_doc_no, p_doc_date, p_customer_id, v_sum, v_received, v_notes, v_entry_id, v_voucher_id);

  -- تكلفة الصنف تُوزَّع على سطوره بالتراكم (كل سطر = التكلفة حتى نهايته − التكلفة قبله، مقربة للقرش)،
  -- فلا يكون سطر سالبًا ومجموع السطور = تكلفة الصنف بالضبط
  for v_step in select value from jsonb_array_elements(v_parsed) loop
    v_item_id := (v_step ->> 'item_id')::bigint;
    v_item_base := (v_need ->> v_item_id::text)::numeric;
    v_cost := (v_costs ->> v_item_id::text)::numeric;
    v_prev := coalesce((v_cum ->> v_item_id::text)::numeric, 0);
    v_next := v_prev + (v_step ->> 'base_qty')::numeric;
    v_cum := jsonb_set(v_cum, array[v_item_id::text], to_jsonb(v_next));
    v_line_cost := round(v_cost * v_next / v_item_base, 2) - round(v_cost * v_prev / v_item_base, 2);

    insert into public.sales_invoice_lines (
      invoice_id, item_id, unit_id, unit_name, factor, qty, base_qty, unit_price, line_total, unit_cost, cost_total
    )
    values (
      v_id, v_item_id, nullif(v_step ->> 'unit_id', '')::bigint, v_step ->> 'unit_name',
      (v_step ->> 'factor')::numeric, (v_step ->> 'qty')::numeric, (v_step ->> 'base_qty')::numeric,
      (v_step ->> 'unit_price')::numeric, (v_step ->> 'total')::numeric,
      round(v_cost / v_item_base, 4), v_line_cost
    );
  end loop;

  foreach v_item_id in array v_order loop
    perform private.stock_out(
      v_item_id, (v_need ->> v_item_id::text)::numeric, (v_costs ->> v_item_id::text)::numeric,
      p_doc_date, 'sale', 'sale', v_id, v_entry_id
    );
  end loop;

  return v_id;
end;
$$;

-- إلغاء فاتورة المبيعات: قيد عكسي + المنتج يرجع للمخزون بتكلفته الأصلية. سند القبض لا يُلغى معها: المبلغ
-- يبقى رصيدًا دائنًا للعميل (دفعة مقدمة) حتى يُلغى السند من صفحته لو لم يُقبض فعلًا.
create function public.cancel_sales_invoice(p_invoice_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invoice public.sales_invoices;
begin
  perform private.require_staff();

  select * into v_invoice from public.sales_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'الفاتورة غير موجودة';
  end if;
  if exists (select 1 from public.journal_entries where reverses_entry_id = v_invoice.journal_entry_id) then
    raise exception 'فاتورة المبيعات رقم % ملغاة بالفعل', v_invoice.doc_no;
  end if;

  return private.reverse_document_stock(
    v_invoice.journal_entry_id, 'إلغاء فاتورة المبيعات رقم ' || v_invoice.doc_no
  );
end;
$$;

-- ---------------------------------------------------------------------
-- دوال القراءة
-- ---------------------------------------------------------------------

-- قائمة فواتير المبيعات: الإجمالي والمقبوض عند الاعتماد والتكلفة ومجمل الربح (ملغاة = لقيدها قيد عكسي)
create function public.sales_invoice_list(
  p_from date default null,
  p_to date default null,
  p_search text default null
)
returns table (
  id bigint,
  doc_no bigint,
  doc_date date,
  customer_id bigint,
  customer_name text,
  total text,
  paid_amount text,
  cost_total text,
  gross_profit text,
  notes text,
  journal_entry_id bigint,
  receipt_voucher_id bigint,
  is_cancelled boolean
)
language sql
stable
set search_path = ''
as $$
  select s.id, s.doc_no, s.doc_date, c.id, c.name, s.total::text, s.paid_amount::text, l.cost::text,
         (s.total - l.cost)::text, s.notes, s.journal_entry_id, s.receipt_voucher_id,
         exists (select 1 from public.journal_entries r where r.reverses_entry_id = s.journal_entry_id)
  from public.sales_invoices s
  join public.customers c on c.id = s.customer_id
  cross join lateral (
    select coalesce(sum(cost_total), 0) as cost from public.sales_invoice_lines where invoice_id = s.id
  ) l
  where (p_from is null or s.doc_date >= p_from)
    and (p_to is null or s.doc_date <= p_to)
    and (
      coalesce(btrim(p_search), '') = ''
      or s.doc_no::text = btrim(p_search)
      or c.name ilike '%' || btrim(p_search) || '%'
      or s.notes ilike '%' || btrim(p_search) || '%'
    )
  order by s.doc_date desc, s.doc_no desc;
$$;

-- تقرير أرباح الأصناف (SPEC §8): من سطور الفواتير غير الملغاة فقط، بالتكلفة المحفوظة وقت البيع.
-- الكمية بالوحدة الأساسية، والهامش = الربح ÷ المبيعات × 100. مجموع الربح = إيرادات المبيعات − تكلفتها.
create function public.item_profit(
  p_from date default null,
  p_to date default null,
  p_item_id bigint default null,
  p_customer_id bigint default null
)
returns table (
  item_id bigint,
  item_code text,
  item_name text,
  base_unit text,
  qty text,
  sales text,
  cost text,
  profit text,
  margin text,
  invoices bigint
)
language sql
stable
set search_path = ''
as $$
  select i.id, i.code, i.name, i.unit, sum(l.base_qty)::text, sum(l.line_total)::text, sum(l.cost_total)::text,
         (sum(l.line_total) - sum(l.cost_total))::text,
         round((sum(l.line_total) - sum(l.cost_total)) * 100 / sum(l.line_total), 2)::text,
         count(distinct s.id)
  from public.sales_invoice_lines l
  join public.sales_invoices s on s.id = l.invoice_id
  join public.items i on i.id = l.item_id
  where not exists (select 1 from public.journal_entries r where r.reverses_entry_id = s.journal_entry_id)
    and (p_from is null or s.doc_date >= p_from)
    and (p_to is null or s.doc_date <= p_to)
    and (p_item_id is null or l.item_id = p_item_id)
    and (p_customer_id is null or s.customer_id = p_customer_id)
  group by i.id, i.code, i.name, i.unit
  order by sum(l.line_total) - sum(l.cost_total) desc, i.code;
$$;

-- سطور الفواتير التي بيع فيها صنف (للضغط على الصنف في تقرير الأرباح)
create function public.item_profit_lines(
  p_item_id bigint,
  p_from date default null,
  p_to date default null,
  p_customer_id bigint default null
)
returns table (
  invoice_id bigint,
  doc_no bigint,
  doc_date date,
  customer_name text,
  unit_name text,
  qty text,
  base_qty text,
  unit_price text,
  line_total text,
  cost_total text,
  profit text
)
language sql
stable
set search_path = ''
as $$
  select s.id, s.doc_no, s.doc_date, c.name, l.unit_name, l.qty::text, l.base_qty::text, l.unit_price::text,
         l.line_total::text, l.cost_total::text, (l.line_total - l.cost_total)::text
  from public.sales_invoice_lines l
  join public.sales_invoices s on s.id = l.invoice_id
  join public.customers c on c.id = s.customer_id
  where l.item_id = p_item_id
    and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = s.journal_entry_id)
    and (p_from is null or s.doc_date >= p_from)
    and (p_to is null or s.doc_date <= p_to)
    and (p_customer_id is null or s.customer_id = p_customer_id)
  order by s.doc_date desc, s.doc_no desc, l.id;
$$;

-- حركة صنف: رقم المستند لفواتير المبيعات أيضًا (نفس التوقيع والأعمدة)
create or replace function public.item_movements(
  p_item_id bigint,
  p_from date default null,
  p_to date default null
)
returns table (
  movement_id bigint,
  movement_date date,
  kind text,
  source_type text,
  source_id bigint,
  doc_no bigint,
  journal_entry_id bigint,
  qty_in text,
  qty_out text,
  unit_cost text,
  total_cost text,
  balance_qty text,
  balance_value text
)
language sql
stable
set search_path = ''
as $$
  with moves as (
    select m.*,
           m.qty_in - m.qty_out as signed_qty,
           case when m.qty_in > 0 then m.total_cost else -m.total_cost end as signed_value
    from public.stock_movements m
    where m.item_id = p_item_id
  ),
  opening as (
    select coalesce(sum(signed_qty), 0) as qty, coalesce(sum(signed_value), 0) as value
    from moves
    where p_from is not null and movement_date < p_from
  ),
  report as (
    select 0 as grp, null::bigint as id, p_from as movement_date, null::text as kind,
           null::text as source_type, null::bigint as source_id, null::bigint as journal_entry_id,
           null::numeric as qty_in, null::numeric as qty_out, null::numeric as unit_cost,
           null::numeric as total_cost,
           (select qty from opening) as balance_qty, (select value from opening) as balance_value
    union all
    select 1, id, movement_date, kind, source_type, source_id, journal_entry_id,
           qty_in, qty_out, unit_cost, total_cost,
           (select qty from opening) + sum(signed_qty) over (order by movement_date, id),
           (select value from opening) + sum(signed_value) over (order by movement_date, id)
    from moves
    where (p_from is null or movement_date >= p_from)
      and (p_to is null or movement_date <= p_to)
  )
  select r.id, r.movement_date, r.kind, r.source_type, r.source_id,
         case r.source_type
           when 'purchase' then (select doc_no from public.purchase_invoices where id = r.source_id)
           when 'stock_adjustment' then (select doc_no from public.stock_adjustments where id = r.source_id)
           when 'production' then (select doc_no from public.production_orders where id = r.source_id)
           when 'sale' then (select doc_no from public.sales_invoices where id = r.source_id)
         end,
         r.journal_entry_id,
         round(r.qty_in, 3)::text, round(r.qty_out, 3)::text, round(r.unit_cost, 4)::text,
         round(r.total_cost, 2)::text, round(r.balance_qty, 3)::text, round(r.balance_value, 2)::text
  from report r
  order by r.grp, r.movement_date, r.id;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات و RLS: الفواتير قراءة فقط للمستخدم، والكتابة عبر الدوال
-- ---------------------------------------------------------------------
revoke execute on function
  public.post_sales_invoice(date, bigint, jsonb, text, text, bigint),
  public.cancel_sales_invoice(bigint),
  public.sales_invoice_list(date, date, text),
  public.item_profit(date, date, bigint, bigint),
  public.item_profit_lines(bigint, date, date, bigint)
from public, anon;

grant execute on function
  public.post_sales_invoice(date, bigint, jsonb, text, text, bigint),
  public.cancel_sales_invoice(bigint),
  public.sales_invoice_list(date, date, text),
  public.item_profit(date, date, bigint, bigint),
  public.item_profit_lines(bigint, date, date, bigint)
to authenticated;

alter table public.sales_invoices enable row level security;
alter table public.sales_invoice_lines enable row level security;

revoke all on public.sales_invoices, public.sales_invoice_lines from anon, authenticated;
revoke all on sequence public.sales_invoices_id_seq, public.sales_invoice_lines_id_seq from anon, authenticated;

grant select on public.sales_invoices, public.sales_invoice_lines to authenticated;

create policy sales_invoices_select on public.sales_invoices for select to authenticated using (true);
create policy sales_invoice_lines_select on public.sales_invoice_lines for select to authenticated using (true);
