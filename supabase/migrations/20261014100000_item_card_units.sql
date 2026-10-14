-- =====================================================================
-- المرحلة 5 (بطاقة الصنف): التصنيفات، التكلفة الافتراضية، الحد الأدنى، الباركود، ووحدات القياس البديلة.
-- الوحدة الأساسية تبقى items.unit (معامل 1) وسعر بيعها items.sale_price، والوحدات البديلة في item_units.
-- المخزون والتكلفة دائمًا بالوحدة الأساسية، وكل سطر مستند يحفظ الوحدة ومعاملها وقت الاعتماد.
-- التكلفة الافتراضية لا تمس item_stock أبدًا: تقترح تكلفة مخزون أول المدة فقط.
-- ترحيل إضافي فقط (بلا DROP).
-- =====================================================================

-- ---------------------------------------------------------------------
-- التصنيفات
-- ---------------------------------------------------------------------
create table public.item_categories (
  id bigint generated always as identity primary key,
  name text not null unique check (btrim(name) <> '' and name = btrim(name)),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- حقول بطاقة الصنف الجديدة
-- ---------------------------------------------------------------------
alter table public.items
  add column category_id bigint references public.item_categories (id),
  add column default_cost numeric(18, 4) not null default 0 check (default_cost >= 0),
  add column min_stock numeric(18, 3) not null default 0 check (min_stock >= 0),
  add column barcode text unique check (barcode is null or (btrim(barcode) <> '' and barcode = btrim(barcode)));

create index items_category_id_idx on public.items (category_id);

-- الوحدات البديلة: الكمية بالوحدة الأساسية = الكمية × المعامل
create table public.item_units (
  id bigint generated always as identity primary key,
  item_id bigint not null references public.items (id) on delete cascade,
  name text not null check (btrim(name) <> '' and name = btrim(name)),
  factor numeric not null check (factor > 0 and factor < 1e9 and scale(trim_scale(factor)) <= 6),
  sale_price numeric(18, 2) check (sale_price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (item_id, name),
  unique (id, item_id)
);

-- وحدة البيع الافتراضية (فارغ = الوحدة الأساسية). المفتاح المركّب يضمن أنها من وحدات نفس الصنف.
alter table public.items
  add column default_sale_unit_id bigint,
  add constraint items_default_sale_unit_fkey foreign key (default_sale_unit_id, id)
    references public.item_units (id, item_id) on delete set null (default_sale_unit_id);

-- ---------------------------------------------------------------------
-- سطور فاتورة المشتريات بالوحدات: الوحدة ومعاملها محفوظان، والكمية الأساسية محسوبة بلا تقريب
-- (الجدول ثابت، فالأعمدة تُضاف بلا UPDATE: base_qty عمود محسوب، و unit_name فارغ = الوحدة الأساسية)
-- ---------------------------------------------------------------------
alter table public.purchase_invoice_lines
  add column unit_id bigint,
  add column unit_name text check (unit_name is null or btrim(unit_name) <> ''),
  add column factor numeric(18, 6) not null default 1 check (factor > 0),
  add column base_qty numeric(18, 3) generated always as (qty * factor) stored,
  add constraint purchase_invoice_lines_exact_base check (qty * factor = round(qty * factor, 3)),
  add constraint purchase_invoice_lines_base_unit_factor check (unit_id is not null or factor = 1),
  add constraint purchase_invoice_lines_unit_fkey foreign key (unit_id, item_id)
    references public.item_units (id, item_id);

create index purchase_invoice_lines_unit_id_idx on public.purchase_invoice_lines (unit_id);

-- ---------------------------------------------------------------------
-- تحويل الأرقام والوحدات (بلا تقريب صامت)
-- ---------------------------------------------------------------------

-- رقم عشري غير سالب من نص (الفارغ = null، والمستدعي يقرر الافتراضي)
create function private.parse_decimal(
  p_value text,
  p_label text,
  p_scale int,
  p_limit numeric,
  p_positive boolean default false
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v numeric;
begin
  if p_value is null or btrim(p_value) = '' then
    return null;
  end if;
  begin
    v := btrim(p_value)::numeric;
  exception when invalid_text_representation then
    raise exception '% "%" غير صالح', p_label, p_value;
  end;
  if v = 'NaN'::numeric or v < 0 or (p_positive and v = 0) then
    raise exception '% يجب أن يكون %', p_label,
      case when p_positive then 'أكبر من صفر' else 'صفرًا أو أكثر' end;
  end if;
  if v >= p_limit then
    raise exception '% أكبر من الحد المسموح', p_label;
  end if;
  if scale(trim_scale(v)) > p_scale then
    raise exception '% لا يزيد عن %', p_label,
      case p_scale
        when 2 then 'خانتين عشريتين'
        when 3 then 'ثلاث خانات عشرية'
        when 4 then 'أربع خانات عشرية'
        when 6 then 'ست خانات عشرية'
        else p_scale || ' خانات عشرية'
      end;
  end if;
  return v;
end;
$$;

-- وحدة السطر: فارغ = الوحدة الأساسية (معامل 1)، وإلا وحدة بديلة نشطة لنفس الصنف
create function private.resolve_unit(
  p_item_id bigint,
  p_unit_id bigint,
  p_context text,
  out unit_id bigint,
  out unit_name text,
  out factor numeric
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_unit public.item_units;
begin
  if p_unit_id is null then
    select null, i.unit, 1 into unit_id, unit_name, factor from public.items i where i.id = p_item_id;
    return;
  end if;
  select * into v_unit from public.item_units u where u.id = p_unit_id;
  if not found or v_unit.item_id <> p_item_id then
    raise exception '%الوحدة المختارة ليست من وحدات هذا الصنف', p_context;
  end if;
  if not v_unit.is_active then
    raise exception '%الوحدة % معطّلة', p_context, v_unit.name;
  end if;
  unit_id := v_unit.id;
  unit_name := v_unit.name;
  factor := v_unit.factor;
end;
$$;

-- الكمية بالوحدة الأساسية = الكمية × المعامل، ويجب أن تكون دقيقة بثلاث خانات (بلا تقريب)
create function private.to_base_qty(p_qty numeric, p_factor numeric, p_context text)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v numeric := p_qty * p_factor;
begin
  if v <> round(v, 3) then
    raise exception '%الكمية بالوحدة الأساسية (%) لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة',
      p_context, trim_scale(v);
  end if;
  if v >= 1e15 then
    raise exception '%الكمية بالوحدة الأساسية أكبر من الحد المسموح', p_context;
  end if;
  return round(v, 3);
end;
$$;

-- ---------------------------------------------------------------------
-- حماية بطاقة الصنف والوحدات (تسري على أي طريق كتابة)
-- ---------------------------------------------------------------------

-- الصنف مستخدم = له حركات أو سطور مستندات (تُضاف الوصفات والإنتاج والمبيعات في مراحلها)
create function private.item_is_used(p_item_id bigint)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.stock_movements where item_id = p_item_id)
      or exists (select 1 from public.purchase_invoice_lines where item_id = p_item_id)
      or exists (select 1 from public.stock_adjustments where item_id = p_item_id);
$$;

-- الوحدة مستخدمة = في سطر مستند (تُضاف الوصفات والإنتاج والمبيعات في مراحلها)
create function private.unit_is_used(p_unit_id bigint)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.purchase_invoice_lines where unit_id = p_unit_id);
$$;

-- النوع والوحدة الأساسية ثابتان بعد الاستخدام. قفل صف رصيد الصنف أولًا يمنع السباق مع مستند يُعتمد
-- في نفس اللحظة (دوال الاعتماد تقفل نفس الصف)، والدالة security definer لأن المستخدم لا يملك قفله.
create or replace function private.validate_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unit public.item_units;
begin
  if new.type <> old.type or new.unit <> old.unit then
    perform 1 from public.item_stock where item_id = old.id for update;
    if private.item_is_used(old.id) then
      if new.type <> old.type then
        raise exception 'لا يمكن تغيير نوع صنف عليه حركات أو مستندات';
      end if;
      raise exception 'لا يمكن تغيير الوحدة الأساسية لصنف عليه حركات أو مستندات';
    end if;
  end if;

  if new.unit <> old.unit and exists (select 1 from public.item_units where item_id = new.id and name = new.unit) then
    raise exception 'اسم الوحدة الأساسية مستخدم لوحدة بديلة لنفس الصنف';
  end if;

  if new.default_sale_unit_id is not null
     and new.default_sale_unit_id is distinct from old.default_sale_unit_id then
    select * into v_unit from public.item_units where id = new.default_sale_unit_id;
    if not v_unit.is_active then
      raise exception 'وحدة البيع الافتراضية يجب أن تكون وحدة نشطة';
    end if;
  end if;
  return new;
end;
$$;

-- الوحدة البديلة: لا تنتقل لصنف آخر، واسمها غير اسم الوحدة الأساسية، ومعاملها ثابت بعد الاستخدام،
-- ووحدة البيع الافتراضية لا تُعطَّل
create function private.validate_item_unit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.items;
begin
  if tg_op = 'UPDATE' and new.item_id <> old.item_id then
    raise exception 'لا يمكن نقل وحدة إلى صنف آخر';
  end if;

  select * into v_item from public.items where id = new.item_id;
  if new.name = v_item.unit then
    raise exception 'اسم الوحدة البديلة يجب أن يختلف عن الوحدة الأساسية (%)', v_item.unit;
  end if;

  if tg_op = 'UPDATE' and new.factor <> old.factor then
    perform 1 from public.item_stock where item_id = new.item_id for update;
    if private.unit_is_used(old.id) then
      raise exception 'لا يمكن تغيير معامل تحويل الوحدة % لأنها استُخدمت في مستندات أو وصفات', old.name;
    end if;
  end if;

  if tg_op = 'UPDATE' and old.is_active and not new.is_active and v_item.default_sale_unit_id = new.id then
    raise exception 'لا يمكن تعطيل وحدة البيع الافتراضية. اختر وحدة بيع افتراضية أخرى أولًا';
  end if;
  return new;
end;
$$;

create trigger validate_item_unit
  before insert or update on public.item_units
  for each row execute function private.validate_item_unit();

-- ---------------------------------------------------------------------
-- حفظ بطاقة الصنف ووحداتها في transaction واحدة
-- p_item: {"id","code","name","type","unit","category_id","barcode","sale_price","default_cost","min_stock","is_active"}
-- p_units: [{"id","name","factor","sale_price","is_active","is_default"}] (الوحدات البديلة فقط؛ المحذوفة تُحذف)
-- ---------------------------------------------------------------------
create function public.save_item(p_item jsonb, p_units jsonb default '[]'::jsonb)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint := nullif(p_item ->> 'id', '')::bigint;
  v_code text := btrim(coalesce(p_item ->> 'code', ''));
  v_name text := btrim(coalesce(p_item ->> 'name', ''));
  v_type text := p_item ->> 'type';
  v_unit text := btrim(coalesce(p_item ->> 'unit', ''));
  v_category bigint := nullif(p_item ->> 'category_id', '')::bigint;
  v_barcode text := nullif(btrim(coalesce(p_item ->> 'barcode', '')), '');
  v_sale_price numeric;
  v_default_cost numeric;
  v_min_stock numeric;
  v_is_active boolean := coalesce((p_item ->> 'is_active')::boolean, true);
  v_line jsonb;
  v_no int := 0;
  v_unit_id bigint;
  v_unit_name text;
  v_factor numeric;
  v_unit_price numeric;
  v_names text[] := '{}';
  v_keep bigint[] := '{}';
  v_default_count int := 0;
  v_default_id bigint;
  v_constraint text;
begin
  perform private.require_staff();

  if v_code = '' then
    raise exception 'كود الصنف مطلوب';
  end if;
  if v_name = '' then
    raise exception 'اسم الصنف مطلوب';
  end if;
  if coalesce(v_type, '') not in ('raw_material', 'packaging', 'finished_good') then
    raise exception 'اختر نوع الصنف';
  end if;
  if v_unit = '' then
    raise exception 'الوحدة الأساسية مطلوبة';
  end if;
  v_sale_price := private.parse_decimal(p_item ->> 'sale_price', 'سعر البيع', 2, 1e16);
  v_default_cost := coalesce(private.parse_decimal(p_item ->> 'default_cost', 'التكلفة الافتراضية', 4, 1e14), 0);
  v_min_stock := coalesce(private.parse_decimal(p_item ->> 'min_stock', 'الحد الأدنى للمخزون', 3, 1e15), 0);
  if jsonb_typeof(coalesce(p_units, '[]'::jsonb)) <> 'array' then
    raise exception 'وحدات الصنف غير صالحة';
  end if;

  begin
    if v_id is null then
      insert into public.items (code, name, type, unit, category_id, barcode, sale_price, default_cost, min_stock, is_active)
      values (v_code, v_name, v_type, v_unit, v_category, v_barcode, v_sale_price, v_default_cost, v_min_stock, v_is_active)
      returning id into v_id;
    else
      update public.items
      set code = v_code, name = v_name, type = v_type, unit = v_unit, category_id = v_category,
          barcode = v_barcode, sale_price = v_sale_price, default_cost = v_default_cost,
          min_stock = v_min_stock, is_active = v_is_active, default_sale_unit_id = null
      where id = v_id;
      if not found then
        raise exception 'الصنف غير موجود';
      end if;
    end if;

    -- الوحدات المحفوظة سابقًا ولم تعد في البطاقة تُحذف (المستخدمة يمنعها الارتباط فتُعطَّل بدل الحذف)
    select coalesce(array_agg(nullif(value ->> 'id', '')::bigint), '{}') into v_keep
    from jsonb_array_elements(coalesce(p_units, '[]'::jsonb))
    where nullif(value ->> 'id', '') is not null;
    delete from public.item_units where item_id = v_id and not (id = any (v_keep));

    for v_line in select value from jsonb_array_elements(coalesce(p_units, '[]'::jsonb)) loop
      v_no := v_no + 1;
      v_unit_id := nullif(v_line ->> 'id', '')::bigint;
      v_unit_name := btrim(coalesce(v_line ->> 'name', ''));
      if v_unit_name = '' then
        raise exception 'الوحدة %: اسم الوحدة مطلوب', v_no;
      end if;
      if v_unit_name = v_unit or v_unit_name = any (v_names) then
        raise exception 'الوحدة %: اسم الوحدة "%" مكرر', v_no, v_unit_name;
      end if;
      v_names := v_names || v_unit_name;
      v_factor := private.parse_decimal(v_line ->> 'factor', 'الوحدة ' || v_no || ': معامل التحويل', 6, 1e9, true);
      if v_factor is null then
        raise exception 'الوحدة %: معامل التحويل مطلوب', v_no;
      end if;
      v_unit_price := private.parse_decimal(v_line ->> 'sale_price', 'الوحدة ' || v_no || ': سعر البيع', 2, 1e16);

      if v_unit_id is null then
        insert into public.item_units (item_id, name, factor, sale_price, is_active)
        values (v_id, v_unit_name, v_factor, v_unit_price, coalesce((v_line ->> 'is_active')::boolean, true))
        returning id into v_unit_id;
      else
        update public.item_units
        set name = v_unit_name, factor = v_factor, sale_price = v_unit_price,
            is_active = coalesce((v_line ->> 'is_active')::boolean, true)
        where id = v_unit_id and item_id = v_id;
        if not found then
          raise exception 'الوحدة %: الوحدة غير موجودة لهذا الصنف', v_no;
        end if;
      end if;

      if coalesce((v_line ->> 'is_default')::boolean, false) then
        v_default_count := v_default_count + 1;
        v_default_id := v_unit_id;
      end if;
    end loop;

    if v_default_count > 1 then
      raise exception 'اختر وحدة بيع افتراضية واحدة فقط';
    end if;
    if v_default_id is not null then
      update public.items set default_sale_unit_id = v_default_id where id = v_id;
    end if;
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      raise exception '%', case v_constraint
        when 'items_code_key' then 'يوجد صنف بنفس الكود'
        when 'items_barcode_key' then 'الباركود مستخدم لصنف آخر'
        when 'item_units_item_id_name_key' then 'اسم الوحدة مكرر'
        else 'القيمة مكررة: يوجد سجل بنفس البيانات'
      end;
    when foreign_key_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint = 'items_category_id_fkey' then
        raise exception 'التصنيف غير موجود';
      end if;
      raise exception 'لا يمكن حذف وحدة استُخدمت في مستندات أو وصفات. عطّلها بدل الحذف';
  end;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- فاتورة المشتريات بالوحدات (نفس التوقيع والسلوك): لكل سطر وحدة اختيارية، والسعر لوحدة الشراء،
-- والإضافة للمخزون بالكمية الأساسية. الأصناف تُقفل قبل التحقق فتُقرأ أنواعها ووحداتها بعد القفل.
-- السطور: [{"item_id": 1, "unit_id": null, "qty": "100", "unit_price": "40"}]
-- ---------------------------------------------------------------------
create or replace function public.post_purchase_invoice(
  p_doc_date date,
  p_supplier_id bigint,
  p_lines jsonb,
  p_notes text default null,
  p_paid_amount text default null,
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
  v_unit record;
  v_qty numeric;
  v_base numeric;
  v_price numeric;
  v_total numeric;
  v_items bigint[] := '{}';
  v_lock bigint[];
  v_parsed jsonb := '[]'::jsonb;
  v_raw numeric := 0;
  v_packaging numeric := 0;
  v_sum numeric;
  v_paid numeric;
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

  -- ترتيب الأقفال: الأصناف ← عدّاد الفواتير ← عدّاد سندات الصرف ← عدّاد القيود
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
    if v_item.type not in ('raw_material', 'packaging') then
      raise exception 'السطر %: فاتورة المشتريات للخامات ومواد التعبئة فقط، والصنف % منتج تام',
        v_no, v_item.code || ' - ' || v_item.name;
    end if;
    if v_item.id = any (v_items) then
      raise exception 'السطر %: الصنف % مكرر في الفاتورة', v_no, v_item.code || ' - ' || v_item.name;
    end if;
    v_items := v_items || v_item.id;

    select * into v_unit
    from private.resolve_unit(v_item.id, nullif(v_line ->> 'unit_id', '')::bigint, 'السطر ' || v_no || ': ');
    v_qty := private.to_qty(v_line ->> 'qty', 'السطر ' || v_no || ': ');
    v_price := private.to_unit_price(v_line ->> 'unit_price', 'السطر ' || v_no || ': ');
    v_base := private.to_base_qty(v_qty, v_unit.factor, 'السطر ' || v_no || ': ');
    v_total := round(v_qty * v_price, 2);
    if v_total <= 0 then
      raise exception 'السطر %: إجمالي السطر يجب أن يكون أكبر من صفر', v_no;
    end if;
    if v_total >= 1e16 then
      raise exception 'السطر %: إجمالي السطر أكبر من الحد المسموح', v_no;
    end if;

    v_parsed := v_parsed || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'unit_id', v_unit.unit_id, 'unit_name', v_unit.unit_name, 'factor', v_unit.factor,
      'qty', v_qty, 'base_qty', v_base, 'unit_price', v_price, 'total', v_total));
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

  -- المدفوع الآن: صفر (آجل بالكامل، الافتراضي) حتى إجمالي الفاتورة، ولا يزيد عنه أبدًا
  v_paid := private.to_amount(p_paid_amount, 'المدفوع الآن: ');
  if v_paid > v_sum then
    raise exception 'المدفوع الآن % أكبر من إجمالي الفاتورة %', private.fmt_amount(v_paid), private.fmt_amount(v_sum);
  end if;
  if v_paid > 0 and p_paid_treasury_account_id is null then
    raise exception 'اختر الخزينة أو البنك المدفوع منه';
  end if;

  v_id := nextval(pg_get_serial_sequence('public.purchase_invoices', 'id'));
  v_doc_no := private.next_doc_no('purchase_invoice');
  if v_paid > 0 then
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

  -- سند الصرف بالمبلغ المدفوع فقط: م الموردين + المورد / د الخزينة أو البنك
  if v_paid > 0 then
    v_voucher_id := private.create_voucher(
      'payment', p_doc_date, p_paid_treasury_account_id, 'supplier', p_supplier_id, v_paid::text,
      case when v_paid = v_sum then 'سداد فاتورة مشتريات رقم ' else 'سداد جزئي لفاتورة مشتريات رقم ' end
        || v_doc_no
    );
  end if;

  insert into public.purchase_invoices (
    id, doc_no, doc_date, supplier_id, total, paid_amount, notes, journal_entry_id, payment_voucher_id
  )
  overriding system value
  values (v_id, v_doc_no, p_doc_date, p_supplier_id, v_sum, v_paid, v_notes, v_entry_id, v_voucher_id);

  for v_step in select value from jsonb_array_elements(v_parsed) loop
    insert into public.purchase_invoice_lines (invoice_id, item_id, unit_id, unit_name, factor, qty, unit_price, line_total)
    values (v_id, (v_step ->> 'item_id')::bigint, nullif(v_step ->> 'unit_id', '')::bigint, v_step ->> 'unit_name',
            (v_step ->> 'factor')::numeric, (v_step ->> 'qty')::numeric,
            (v_step ->> 'unit_price')::numeric, (v_step ->> 'total')::numeric);
    perform private.stock_in(
      (v_step ->> 'item_id')::bigint, (v_step ->> 'base_qty')::numeric, (v_step ->> 'total')::numeric,
      p_doc_date, 'purchase', 'purchase', v_id, v_entry_id
    );
  end loop;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- الصلاحيات و RLS
-- ---------------------------------------------------------------------
revoke execute on function
  private.parse_decimal(text, text, int, numeric, boolean),
  private.resolve_unit(bigint, bigint, text),
  private.to_base_qty(numeric, numeric, text),
  private.item_is_used(bigint),
  private.unit_is_used(bigint),
  private.validate_item(),
  private.validate_item_unit()
from public, anon, authenticated;

revoke execute on function public.save_item(jsonb, jsonb) from public, anon;
grant execute on function public.save_item(jsonb, jsonb) to authenticated;

alter table public.item_categories enable row level security;
alter table public.item_units enable row level security;

revoke all on public.item_categories, public.item_units from anon, authenticated;
revoke all on sequence public.item_categories_id_seq, public.item_units_id_seq from anon, authenticated;

-- التصنيفات: إدارة مباشرة للمدير والمحاسب (الاسم فقط). الوحدات: قراءة، والكتابة عبر save_item.
grant select, delete on public.item_categories to authenticated;
grant insert (name), update (name) on public.item_categories to authenticated;
grant select on public.item_units to authenticated;

create policy item_categories_select on public.item_categories for select to authenticated using (true);
create policy item_categories_insert on public.item_categories for insert to authenticated with check (true);
create policy item_categories_update on public.item_categories for update to authenticated using (true) with check (true);
create policy item_categories_delete on public.item_categories for delete to authenticated using (true);
create policy item_units_select on public.item_units for select to authenticated using (true);
