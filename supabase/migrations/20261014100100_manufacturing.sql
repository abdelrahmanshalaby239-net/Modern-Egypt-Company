-- =====================================================================
-- المرحلة 5: التصنيع — الوصفات، تسجيل الإنتاج، تقرير الإنتاج (SPEC §7)
-- الإنتاج يصرف المواد بمتوسط التكلفة وقت التسجيل، ويضيف المنتج التام بإجمالي التكلفة (المواد + الإضافية)
-- فيُحسب متوسطه الجديد، والقيد في نفس الـ transaction. الكميات بأي وحدة من وحدات الصنف وتُحفظ بمعاملها.
-- ترحيل إضافي فقط (بلا DROP).
-- =====================================================================

-- ---------------------------------------------------------------------
-- الوصفات (بيانات أساسية تُعدَّل؛ أوامر الإنتاج تحفظ سطورها الفعلية)
-- ---------------------------------------------------------------------
create table public.formulas (
  id bigint generated always as identity primary key,
  name text not null unique check (btrim(name) <> '' and name = btrim(name)),
  finished_item_id bigint not null references public.items (id),
  batch_qty numeric(18, 3) not null check (batch_qty > 0),
  batch_unit_id bigint,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint formulas_batch_unit_fkey foreign key (batch_unit_id, finished_item_id)
    references public.item_units (id, item_id)
);

create table public.formula_lines (
  id bigint generated always as identity primary key,
  formula_id bigint not null references public.formulas (id) on delete cascade,
  item_id bigint not null references public.items (id),
  unit_id bigint,
  qty_per_batch numeric(18, 3) not null check (qty_per_batch > 0),
  unique (formula_id, item_id),
  constraint formula_lines_unit_fkey foreign key (unit_id, item_id) references public.item_units (id, item_id)
);

create index formulas_finished_item_id_idx on public.formulas (finished_item_id);
create index formula_lines_item_id_idx on public.formula_lines (item_id);

-- ---------------------------------------------------------------------
-- أوامر الإنتاج (ثابتة بعد الاعتماد، و«ملغى» = لقيدها قيد عكسي)
-- ---------------------------------------------------------------------
create table public.production_orders (
  id bigint generated always as identity primary key,
  doc_no bigint not null unique,
  doc_date date not null,
  formula_id bigint not null references public.formulas (id),
  finished_item_id bigint not null references public.items (id),
  batches numeric(18, 3) not null check (batches > 0),
  unit_id bigint,
  unit_name text not null check (btrim(unit_name) <> ''),
  factor numeric(18, 6) not null check (factor > 0),
  qty_produced numeric(18, 3) not null check (qty_produced > 0),
  base_qty_produced numeric(18, 3) not null check (base_qty_produced > 0),
  materials_cost numeric(18, 2) not null check (materials_cost >= 0),
  extra_cost numeric(18, 2) not null default 0 check (extra_cost >= 0),
  extra_cost_account_id bigint references public.accounts (id),
  total_cost numeric(18, 2) not null check (total_cost > 0),
  unit_cost numeric(18, 4) not null check (unit_cost >= 0),
  notes text,
  journal_entry_id bigint not null unique references public.journal_entries (id),
  created_at timestamptz not null default now(),
  constraint production_orders_total check (total_cost = materials_cost + extra_cost),
  constraint production_orders_extra_account check ((extra_cost > 0) = (extra_cost_account_id is not null)),
  constraint production_orders_base_unit_factor check (unit_id is not null or factor = 1),
  constraint production_orders_base_qty check (base_qty_produced = qty_produced * factor),
  constraint production_orders_unit_fkey foreign key (unit_id, finished_item_id)
    references public.item_units (id, item_id)
);

create table public.production_lines (
  id bigint generated always as identity primary key,
  order_id bigint not null references public.production_orders (id),
  item_id bigint not null references public.items (id),
  unit_id bigint,
  unit_name text not null check (btrim(unit_name) <> ''),
  factor numeric(18, 6) not null check (factor > 0),
  standard_base_qty numeric check (standard_base_qty >= 0),
  qty numeric(18, 3) not null check (qty > 0),
  base_qty numeric(18, 3) not null check (base_qty > 0),
  unit_cost numeric(18, 4) not null check (unit_cost >= 0),
  total_cost numeric(18, 2) not null check (total_cost >= 0),
  unique (order_id, item_id),
  constraint production_lines_base_unit_factor check (unit_id is not null or factor = 1),
  constraint production_lines_base_qty check (base_qty = qty * factor),
  constraint production_lines_unit_fkey foreign key (unit_id, item_id) references public.item_units (id, item_id)
);

create index production_orders_doc_date_idx on public.production_orders (doc_date);
create index production_orders_finished_item_id_idx on public.production_orders (finished_item_id);
create index production_orders_formula_id_idx on public.production_orders (formula_id);
create index production_lines_item_id_idx on public.production_lines (item_id);

insert into public.doc_counters (kind, last_no) values ('production_order', 0)
on conflict (kind) do nothing;

create trigger forbid_change before update or delete on public.production_orders
  for each row execute function private.forbid_document_change();
create trigger forbid_truncate before truncate on public.production_orders
  for each statement execute function private.forbid_document_change();
create trigger forbid_change before update or delete on public.production_lines
  for each row execute function private.forbid_document_change();
create trigger forbid_truncate before truncate on public.production_lines
  for each statement execute function private.forbid_document_change();

-- ---------------------------------------------------------------------
-- الصنف أو الوحدة مستخدمان: + الوصفات والإنتاج
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
      or exists (select 1 from public.production_lines where item_id = p_item_id);
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
      or exists (select 1 from public.production_lines where unit_id = p_unit_id);
$$;

-- ---------------------------------------------------------------------
-- حفظ الوصفة (إضافة أو تعديل؛ السطور تُستبدل). المنتج تام، والمواد خامات أو تعبئة، والصنف مرة واحدة.
-- السطور: [{"item_id": 1, "unit_id": null, "qty_per_batch": "8"}]
-- ---------------------------------------------------------------------
create function public.save_formula(
  p_id bigint,
  p_name text,
  p_finished_item_id bigint,
  p_batch_qty text,
  p_batch_unit_id bigint,
  p_lines jsonb,
  p_notes text default null,
  p_is_active boolean default true
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint := p_id;
  v_name text := btrim(coalesce(p_name, ''));
  v_finished public.items;
  v_unit record;
  v_batch numeric;
  v_line jsonb;
  v_no int := 0;
  v_item public.items;
  v_qty numeric;
  v_items bigint[] := '{}';
  v_parsed jsonb := '[]'::jsonb;
  v_step jsonb;
begin
  perform private.require_staff();

  if v_name = '' then
    raise exception 'اسم الوصفة مطلوب';
  end if;
  select * into v_finished from public.items where id = p_finished_item_id;
  if not found then
    raise exception 'اختر المنتج التام';
  end if;
  if v_finished.type <> 'finished_good' then
    raise exception 'الوصفة تنتج منتجًا تامًا فقط، والصنف % ليس منتجًا تامًا', v_finished.code || ' - ' || v_finished.name;
  end if;
  if not v_finished.is_active then
    raise exception 'الصنف % معطّل', v_finished.code || ' - ' || v_finished.name;
  end if;
  select * into v_unit from private.resolve_unit(v_finished.id, p_batch_unit_id, 'كمية الدفعة: ');
  v_batch := private.to_qty(p_batch_qty, 'كمية الدفعة: ');
  perform private.to_base_qty(v_batch, v_unit.factor, 'كمية الدفعة: ');

  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'أضف مادة واحدة على الأقل';
  end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    select * into v_item from public.items where id = nullif(v_line ->> 'item_id', '')::bigint;
    if not found then
      raise exception 'السطر %: اختر المادة', v_no;
    end if;
    if not v_item.is_active then
      raise exception 'السطر %: الصنف % معطّل', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.type not in ('raw_material', 'packaging') then
      raise exception 'السطر %: مواد الوصفة خامات أو مواد تعبئة فقط، والصنف % منتج تام',
        v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.id = any (v_items) then
      raise exception 'السطر %: الصنف % مكرر في الوصفة', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    v_items := v_items || v_item.id;
    select * into v_unit
    from private.resolve_unit(v_item.id, nullif(v_line ->> 'unit_id', '')::bigint, 'السطر ' || v_no || ': ');
    v_qty := private.to_qty(v_line ->> 'qty_per_batch', 'السطر ' || v_no || ': ');
    perform private.to_base_qty(v_qty, v_unit.factor, 'السطر ' || v_no || ': ');
    v_parsed := v_parsed || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'unit_id', v_unit.unit_id, 'qty', v_qty));
  end loop;

  begin
    if v_id is null then
      insert into public.formulas (name, finished_item_id, batch_qty, batch_unit_id, notes, is_active)
      values (v_name, v_finished.id, v_batch, p_batch_unit_id, nullif(btrim(p_notes), ''), coalesce(p_is_active, true))
      returning id into v_id;
    else
      update public.formulas
      set name = v_name, finished_item_id = v_finished.id, batch_qty = v_batch, batch_unit_id = p_batch_unit_id,
          notes = nullif(btrim(p_notes), ''), is_active = coalesce(p_is_active, true)
      where id = v_id;
      if not found then
        raise exception 'الوصفة غير موجودة';
      end if;
      delete from public.formula_lines where formula_id = v_id;
    end if;
  exception when unique_violation then
    raise exception 'يوجد وصفة بنفس الاسم';
  end;

  for v_step in select value from jsonb_array_elements(v_parsed) loop
    insert into public.formula_lines (formula_id, item_id, unit_id, qty_per_batch)
    values (v_id, (v_step ->> 'item_id')::bigint, nullif(v_step ->> 'unit_id', '')::bigint, (v_step ->> 'qty')::numeric);
  end loop;

  return v_id;
end;
$$;

-- حذف وصفة لم تُستخدم (المستخدمة تُعطَّل بدل الحذف)
create function public.delete_formula(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_staff();
  delete from public.formulas where id = p_id;
  if not found then
    raise exception 'الوصفة غير موجودة';
  end if;
exception when foreign_key_violation then
  raise exception 'لا يمكن حذف وصفة استُخدمت في الإنتاج. عطّلها بدل الحذف';
end;
$$;

-- ---------------------------------------------------------------------
-- تسجيل الإنتاج (SPEC §6.1 و§7): م مخزون منتج تام (المواد + الإضافية) / د مخزون الخام والتعبئة
-- المستهلكة + د حساب التكاليف الإضافية (خزينة/بنك أو خصوم مثل المصروفات المستحقة).
-- يُرفض لو أي مادة رصيدها لا يكفي. ترتيب الأقفال: الأصناف ← عدّاد أوامر الإنتاج ← عدّاد القيود.
-- السطور: [{"item_id": 1, "unit_id": null, "qty": "16"}]
-- ---------------------------------------------------------------------
create function public.post_production_order(
  p_doc_date date,
  p_formula_id bigint,
  p_batches text,
  p_qty_produced text,
  p_unit_id bigint,
  p_lines jsonb,
  p_extra_cost text default null,
  p_extra_cost_account_id bigint default null,
  p_notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_formula public.formulas;
  v_finished public.items;
  v_unit record;
  v_batches numeric;
  v_qty numeric;
  v_base numeric;
  v_line jsonb;
  v_no int := 0;
  v_item public.items;
  v_line_unit record;
  v_line_qty numeric;
  v_line_base numeric;
  v_standard numeric;
  v_stock public.item_stock;
  v_cost numeric;
  v_items bigint[] := '{}';
  v_lock bigint[];
  v_parsed jsonb := '[]'::jsonb;
  v_raw numeric := 0;
  v_packaging numeric := 0;
  v_materials numeric;
  v_extra numeric;
  v_extra_account public.accounts;
  v_total numeric;
  v_notes text := nullif(btrim(p_notes), '');
  v_id bigint;
  v_doc_no bigint;
  v_lines jsonb := '[]'::jsonb;
  v_entry_id bigint;
  v_step jsonb;
begin
  perform private.require_staff();

  if p_doc_date is null then
    raise exception 'تاريخ الإنتاج مطلوب';
  end if;
  select * into v_formula from public.formulas where id = p_formula_id;
  if not found or not v_formula.is_active then
    raise exception 'اختر وصفة نشطة';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'أضف مادة واحدة على الأقل';
  end if;

  -- قفل كل الأصناف (المنتج والمواد) بترتيب ثابت قبل قراءة أنواعها وأرصدتها
  select coalesce(array_agg(distinct x), '{}') into v_lock
  from (
    select v_formula.finished_item_id as x
    union all
    select nullif(value ->> 'item_id', '')::bigint from jsonb_array_elements(p_lines)
  ) s
  where x is not null;
  perform private.lock_items(v_lock);

  select * into v_finished from public.items where id = v_formula.finished_item_id;
  if not v_finished.is_active then
    raise exception 'المنتج % معطّل', v_finished.code || ' - ' || v_finished.name;
  end if;

  v_batches := private.to_qty(p_batches, 'عدد الدفعات: ');
  select * into v_unit from private.resolve_unit(v_finished.id, p_unit_id, 'الكمية المنتجة: ');
  v_qty := private.to_qty(p_qty_produced, 'الكمية المنتجة: ');
  v_base := private.to_base_qty(v_qty, v_unit.factor, 'الكمية المنتجة: ');

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_no := v_no + 1;
    select * into v_item from public.items where id = nullif(v_line ->> 'item_id', '')::bigint;
    if not found then
      raise exception 'السطر %: اختر المادة', v_no;
    end if;
    if not v_item.is_active then
      raise exception 'السطر %: الصنف % معطّل', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.type not in ('raw_material', 'packaging') then
      raise exception 'السطر %: مواد الإنتاج خامات أو مواد تعبئة فقط، والصنف % منتج تام',
        v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.id = any (v_items) then
      raise exception 'السطر %: الصنف % مكرر', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    v_items := v_items || v_item.id;

    select * into v_line_unit
    from private.resolve_unit(v_item.id, nullif(v_line ->> 'unit_id', '')::bigint, 'السطر ' || v_no || ': ');
    v_line_qty := private.to_qty(v_line ->> 'qty', 'السطر ' || v_no || ': ');
    v_line_base := private.to_base_qty(v_line_qty, v_line_unit.factor, 'السطر ' || v_no || ': ');

    -- الكمية المعيارية من الوصفة (بالوحدة الأساسية) لمقارنة الهالك
    select fl.qty_per_batch * coalesce(u.factor, 1) * v_batches into v_standard
    from public.formula_lines fl
    left join public.item_units u on u.id = fl.unit_id
    where fl.formula_id = v_formula.id and fl.item_id = v_item.id;

    select * into v_stock from public.item_stock where item_id = v_item.id;
    if v_line_base > v_stock.qty then
      raise exception 'السطر %: الكمية المطلوبة من الصنف % هي % % والمتاح % % فقط (النقص %)',
        v_no, v_item.code || ' - ' || v_item.name, trim_scale(v_line_base), v_item.unit,
        trim_scale(v_stock.qty), v_item.unit, trim_scale(v_line_base - v_stock.qty);
    end if;
    v_cost := private.issue_cost(v_item.id, v_line_base);

    v_parsed := v_parsed || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'unit_id', v_line_unit.unit_id, 'unit_name', v_line_unit.unit_name,
      'factor', v_line_unit.factor, 'standard', v_standard, 'qty', v_line_qty, 'base_qty', v_line_base,
      'cost', v_cost));
    if v_item.type = 'raw_material' then
      v_raw := v_raw + v_cost;
    else
      v_packaging := v_packaging + v_cost;
    end if;
  end loop;
  v_materials := v_raw + v_packaging;

  -- التكاليف الإضافية (اختياري): مبلغ واحد + الحساب الدائن له
  v_extra := private.to_amount(p_extra_cost, 'التكاليف الإضافية: ');
  if v_extra > 0 then
    select * into v_extra_account from public.accounts where id = p_extra_cost_account_id;
    if not found then
      raise exception 'اختر الحساب الدائن للتكاليف الإضافية';
    end if;
    if not v_extra_account.is_postable or not v_extra_account.is_active then
      raise exception 'الترحيل مسموح فقط على حساب فرعي نشط: % - %', v_extra_account.code, v_extra_account.name;
    end if;
    if not (v_extra_account.is_treasury
            or (v_extra_account.type = 'liability' and cardinality(private.account_keys(v_extra_account.id)) = 0)) then
      raise exception 'حساب التكاليف الإضافية يجب أن يكون خزينة أو بنكًا أو حساب خصوم (مثل المصروفات المستحقة)';
    end if;
  end if;

  v_total := v_materials + v_extra;
  if v_total <= 0 then
    raise exception 'تكلفة الإنتاج صفر، ولا يُسجَّل قيد بلا قيمة';
  end if;
  if v_total >= 1e16 then
    raise exception 'تكلفة الإنتاج أكبر من الحد المسموح';
  end if;

  v_id := nextval(pg_get_serial_sequence('public.production_orders', 'id'));
  v_doc_no := private.next_doc_no('production_order');

  v_lines := jsonb_build_array(jsonb_build_object(
    'account_id', private.inventory_account('finished_good'), 'debit', v_total::text, 'credit', '0'));
  if v_raw > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', private.inventory_account('raw_material'), 'debit', '0', 'credit', v_raw::text,
      'description', 'خامات مستهلكة'));
  end if;
  if v_packaging > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', private.inventory_account('packaging'), 'debit', '0', 'credit', v_packaging::text,
      'description', 'مواد تعبئة مستهلكة'));
  end if;
  if v_extra > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'account_id', v_extra_account.id, 'debit', '0', 'credit', v_extra::text, 'description', 'تكاليف إضافية للإنتاج'));
  end if;

  v_entry_id := private.post_entry(
    p_doc_date,
    'أمر إنتاج رقم ' || v_doc_no || ' - ' || v_finished.code || ' - ' || v_finished.name || ' - '
      || trim_scale(v_qty) || ' ' || v_unit.unit_name || coalesce(' - ' || v_notes, ''),
    'production',
    v_lines,
    v_id
  );

  insert into public.production_orders (
    id, doc_no, doc_date, formula_id, finished_item_id, batches, unit_id, unit_name, factor,
    qty_produced, base_qty_produced, materials_cost, extra_cost, extra_cost_account_id, total_cost,
    unit_cost, notes, journal_entry_id
  )
  overriding system value
  values (
    v_id, v_doc_no, p_doc_date, v_formula.id, v_finished.id, v_batches, v_unit.unit_id, v_unit.unit_name,
    v_unit.factor, v_qty, v_base, v_materials, v_extra, case when v_extra > 0 then v_extra_account.id end,
    v_total, round(v_total / v_base, 4), v_notes, v_entry_id
  );

  for v_step in select value from jsonb_array_elements(v_parsed) loop
    insert into public.production_lines (
      order_id, item_id, unit_id, unit_name, factor, standard_base_qty, qty, base_qty, unit_cost, total_cost
    )
    values (
      v_id, (v_step ->> 'item_id')::bigint, nullif(v_step ->> 'unit_id', '')::bigint, v_step ->> 'unit_name',
      (v_step ->> 'factor')::numeric, (v_step ->> 'standard')::numeric, (v_step ->> 'qty')::numeric,
      (v_step ->> 'base_qty')::numeric,
      round((v_step ->> 'cost')::numeric / (v_step ->> 'base_qty')::numeric, 4), (v_step ->> 'cost')::numeric
    );
    perform private.stock_out(
      (v_step ->> 'item_id')::bigint, (v_step ->> 'base_qty')::numeric, (v_step ->> 'cost')::numeric,
      p_doc_date, 'production', 'production', v_id, v_entry_id
    );
  end loop;

  perform private.stock_in(v_finished.id, v_base, v_total, p_doc_date, 'production', 'production', v_id, v_entry_id);

  return v_id;
end;
$$;

-- إلغاء أمر إنتاج: قيد عكسي + حركات عكسية بنفس التكلفة (المواد ترجع، والمنتج يخرج). يُرفض لو صُرف من
-- المنتج ما يجعل رصيده سالبًا. التكاليف الإضافية تُعكس على حسابها مع القيد.
create function public.cancel_production_order(p_order_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.production_orders;
begin
  perform private.require_staff();

  select * into v_order from public.production_orders where id = p_order_id for update;
  if not found then
    raise exception 'أمر الإنتاج غير موجود';
  end if;
  if exists (select 1 from public.journal_entries where reverses_entry_id = v_order.journal_entry_id) then
    raise exception 'أمر الإنتاج رقم % ملغى بالفعل', v_order.doc_no;
  end if;

  return private.reverse_document_stock(v_order.journal_entry_id, 'إلغاء أمر الإنتاج رقم ' || v_order.doc_no);
end;
$$;

-- ---------------------------------------------------------------------
-- دوال القراءة
-- ---------------------------------------------------------------------

-- قائمة أوامر الإنتاج وتقريره (ملغى = لقيده قيد عكسي)
create function public.production_list(
  p_from date default null,
  p_to date default null,
  p_search text default null,
  p_item_id bigint default null
)
returns table (
  id bigint,
  doc_no bigint,
  doc_date date,
  formula_name text,
  item_id bigint,
  item_code text,
  item_name text,
  base_unit text,
  unit_name text,
  batches text,
  qty_produced text,
  base_qty_produced text,
  materials_cost text,
  extra_cost text,
  total_cost text,
  unit_cost text,
  notes text,
  journal_entry_id bigint,
  is_cancelled boolean
)
language sql
stable
set search_path = ''
as $$
  select o.id, o.doc_no, o.doc_date, f.name, i.id, i.code, i.name, i.unit, o.unit_name,
         trim_scale(o.batches)::text, o.qty_produced::text, o.base_qty_produced::text, o.materials_cost::text,
         o.extra_cost::text, o.total_cost::text, o.unit_cost::text, o.notes, o.journal_entry_id,
         exists (select 1 from public.journal_entries r where r.reverses_entry_id = o.journal_entry_id)
  from public.production_orders o
  join public.formulas f on f.id = o.formula_id
  join public.items i on i.id = o.finished_item_id
  where (p_from is null or o.doc_date >= p_from)
    and (p_to is null or o.doc_date <= p_to)
    and (p_item_id is null or o.finished_item_id = p_item_id)
    and (
      coalesce(btrim(p_search), '') = ''
      or o.doc_no::text = btrim(p_search)
      or i.code ilike '%' || btrim(p_search) || '%'
      or i.name ilike '%' || btrim(p_search) || '%'
      or f.name ilike '%' || btrim(p_search) || '%'
      or o.notes ilike '%' || btrim(p_search) || '%'
    )
  order by o.doc_date desc, o.doc_no desc;
$$;

-- حركة صنف: رقم المستند لأوامر الإنتاج أيضًا (نفس التوقيع والأعمدة)
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
         end,
         r.journal_entry_id,
         round(r.qty_in, 3)::text, round(r.qty_out, 3)::text, round(r.unit_cost, 4)::text,
         round(r.total_cost, 2)::text, round(r.balance_qty, 3)::text, round(r.balance_value, 2)::text
  from report r
  order by r.grp, r.movement_date, r.id;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات و RLS: الوصفات والإنتاج قراءة فقط للمستخدم، والكتابة عبر الدوال
-- ---------------------------------------------------------------------
revoke execute on function
  public.save_formula(bigint, text, bigint, text, bigint, jsonb, text, boolean),
  public.delete_formula(bigint),
  public.post_production_order(date, bigint, text, text, bigint, jsonb, text, bigint, text),
  public.cancel_production_order(bigint),
  public.production_list(date, date, text, bigint)
from public, anon;

grant execute on function
  public.save_formula(bigint, text, bigint, text, bigint, jsonb, text, boolean),
  public.delete_formula(bigint),
  public.post_production_order(date, bigint, text, text, bigint, jsonb, text, bigint, text),
  public.cancel_production_order(bigint),
  public.production_list(date, date, text, bigint)
to authenticated;

alter table public.formulas enable row level security;
alter table public.formula_lines enable row level security;
alter table public.production_orders enable row level security;
alter table public.production_lines enable row level security;

revoke all on public.formulas, public.formula_lines, public.production_orders, public.production_lines
from anon, authenticated;
revoke all on sequence public.formulas_id_seq, public.formula_lines_id_seq, public.production_orders_id_seq,
  public.production_lines_id_seq
from anon, authenticated;

grant select on public.formulas, public.formula_lines, public.production_orders, public.production_lines
to authenticated;

create policy formulas_select on public.formulas for select to authenticated using (true);
create policy formula_lines_select on public.formula_lines for select to authenticated using (true);
create policy production_orders_select on public.production_orders for select to authenticated using (true);
create policy production_lines_select on public.production_lines for select to authenticated using (true);
