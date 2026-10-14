-- =====================================================================
-- المرحلة 4: الأصناف والمخزون والمشتريات
-- الأصناف، رصيد الصنف بمتوسط التكلفة المرجح المتحرك، حركات المخزون، فواتير المشتريات،
-- تسوية الجرد، مخزون أول المدة (الجزء الثالث من الأرصدة الافتتاحية).
-- كل مستند يعتمد قيده وحركاته في نفس الـ transaction، ومطابقة المخزون مع الأستاذ تُفحص عند الـ commit.
-- =====================================================================

-- ---------------------------------------------------------------------
-- items / item_stock / stock_movements
-- ---------------------------------------------------------------------
create table public.items (
  id bigint generated always as identity primary key,
  code text not null unique check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  type text not null check (type in ('raw_material', 'packaging', 'finished_good')),
  unit text not null check (btrim(unit) <> ''),
  sale_price numeric(18, 2) check (sale_price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- رصيد الصنف: القيمة هي الأساس (تطابق الأستاذ بالقرش)، والمتوسط = القيمة ÷ الكمية (آخر متوسط عند الصفر)
create table public.item_stock (
  item_id bigint primary key references public.items (id) on delete cascade,
  qty numeric(18, 3) not null default 0 check (qty >= 0),
  value numeric(18, 2) not null default 0 check (value >= 0),
  avg_cost numeric(18, 4) not null default 0 check (avg_cost >= 0),
  constraint item_stock_zero_qty_zero_value check (qty > 0 or value = 0)
);

create table public.stock_movements (
  id bigint generated always as identity primary key,
  item_id bigint not null references public.items (id),
  movement_date date not null,
  kind text not null check (kind in ('opening', 'purchase', 'production', 'sale', 'stock_adjustment', 'reversal')),
  qty_in numeric(18, 3) not null default 0 check (qty_in >= 0),
  qty_out numeric(18, 3) not null default 0 check (qty_out >= 0),
  unit_cost numeric(18, 4) not null default 0 check (unit_cost >= 0),
  total_cost numeric(18, 2) not null default 0 check (total_cost >= 0),
  source_type text not null check (source_type in ('opening', 'purchase', 'production', 'sale', 'stock_adjustment')),
  source_id bigint,
  journal_entry_id bigint not null references public.journal_entries (id),
  reverses_movement_id bigint unique references public.stock_movements (id),
  created_at timestamptz not null default now(),
  constraint stock_movements_one_side check ((qty_in > 0) <> (qty_out > 0))
);

create index stock_movements_item_id_idx on public.stock_movements (item_id);
create index stock_movements_journal_entry_id_idx on public.stock_movements (journal_entry_id);
create index stock_movements_source_idx on public.stock_movements (source_type, source_id);

-- ---------------------------------------------------------------------
-- فواتير المشتريات وتسوية الجرد (ثابتة بعد الاعتماد، و«ملغى» = لقيدها قيد عكسي)
-- ---------------------------------------------------------------------
create table public.purchase_invoices (
  id bigint generated always as identity primary key,
  doc_no bigint not null unique,
  doc_date date not null,
  supplier_id bigint not null references public.suppliers (id),
  total numeric(18, 2) not null check (total > 0),
  notes text,
  journal_entry_id bigint not null unique references public.journal_entries (id),
  payment_voucher_id bigint unique references public.vouchers (id),
  created_at timestamptz not null default now()
);

create index purchase_invoices_doc_date_idx on public.purchase_invoices (doc_date);
create index purchase_invoices_supplier_id_idx on public.purchase_invoices (supplier_id);

create table public.purchase_invoice_lines (
  id bigint generated always as identity primary key,
  invoice_id bigint not null references public.purchase_invoices (id),
  item_id bigint not null references public.items (id),
  qty numeric(18, 3) not null check (qty > 0),
  unit_price numeric(18, 4) not null check (unit_price >= 0),
  line_total numeric(18, 2) not null check (line_total > 0),
  unique (invoice_id, item_id)
);

create index purchase_invoice_lines_item_id_idx on public.purchase_invoice_lines (item_id);

create table public.stock_adjustments (
  id bigint generated always as identity primary key,
  doc_no bigint not null unique,
  doc_date date not null,
  item_id bigint not null references public.items (id),
  system_qty numeric(18, 3) not null check (system_qty >= 0),
  counted_qty numeric(18, 3) not null check (counted_qty >= 0),
  unit_cost numeric(18, 4) not null check (unit_cost >= 0),
  total_cost numeric(18, 2) not null check (total_cost > 0),
  notes text,
  journal_entry_id bigint not null unique references public.journal_entries (id),
  created_at timestamptz not null default now(),
  constraint stock_adjustments_has_difference check (counted_qty <> system_qty)
);

create index stock_adjustments_doc_date_idx on public.stock_adjustments (doc_date);
create index stock_adjustments_item_id_idx on public.stock_adjustments (item_id);

insert into public.doc_counters (kind, last_no)
values ('purchase_invoice', 0), ('stock_adjustment', 0);

-- المستندات وحركات المخزون لا تُعدَّل ولا تُحذف (القاعدة 3)
create trigger forbid_change before update or delete on public.stock_movements
  for each row execute function private.forbid_document_change();
create trigger forbid_truncate before truncate on public.stock_movements
  for each statement execute function private.forbid_document_change();
create trigger forbid_change before update or delete on public.purchase_invoices
  for each row execute function private.forbid_document_change();
create trigger forbid_truncate before truncate on public.purchase_invoices
  for each statement execute function private.forbid_document_change();
create trigger forbid_change before update or delete on public.purchase_invoice_lines
  for each row execute function private.forbid_document_change();
create trigger forbid_truncate before truncate on public.purchase_invoice_lines
  for each statement execute function private.forbid_document_change();
create trigger forbid_change before update or delete on public.stock_adjustments
  for each row execute function private.forbid_document_change();
create trigger forbid_truncate before truncate on public.stock_adjustments
  for each statement execute function private.forbid_document_change();

-- ---------------------------------------------------------------------
-- الأصناف: صف رصيد لكل صنف، والنوع ثابت بعد وجود حركات أو مستندات
-- ---------------------------------------------------------------------
create function private.create_item_stock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.item_stock (item_id) values (new.id);
  return null;
end;
$$;

create trigger create_item_stock
  after insert on public.items
  for each row execute function private.create_item_stock();

create function private.validate_item()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.type <> old.type and (
    exists (select 1 from public.stock_movements where item_id = old.id)
    or exists (select 1 from public.purchase_invoice_lines where item_id = old.id)
    or exists (select 1 from public.stock_adjustments where item_id = old.id)
  ) then
    raise exception 'لا يمكن تغيير نوع صنف عليه حركات أو مستندات';
  end if;
  return new;
end;
$$;

create trigger validate_item
  before update on public.items
  for each row execute function private.validate_item();

-- ---------------------------------------------------------------------
-- تحقق مؤجل حتى الـ commit (يسري على أي طريق كتابة)
-- ---------------------------------------------------------------------

-- حساب المخزون لنوع الصنف
create function private.inventory_account(p_item_type text)
returns bigint
language sql
stable
set search_path = ''
as $$
  select account_id from public.system_accounts
  where key = case p_item_type
    when 'raw_material' then 'inventory_raw'
    when 'packaging' then 'inventory_packaging'
    else 'inventory_finished'
  end;
$$;

-- القاعدة 10: رصيد الصنف = مجموع حركاته (كمية وقيمة).
-- التحقق المؤجل يعمل عند الـ commit بصلاحية المستخدم نفسه، فالدالة security definer (قراءة فقط).
create function private.check_item_stock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stock public.item_stock;
  v_qty numeric;
  v_value numeric;
  v_label text;
begin
  select * into v_stock from public.item_stock where item_id = new.item_id;
  select coalesce(sum(qty_in - qty_out), 0),
         coalesce(sum(case when qty_in > 0 then total_cost else -total_cost end), 0)
    into v_qty, v_value
  from public.stock_movements
  where item_id = new.item_id;

  if v_stock.qty is distinct from v_qty or v_stock.value is distinct from v_value then
    select code || ' - ' || name into v_label from public.items where id = new.item_id;
    raise exception 'رصيد الصنف % لا يطابق مجموع حركاته (الرصيد % بقيمة %، والحركات % بقيمة %)',
      v_label, v_stock.qty, private.fmt_amount(v_stock.value), v_qty, private.fmt_amount(v_value);
  end if;
  return null;
end;
$$;

create constraint trigger stock_movements_match_stock
  after insert on public.stock_movements
  deferrable initially deferred
  for each row execute function private.check_item_stock();

create constraint trigger item_stock_matches_movements
  after update on public.item_stock
  deferrable initially deferred
  for each row execute function private.check_item_stock();

-- كل قيد: صافي سطوره على كل حساب مخزون = قيمة حركات أصناف ذلك الحساب في نفس القيد
create function private.check_entry_inventory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry_id bigint;
  v_account text;
begin
  if tg_table_name = 'journal_lines' then
    if not private.account_keys(new.account_id)
           && array['inventory_raw', 'inventory_packaging', 'inventory_finished'] then
      return null;
    end if;
    v_entry_id := new.entry_id;
  else
    v_entry_id := new.journal_entry_id;
  end if;

  with inv as (
    select s.account_id,
           case s.key
             when 'inventory_raw' then 'raw_material'
             when 'inventory_packaging' then 'packaging'
             else 'finished_good'
           end as item_type
    from public.system_accounts s
    where s.key in ('inventory_raw', 'inventory_packaging', 'inventory_finished')
  ),
  line_totals as (
    select l.account_id, sum(l.debit - l.credit) as amount
    from public.journal_lines l
    where l.entry_id = v_entry_id and l.account_id in (select account_id from inv)
    group by l.account_id
  ),
  movement_totals as (
    select inv.account_id,
           sum(case when m.qty_in > 0 then m.total_cost else -m.total_cost end) as amount
    from public.stock_movements m
    join public.items i on i.id = m.item_id
    join inv on inv.item_type = i.type
    where m.journal_entry_id = v_entry_id
    group by inv.account_id
  )
  select a.code || ' - ' || a.name into v_account
  from (select distinct account_id from inv) x
  join public.accounts a on a.id = x.account_id
  left join line_totals lt on lt.account_id = x.account_id
  left join movement_totals mt on mt.account_id = x.account_id
  where coalesce(lt.amount, 0) <> coalesce(mt.amount, 0)
  limit 1;

  if found then
    raise exception 'قيد المخزون لا يطابق حركات المخزون على حساب % (القيد رقم %)',
      v_account, (select entry_no from public.journal_entries where id = v_entry_id);
  end if;
  return null;
end;
$$;

create constraint trigger journal_lines_match_stock
  after insert on public.journal_lines
  deferrable initially deferred
  for each row execute function private.check_entry_inventory();

create constraint trigger stock_movements_match_entry
  after insert on public.stock_movements
  deferrable initially deferred
  for each row execute function private.check_entry_inventory();

-- ---------------------------------------------------------------------
-- تحويل الكميات والأسعار من نص: بلا تقريب صامت
-- ---------------------------------------------------------------------
create function private.to_qty(p_value text, p_context text, p_allow_zero boolean default false)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v numeric;
begin
  if p_value is null or btrim(p_value) = '' then
    raise exception '%الكمية مطلوبة', p_context;
  end if;
  begin
    v := btrim(p_value)::numeric;
  exception when invalid_text_representation then
    raise exception '%الكمية "%" غير صالحة', p_context, p_value;
  end;
  if v = 'NaN'::numeric or v < 0 or (v = 0 and not p_allow_zero) then
    if p_allow_zero then
      raise exception '%الكمية يجب أن تكون صفرًا أو أكثر', p_context;
    end if;
    raise exception '%الكمية يجب أن تكون أكبر من صفر', p_context;
  end if;
  if v >= 1e15 then
    raise exception '%الكمية أكبر من الحد المسموح', p_context;
  end if;
  if scale(trim_scale(v)) > 3 then
    raise exception '%الكمية لا تزيد عن ثلاث خانات عشرية', p_context;
  end if;
  return v;
end;
$$;

create function private.to_unit_price(p_value text, p_context text)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v numeric;
begin
  if p_value is null or btrim(p_value) = '' then
    raise exception '%سعر الوحدة مطلوب', p_context;
  end if;
  begin
    v := btrim(p_value)::numeric;
  exception when invalid_text_representation then
    raise exception '%سعر الوحدة "%" غير صالح', p_context, p_value;
  end;
  if v = 'NaN'::numeric or v < 0 then
    raise exception '%سعر الوحدة يجب أن يكون رقمًا موجبًا', p_context;
  end if;
  if v >= 1e14 then
    raise exception '%سعر الوحدة أكبر من الحد المسموح', p_context;
  end if;
  if scale(trim_scale(v)) > 4 then
    raise exception '%سعر الوحدة لا يزيد عن أربع خانات عشرية', p_context;
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- حركات المخزون بمتوسط التكلفة المرجح المتحرك (القاعدة 5)
-- ---------------------------------------------------------------------

-- قفل صفوف أرصدة الأصناف بترتيب ثابت (يمنع الـ deadlock)
create function private.lock_items(p_item_ids bigint[])
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform 1 from public.item_stock
  where item_id = any (p_item_ids)
  order by item_id
  for update;
end;
$$;

-- اسم الصنف للرسائل
create function private.item_label(p_item_id bigint)
returns text
language sql
stable
set search_path = ''
as $$
  select code || ' - ' || name from public.items where id = p_item_id;
$$;

-- تكلفة صرف كمية بالمتوسط الحالي (الصف مقفول من المستدعي). لا يتجاوز القيمة المتبقية أبدًا،
-- وصرف كل الكمية يأخذ القيمة كلها (بلا قروش متبقية). الرصيد السالب ممنوع.
create function private.issue_cost(p_item_id bigint, p_qty numeric)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  v_stock public.item_stock;
begin
  select * into v_stock from public.item_stock where item_id = p_item_id;
  if p_qty > v_stock.qty then
    raise exception 'الكمية المتاحة من الصنف % هي % فقط', private.item_label(p_item_id), trim_scale(v_stock.qty);
  end if;
  if p_qty = v_stock.qty then
    return v_stock.value;
  end if;
  return round(p_qty * v_stock.value / v_stock.qty, 2);
end;
$$;

-- إضافة للمخزون: المتوسط الجديد = إجمالي القيمة ÷ إجمالي الكمية
create function private.stock_in(
  p_item_id bigint,
  p_qty numeric,
  p_total numeric,
  p_date date,
  p_kind text,
  p_source_type text,
  p_source_id bigint,
  p_entry_id bigint,
  p_reverses_movement_id bigint default null
)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_stock public.item_stock;
  v_id bigint;
begin
  select * into v_stock from public.item_stock where item_id = p_item_id for update;
  update public.item_stock
  set qty = v_stock.qty + p_qty,
      value = v_stock.value + p_total,
      avg_cost = round((v_stock.value + p_total) / (v_stock.qty + p_qty), 4)
  where item_id = p_item_id;

  insert into public.stock_movements (
    item_id, movement_date, kind, qty_in, unit_cost, total_cost,
    source_type, source_id, journal_entry_id, reverses_movement_id
  )
  values (
    p_item_id, p_date, p_kind, p_qty, round(p_total / p_qty, 4), p_total,
    p_source_type, p_source_id, p_entry_id, p_reverses_movement_id
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- صرف من المخزون بتكلفة محسوبة مسبقًا (issue_cost أو تكلفة الإلغاء). المتوسط لا يتغير،
-- وعند الصفر يبقى آخر متوسط معروف.
create function private.stock_out(
  p_item_id bigint,
  p_qty numeric,
  p_total numeric,
  p_date date,
  p_kind text,
  p_source_type text,
  p_source_id bigint,
  p_entry_id bigint,
  p_reverses_movement_id bigint default null
)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_stock public.item_stock;
  v_id bigint;
begin
  select * into v_stock from public.item_stock where item_id = p_item_id for update;
  if p_qty > v_stock.qty then
    raise exception 'الكمية المتاحة من الصنف % هي % فقط', private.item_label(p_item_id), trim_scale(v_stock.qty);
  end if;
  update public.item_stock
  set qty = v_stock.qty - p_qty,
      value = v_stock.value - p_total,
      avg_cost = case
        when v_stock.qty - p_qty > 0 then round((v_stock.value - p_total) / (v_stock.qty - p_qty), 4)
        else v_stock.avg_cost
      end
  where item_id = p_item_id;

  insert into public.stock_movements (
    item_id, movement_date, kind, qty_out, unit_cost, total_cost,
    source_type, source_id, journal_entry_id, reverses_movement_id
  )
  values (
    p_item_id, p_date, p_kind, p_qty, round(p_total / p_qty, 4), p_total,
    p_source_type, p_source_id, p_entry_id, p_reverses_movement_id
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- قيد عكسي بسطور إضافية (فرق تكلفة الإلغاء). النسخة القديمة بمعاملين تستدعي هذه.
create function private.reverse_entry(p_entry_id bigint, p_description text, p_extra_lines jsonb)
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

  return private.post_entry(
    v_entry.entry_date, p_description, 'reversal',
    v_lines || coalesce(p_extra_lines, '[]'::jsonb), null, p_entry_id
  );
end;
$$;

create or replace function private.reverse_entry(p_entry_id bigint, p_description text)
returns bigint
language plpgsql
set search_path = ''
as $$
begin
  return private.reverse_entry(p_entry_id, p_description, '[]'::jsonb);
end;
$$;

-- إلغاء مستند مخزون: قيد عكسي + حركات عكسية بنفس التكلفة (القاعدة 3).
-- عكس حركة إضافة يُخرج تكلفتها الأصلية، إلا لو كانت الكمية ستصير صفرًا أو القيمة ستصير سالبة
-- فيُخرج القيمة المتبقية بالضبط، والفرق يُسجَّل على فروقات الجرد (5201) في نفس القيد العكسي.
-- عكس حركة صرف يعيد الكمية بتكلفتها الأصلية. الرصيد السالب ممنوع.
create function private.reverse_document_stock(p_entry_id bigint, p_description text)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_items bigint[];
  v_mov public.stock_movements;
  v_stock public.item_stock;
  v_type text;
  v_out numeric;
  v_residual numeric;
  v_plan jsonb := '[]'::jsonb;
  v_residuals jsonb := '{}'::jsonb;
  v_extra jsonb := '[]'::jsonb;
  v_adjustment_account bigint := (select account_id from public.system_accounts where key = 'inventory_adjustment');
  v_key text;
  v_amount numeric;
  v_step jsonb;
  v_reversal_id bigint;
begin
  select array_agg(distinct item_id order by item_id) into v_items
  from public.stock_movements where journal_entry_id = p_entry_id;
  if (select count(*) from public.stock_movements where journal_entry_id = p_entry_id)
     <> coalesce(cardinality(v_items), 0) then
    raise exception 'المستند فيه أكثر من حركة لنفس الصنف';
  end if;
  perform private.lock_items(coalesce(v_items, '{}'));

  for v_mov in
    select * from public.stock_movements where journal_entry_id = p_entry_id order by item_id
  loop
    select * into v_stock from public.item_stock where item_id = v_mov.item_id;
    select type into v_type from public.items where id = v_mov.item_id;

    if v_mov.qty_in > 0 then
      if v_mov.qty_in > v_stock.qty then
        raise exception 'لا يمكن الإلغاء: المتبقي من الصنف % هو % فقط، وكمية المستند %',
          private.item_label(v_mov.item_id), trim_scale(v_stock.qty), trim_scale(v_mov.qty_in);
      end if;
      v_out := case
        when v_mov.qty_in = v_stock.qty or v_mov.total_cost > v_stock.value then v_stock.value
        else v_mov.total_cost
      end;
      v_residual := v_mov.total_cost - v_out;
      if v_residual <> 0 then
        v_key := private.inventory_account(v_type)::text;
        v_residuals := jsonb_set(v_residuals, array[v_key],
          to_jsonb(coalesce((v_residuals ->> v_key)::numeric, 0) + v_residual));
      end if;
      v_plan := v_plan || jsonb_build_array(jsonb_build_object(
        'dir', 'out', 'movement_id', v_mov.id, 'item_id', v_mov.item_id,
        'qty', v_mov.qty_in, 'total', v_out, 'source_type', v_mov.source_type, 'source_id', v_mov.source_id));
    else
      v_plan := v_plan || jsonb_build_array(jsonb_build_object(
        'dir', 'in', 'movement_id', v_mov.id, 'item_id', v_mov.item_id,
        'qty', v_mov.qty_out, 'total', v_mov.total_cost, 'source_type', v_mov.source_type, 'source_id', v_mov.source_id));
    end if;
  end loop;

  -- فرق التكلفة: موجب = أُخرج من المخزون أقل من تكلفة المستند (م المخزون / د فروقات الجرد)، سالب = العكس
  for v_key, v_amount in select key, value::numeric from jsonb_each_text(v_residuals) loop
    if v_amount <> 0 then
      v_extra := v_extra || jsonb_build_array(
        jsonb_build_object('account_id', v_key::bigint,
          'debit', case when v_amount > 0 then v_amount::text else '0' end,
          'credit', case when v_amount < 0 then (-v_amount)::text else '0' end,
          'description', 'فرق تكلفة الإلغاء (المخزون المتبقي بمتوسط مختلف)'),
        jsonb_build_object('account_id', v_adjustment_account,
          'debit', case when v_amount < 0 then (-v_amount)::text else '0' end,
          'credit', case when v_amount > 0 then v_amount::text else '0' end,
          'description', 'فرق تكلفة الإلغاء (المخزون المتبقي بمتوسط مختلف)'));
    end if;
  end loop;

  v_reversal_id := private.reverse_entry(p_entry_id, p_description, v_extra);

  for v_step in select value from jsonb_array_elements(v_plan) loop
    if v_step ->> 'dir' = 'out' then
      perform private.stock_out(
        (v_step ->> 'item_id')::bigint, (v_step ->> 'qty')::numeric, (v_step ->> 'total')::numeric,
        (select entry_date from public.journal_entries where id = p_entry_id), 'reversal',
        v_step ->> 'source_type', (v_step ->> 'source_id')::bigint, v_reversal_id,
        (v_step ->> 'movement_id')::bigint);
    else
      perform private.stock_in(
        (v_step ->> 'item_id')::bigint, (v_step ->> 'qty')::numeric, (v_step ->> 'total')::numeric,
        (select entry_date from public.journal_entries where id = p_entry_id), 'reversal',
        v_step ->> 'source_type', (v_step ->> 'source_id')::bigint, v_reversal_id,
        (v_step ->> 'movement_id')::bigint);
    end if;
  end loop;

  return v_reversal_id;
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

  -- حسابات الأطراف والمخزون ثابتة بعد وجود قيود (حتى يطابق مجموع الأطراف والأصناف رصيد الحساب)
  if tg_op = 'UPDATE'
     and new.key in ('receivables', 'payables', 'inventory_raw', 'inventory_packaging', 'inventory_finished')
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
        else 'مخزون المنتج التام'
      end;
  end if;
  return new;
end;
$$;

-- السند وقيده (تستدعيها post_voucher وفاتورة المشتريات «مدفوع الآن»). التحقق من المستخدم في post_entry.
create function private.create_voucher(
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

-- سند قبض أو صرف (RPC)
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
begin
  perform private.require_staff();
  return private.create_voucher(
    p_kind, p_doc_date, p_treasury_account_id, p_party_kind, p_party_id, p_amount, p_notes
  );
end;
$$;

-- ---------------------------------------------------------------------
-- دوال المراحل السابقة بعد إضافة المخزون (نفس التوقيع)
-- ---------------------------------------------------------------------

-- جزء القيد الافتتاحي: الأطراف (سطور بطرف)، المخزون (سطور على حسابات المخزون)، وغير ذلك الحسابات
create or replace function private.opening_part(p_entry_id bigint)
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
    when exists (
      select 1 from public.journal_lines l
      join public.system_accounts s on s.account_id = l.account_id
      where l.entry_id = p_entry_id
        and s.key in ('inventory_raw', 'inventory_packaging', 'inventory_finished')
    ) then 'inventory'
    else 'accounts'
  end;
$$;

-- إلغاء قيد يدوي/تسوية/افتتاحي. مخزون أول المدة يُلغى مع حركاته.
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
-- فاتورة المشتريات (خامات ومواد تعبئة فقط): م المخزون حسب نوع الصنف / د الموردين + المورد،
-- وحركات إضافة بمتوسط مرجح جديد. «مدفوع الآن» ينشئ سند صرف بكامل المبلغ.
-- السطور: [{"item_id": 1, "qty": "100", "unit_price": "40"}]
-- ---------------------------------------------------------------------
create function public.post_purchase_invoice(
  p_doc_date date,
  p_supplier_id bigint,
  p_lines jsonb,
  p_notes text default null,
  p_paid_treasury_account_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_supplier text;
  v_line jsonb;
  v_no int := 0;
  v_item public.items;
  v_qty numeric;
  v_price numeric;
  v_total numeric;
  v_items bigint[] := '{}';
  v_parsed jsonb := '[]'::jsonb;
  v_raw numeric := 0;
  v_packaging numeric := 0;
  v_sum numeric;
  v_notes text := nullif(btrim(p_notes), '');
  v_id bigint;
  v_doc_no bigint;
  v_lines jsonb := '[]'::jsonb;
  v_entry_id bigint;
  v_voucher_id bigint;
  v_step jsonb;
begin
  perform private.require_staff();

  if p_doc_date is null then
    raise exception 'تاريخ الفاتورة مطلوب';
  end if;
  select name into v_supplier from public.suppliers where id = p_supplier_id and is_active;
  if not found then
    raise exception 'اختر موردًا نشطًا';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'أضف صنفًا واحدًا على الأقل';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    select * into v_item from public.items where id = nullif(v_line ->> 'item_id', '')::bigint;
    if not found then
      raise exception 'السطر %: اختر الصنف', v_no;
    end if;
    if not v_item.is_active then
      raise exception 'السطر %: الصنف % معطّل', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.type not in ('raw_material', 'packaging') then
      raise exception 'السطر %: فاتورة المشتريات للخامات ومواد التعبئة فقط، والصنف % منتج تام',
        v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.id = any (v_items) then
      raise exception 'السطر %: الصنف % مكرر في الفاتورة', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    v_items := v_items || v_item.id;

    v_qty := private.to_qty(v_line ->> 'qty', 'السطر ' || v_no || ': ');
    v_price := private.to_unit_price(v_line ->> 'unit_price', 'السطر ' || v_no || ': ');
    v_total := round(v_qty * v_price, 2);
    if v_total <= 0 then
      raise exception 'السطر %: إجمالي السطر يجب أن يكون أكبر من صفر', v_no;
    end if;
    if v_total >= 1e16 then
      raise exception 'السطر %: إجمالي السطر أكبر من الحد المسموح', v_no;
    end if;

    v_parsed := v_parsed || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'qty', v_qty, 'unit_price', v_price, 'total', v_total));
    if v_item.type = 'raw_material' then
      v_raw := v_raw + v_total;
    else
      v_packaging := v_packaging + v_total;
    end if;
  end loop;
  v_sum := v_raw + v_packaging;
  if v_sum >= 1e16 then
    raise exception 'إجمالي الفاتورة أكبر من الحد المسموح';
  end if;

  -- ترتيب الأقفال: الأصناف ← عدّاد الفواتير ← عدّاد سندات الصرف ← عدّاد القيود
  perform private.lock_items(v_items);
  v_id := nextval(pg_get_serial_sequence('public.purchase_invoices', 'id'));
  v_doc_no := private.next_doc_no('purchase_invoice');
  if p_paid_treasury_account_id is not null then
    perform 1 from public.doc_counters where kind = 'payment_voucher' for update;
  end if;

  if v_raw > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', private.inventory_account('raw_material'), 'debit', v_raw::text, 'credit', '0'));
  end if;
  if v_packaging > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', private.inventory_account('packaging'), 'debit', v_packaging::text, 'credit', '0'));
  end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object(
    'account_id', (select account_id from public.system_accounts where key = 'payables'),
    'debit', '0', 'credit', v_sum::text, 'supplier_id', p_supplier_id));

  v_entry_id := private.post_entry(
    p_doc_date,
    'فاتورة مشتريات رقم ' || v_doc_no || ' - المورد ' || v_supplier || coalesce(' - ' || v_notes, ''),
    'purchase',
    v_lines,
    v_id
  );

  if p_paid_treasury_account_id is not null then
    v_voucher_id := private.create_voucher(
      'payment', p_doc_date, p_paid_treasury_account_id, 'supplier', p_supplier_id, v_sum::text,
      'سداد فاتورة مشتريات رقم ' || v_doc_no
    );
  end if;

  insert into public.purchase_invoices (
    id, doc_no, doc_date, supplier_id, total, notes, journal_entry_id, payment_voucher_id
  )
  overriding system value
  values (v_id, v_doc_no, p_doc_date, p_supplier_id, v_sum, v_notes, v_entry_id, v_voucher_id);

  for v_step in select value from jsonb_array_elements(v_parsed) loop
    insert into public.purchase_invoice_lines (invoice_id, item_id, qty, unit_price, line_total)
    values (v_id, (v_step ->> 'item_id')::bigint, (v_step ->> 'qty')::numeric,
            (v_step ->> 'unit_price')::numeric, (v_step ->> 'total')::numeric);
    perform private.stock_in(
      (v_step ->> 'item_id')::bigint, (v_step ->> 'qty')::numeric, (v_step ->> 'total')::numeric,
      p_doc_date, 'purchase', 'purchase', v_id, v_entry_id
    );
  end loop;

  return v_id;
end;
$$;

-- إلغاء فاتورة مشتريات: قيد عكسي + حركات عكسية بنفس التكلفة. سند «مدفوع الآن» لا يُلغى معها.
create function public.cancel_purchase_invoice(p_invoice_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invoice public.purchase_invoices;
begin
  perform private.require_staff();

  select * into v_invoice from public.purchase_invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'الفاتورة غير موجودة';
  end if;
  if exists (select 1 from public.journal_entries where reverses_entry_id = v_invoice.journal_entry_id) then
    raise exception 'فاتورة المشتريات رقم % ملغاة بالفعل', v_invoice.doc_no;
  end if;

  return private.reverse_document_stock(
    v_invoice.journal_entry_id, 'إلغاء فاتورة المشتريات رقم ' || v_invoice.doc_no
  );
end;
$$;

-- ---------------------------------------------------------------------
-- تسوية الجرد (صنف واحد): العجز بمتوسط التكلفة الحالي (م فروقات الجرد / د المخزون)،
-- والزيادة بآخر متوسط معروف (م المخزون / د فروقات الجرد)
-- ---------------------------------------------------------------------
create function public.post_stock_adjustment(
  p_doc_date date,
  p_item_id bigint,
  p_counted_qty text,
  p_notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.items;
  v_counted numeric;
  v_stock public.item_stock;
  v_diff numeric;
  v_total numeric;
  v_unit numeric;
  v_notes text := nullif(btrim(p_notes), '');
  v_id bigint;
  v_doc_no bigint;
  v_inventory bigint;
  v_adjustment bigint := (select account_id from public.system_accounts where key = 'inventory_adjustment');
  v_entry_id bigint;
begin
  perform private.require_staff();

  if p_doc_date is null then
    raise exception 'تاريخ التسوية مطلوب';
  end if;
  select * into v_item from public.items where id = p_item_id;
  if not found then
    raise exception 'اختر الصنف';
  end if;
  if not v_item.is_active then
    raise exception 'الصنف % معطّل', v_item.code || ' - ' || v_item.name;
  end if;
  v_counted := private.to_qty(p_counted_qty, 'الكمية الفعلية: ', true);

  perform private.lock_items(array[p_item_id]);
  select * into v_stock from public.item_stock where item_id = p_item_id;
  v_diff := v_counted - v_stock.qty;
  if v_diff = 0 then
    raise exception 'لا فرق بين الكمية الفعلية ورصيد النظام (%)', trim_scale(v_stock.qty);
  end if;

  if v_diff < 0 then
    v_total := private.issue_cost(p_item_id, -v_diff);
    if v_total = 0 then
      raise exception 'قيمة العجز صفر لأن تكلفة الصنف صفر، ولا يُسجَّل قيد بلا قيمة';
    end if;
    v_unit := round(v_total / -v_diff, 4);
  else
    if v_stock.avg_cost = 0 then
      raise exception 'لا توجد تكلفة حالية للصنف %. سجّل مخزون أول المدة أو فاتورة مشتريات أولًا',
        v_item.code || ' - ' || v_item.name;
    end if;
    v_unit := v_stock.avg_cost;
    v_total := round(v_diff * v_unit, 2);
    if v_total = 0 then
      raise exception 'قيمة الزيادة أقل من قرش، ولا يُسجَّل قيد بلا قيمة';
    end if;
  end if;

  v_id := nextval(pg_get_serial_sequence('public.stock_adjustments', 'id'));
  v_doc_no := private.next_doc_no('stock_adjustment');
  v_inventory := private.inventory_account(v_item.type);

  v_entry_id := private.post_entry(
    p_doc_date,
    'تسوية جرد رقم ' || v_doc_no || ' - ' || v_item.code || ' - ' || v_item.name || ' - '
      || case when v_diff < 0 then 'عجز ' else 'زيادة ' end || trim_scale(abs(v_diff))
      || coalesce(' - ' || v_notes, ''),
    'stock_adjustment',
    case when v_diff < 0 then
      jsonb_build_array(
        jsonb_build_object('account_id', v_adjustment, 'debit', v_total::text, 'credit', '0'),
        jsonb_build_object('account_id', v_inventory, 'debit', '0', 'credit', v_total::text))
    else
      jsonb_build_array(
        jsonb_build_object('account_id', v_inventory, 'debit', v_total::text, 'credit', '0'),
        jsonb_build_object('account_id', v_adjustment, 'debit', '0', 'credit', v_total::text))
    end,
    v_id
  );

  insert into public.stock_adjustments (
    id, doc_no, doc_date, item_id, system_qty, counted_qty, unit_cost, total_cost, notes, journal_entry_id
  )
  overriding system value
  values (v_id, v_doc_no, p_doc_date, p_item_id, v_stock.qty, v_counted, v_unit, v_total, v_notes, v_entry_id);

  if v_diff < 0 then
    perform private.stock_out(p_item_id, -v_diff, v_total, p_doc_date, 'stock_adjustment',
                              'stock_adjustment', v_id, v_entry_id);
  else
    perform private.stock_in(p_item_id, v_diff, v_total, p_doc_date, 'stock_adjustment',
                             'stock_adjustment', v_id, v_entry_id);
  end if;

  return v_id;
end;
$$;

create function public.cancel_stock_adjustment(p_adjustment_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_adjustment public.stock_adjustments;
begin
  perform private.require_staff();

  select * into v_adjustment from public.stock_adjustments where id = p_adjustment_id for update;
  if not found then
    raise exception 'التسوية غير موجودة';
  end if;
  if exists (select 1 from public.journal_entries where reverses_entry_id = v_adjustment.journal_entry_id) then
    raise exception 'تسوية الجرد رقم % ملغاة بالفعل', v_adjustment.doc_no;
  end if;

  return private.reverse_document_stock(
    v_adjustment.journal_entry_id, 'إلغاء تسوية الجرد رقم ' || v_adjustment.doc_no
  );
end;
$$;

-- ---------------------------------------------------------------------
-- مخزون أول المدة (الجزء الثالث من الأرصدة الافتتاحية): مرة واحدة، م حسابات المخزون /
-- د رأس المال بعد التأكيد، مع حركات افتتاحية. يُلغى من القيد الافتتاحي (cancel_journal_entry).
-- السطور: [{"item_id": 1, "qty": "100", "unit_cost": "40"}]
-- ---------------------------------------------------------------------
create function public.post_stock_opening(
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
  v_item public.items;
  v_qty numeric;
  v_cost numeric;
  v_total numeric;
  v_items bigint[] := '{}';
  v_parsed jsonb := '[]'::jsonb;
  v_by_account jsonb := '{}'::jsonb;
  v_sum numeric := 0;
  v_lines jsonb := '[]'::jsonb;
  v_key text;
  v_amount numeric;
  v_entry_id bigint;
  v_step jsonb;
begin
  perform private.require_staff();

  if p_entry_date is null then
    raise exception 'تاريخ مخزون أول المدة مطلوب';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'أدخل صنفًا واحدًا على الأقل';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    select * into v_item from public.items where id = nullif(v_line ->> 'item_id', '')::bigint;
    if not found then
      raise exception 'السطر %: اختر الصنف', v_no;
    end if;
    if not v_item.is_active then
      raise exception 'السطر %: الصنف % معطّل', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.id = any (v_items) then
      raise exception 'السطر %: الصنف % مكرر', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    v_items := v_items || v_item.id;

    v_qty := private.to_qty(v_line ->> 'qty', 'السطر ' || v_no || ': ');
    v_cost := private.to_unit_price(v_line ->> 'unit_cost', 'السطر ' || v_no || ': ');
    v_total := round(v_qty * v_cost, 2);
    if v_total <= 0 then
      raise exception 'السطر %: قيمة الصنف يجب أن تكون أكبر من صفر', v_no;
    end if;

    v_parsed := v_parsed || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'qty', v_qty, 'total', v_total));
    v_key := private.inventory_account(v_item.type)::text;
    v_by_account := jsonb_set(v_by_account, array[v_key],
      to_jsonb(coalesce((v_by_account ->> v_key)::numeric, 0) + v_total));
    v_sum := v_sum + v_total;
  end loop;

  -- الأصناف ثم عدّاد القيود (نفس ترتيب الأقفال)، ثم شرط «مرة واحدة» لجزء المخزون
  perform private.lock_items(v_items);
  perform 1 from public.doc_counters where kind = 'journal' for update;

  if exists (
    select 1 from public.journal_entries o
    where o.source_type = 'opening'
      and not exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.id)
      and private.opening_part(o.id) = 'inventory'
  ) then
    raise exception 'مخزون أول المدة مسجّل بالفعل. للتصحيح ألغِ قيده ثم سجّله من جديد';
  end if;

  -- جزء المخزون في جانب واحد، فقيمته كلها فرق على رأس المال بعد التأكيد
  if not coalesce(p_difference_to_capital, false) then
    raise exception 'الأرصدة غير متوازنة: المدين % والدائن % والفرق %. أكّد تسجيل الفرق على حساب رأس المال',
      private.fmt_amount(v_sum), private.fmt_amount(0), private.fmt_amount(v_sum);
  end if;

  for v_key, v_amount in select key, value::numeric from jsonb_each_text(v_by_account) loop
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', v_key::bigint, 'debit', v_amount::text, 'credit', '0'));
  end loop;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object(
    'account_id', (select account_id from public.system_accounts where key = 'capital'),
    'debit', '0', 'credit', v_sum::text, 'description', 'فرق الأرصدة الافتتاحية'));

  v_entry_id := private.post_entry(p_entry_date, 'مخزون أول المدة', 'opening', v_lines);

  for v_step in select value from jsonb_array_elements(v_parsed) loop
    perform private.stock_in(
      (v_step ->> 'item_id')::bigint, (v_step ->> 'qty')::numeric, (v_step ->> 'total')::numeric,
      p_entry_date, 'opening', 'opening', v_entry_id, v_entry_id
    );
  end loop;

  return v_entry_id;
end;
$$;

-- ---------------------------------------------------------------------
-- دوال القراءة (RLS يسري عليها، والمبالغ والكميات نصوص)
-- ---------------------------------------------------------------------

-- أرصدة المخزون: كمية ومتوسط تكلفة وقيمة لكل صنف
create function public.stock_balances()
returns table (
  item_id bigint,
  code text,
  name text,
  type text,
  unit text,
  is_active boolean,
  qty text,
  avg_cost text,
  value text
)
language sql
stable
set search_path = ''
as $$
  select i.id, i.code, i.name, i.type, i.unit, i.is_active,
         s.qty::text, s.avg_cost::text, s.value::text
  from public.items i
  join public.item_stock s on s.item_id = i.id
  order by i.type, i.code;
$$;

-- حركة صنف: رصيد أول المدة ثم الحركات برصيد جارٍ (كمية وقيمة) بترتيب التاريخ
create function public.item_movements(
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
         end,
         r.journal_entry_id,
         round(r.qty_in, 3)::text, round(r.qty_out, 3)::text, round(r.unit_cost, 4)::text,
         round(r.total_cost, 2)::text, round(r.balance_qty, 3)::text, round(r.balance_value, 2)::text
  from report r
  order by r.grp, r.movement_date, r.id;
$$;

-- قائمة فواتير المشتريات (ملغاة = لقيدها قيد عكسي)
create function public.purchase_invoice_list(
  p_from date default null,
  p_to date default null,
  p_search text default null
)
returns table (
  id bigint,
  doc_no bigint,
  doc_date date,
  supplier_name text,
  total text,
  notes text,
  journal_entry_id bigint,
  payment_voucher_id bigint,
  is_cancelled boolean
)
language sql
stable
set search_path = ''
as $$
  select p.id, p.doc_no, p.doc_date, s.name, p.total::text, p.notes, p.journal_entry_id,
         p.payment_voucher_id,
         exists (select 1 from public.journal_entries r where r.reverses_entry_id = p.journal_entry_id)
  from public.purchase_invoices p
  join public.suppliers s on s.id = p.supplier_id
  where (p_from is null or p.doc_date >= p_from)
    and (p_to is null or p.doc_date <= p_to)
    and (
      coalesce(btrim(p_search), '') = ''
      or p.doc_no::text = btrim(p_search)
      or s.name ilike '%' || btrim(p_search) || '%'
      or p.notes ilike '%' || btrim(p_search) || '%'
    )
  order by p.doc_date desc, p.doc_no desc;
$$;

-- قائمة تسويات الجرد
create function public.stock_adjustment_list(
  p_from date default null,
  p_to date default null,
  p_search text default null
)
returns table (
  id bigint,
  doc_no bigint,
  doc_date date,
  item_code text,
  item_name text,
  system_qty text,
  counted_qty text,
  total_cost text,
  notes text,
  journal_entry_id bigint,
  is_cancelled boolean
)
language sql
stable
set search_path = ''
as $$
  select a.id, a.doc_no, a.doc_date, i.code, i.name, a.system_qty::text, a.counted_qty::text,
         a.total_cost::text, a.notes, a.journal_entry_id,
         exists (select 1 from public.journal_entries r where r.reverses_entry_id = a.journal_entry_id)
  from public.stock_adjustments a
  join public.items i on i.id = a.item_id
  where (p_from is null or a.doc_date >= p_from)
    and (p_to is null or a.doc_date <= p_to)
    and (
      coalesce(btrim(p_search), '') = ''
      or a.doc_no::text = btrim(p_search)
      or i.code ilike '%' || btrim(p_search) || '%'
      or i.name ilike '%' || btrim(p_search) || '%'
      or a.notes ilike '%' || btrim(p_search) || '%'
    )
  order by a.doc_date desc, a.doc_no desc;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات و RLS: الأصناف للمدير والمحاسب (أعمدة محددة)، والباقي قراءة فقط (الكتابة عبر الدوال)
-- ---------------------------------------------------------------------
revoke execute on function
  private.create_item_stock(),
  private.validate_item(),
  private.inventory_account(text),
  private.check_item_stock(),
  private.check_entry_inventory(),
  private.to_qty(text, text, boolean),
  private.to_unit_price(text, text),
  private.lock_items(bigint[]),
  private.item_label(bigint),
  private.issue_cost(bigint, numeric),
  private.stock_in(bigint, numeric, numeric, date, text, text, bigint, bigint, bigint),
  private.stock_out(bigint, numeric, numeric, date, text, text, bigint, bigint, bigint),
  private.reverse_entry(bigint, text, jsonb),
  private.reverse_document_stock(bigint, text),
  private.create_voucher(text, date, bigint, text, bigint, text, text)
from public, anon, authenticated;

revoke execute on function
  public.post_purchase_invoice(date, bigint, jsonb, text, bigint),
  public.cancel_purchase_invoice(bigint),
  public.post_stock_adjustment(date, bigint, text, text),
  public.cancel_stock_adjustment(bigint),
  public.post_stock_opening(date, jsonb, boolean),
  public.stock_balances(),
  public.item_movements(bigint, date, date),
  public.purchase_invoice_list(date, date, text),
  public.stock_adjustment_list(date, date, text)
from public, anon;

grant execute on function
  public.post_purchase_invoice(date, bigint, jsonb, text, bigint),
  public.cancel_purchase_invoice(bigint),
  public.post_stock_adjustment(date, bigint, text, text),
  public.cancel_stock_adjustment(bigint),
  public.post_stock_opening(date, jsonb, boolean),
  public.stock_balances(),
  public.item_movements(bigint, date, date),
  public.purchase_invoice_list(date, date, text),
  public.stock_adjustment_list(date, date, text)
to authenticated;

alter table public.items enable row level security;
alter table public.item_stock enable row level security;
alter table public.stock_movements enable row level security;
alter table public.purchase_invoices enable row level security;
alter table public.purchase_invoice_lines enable row level security;
alter table public.stock_adjustments enable row level security;

revoke all on public.items, public.item_stock, public.stock_movements, public.purchase_invoices,
  public.purchase_invoice_lines, public.stock_adjustments
from anon, authenticated;
revoke all on sequence public.items_id_seq, public.stock_movements_id_seq, public.purchase_invoices_id_seq,
  public.purchase_invoice_lines_id_seq, public.stock_adjustments_id_seq
from anon, authenticated;

grant select, delete on public.items to authenticated;
grant insert (code, name, type, unit, sale_price, is_active),
      update (code, name, type, unit, sale_price, is_active)
  on public.items to authenticated;
grant select on public.item_stock, public.stock_movements, public.purchase_invoices,
  public.purchase_invoice_lines, public.stock_adjustments
to authenticated;

create policy items_select on public.items for select to authenticated using (true);
create policy items_insert on public.items for insert to authenticated with check (true);
create policy items_update on public.items for update to authenticated using (true) with check (true);
create policy items_delete on public.items for delete to authenticated using (true);
create policy item_stock_select on public.item_stock for select to authenticated using (true);
create policy stock_movements_select on public.stock_movements for select to authenticated using (true);
create policy purchase_invoices_select on public.purchase_invoices for select to authenticated using (true);
create policy purchase_invoice_lines_select on public.purchase_invoice_lines for select to authenticated using (true);
create policy stock_adjustments_select on public.stock_adjustments for select to authenticated using (true);
