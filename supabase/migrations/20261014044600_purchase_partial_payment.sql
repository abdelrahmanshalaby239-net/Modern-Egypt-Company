-- =====================================================================
-- المرحلة 4 (تعديل): سداد فاتورة المشتريات بالكامل أو جزئيًا أو آجل بالكامل.
-- المدفوع الآن من صفر حتى إجمالي الفاتورة. الفاتورة كلها على حساب المورد، وسند صرف بالمبلغ المدفوع
-- فقط (لا سند لو المدفوع صفر) داخل نفس الـ transaction. paid_amount = المدفوع عند الاعتماد (تاريخي).
-- =====================================================================

alter table public.purchase_invoices
  add column paid_amount numeric(18, 2) not null default 0;

-- لا توجد فواتير مدفوعة قبل هذا الترحيل (لم يُستخدم النظام بعد). لو وُجدت يتوقف الترحيل بدل أن
-- يترك المدفوع صفرًا لفاتورة لها سند.
do $$
begin
  if exists (select 1 from public.purchase_invoices where payment_voucher_id is not null) then
    raise exception 'توجد فواتير مشتريات مدفوعة: املأ paid_amount من مبالغ سنداتها قبل هذا الترحيل';
  end if;
end $$;

alter table public.purchase_invoices
  add constraint purchase_invoices_paid_amount_range check (paid_amount >= 0 and paid_amount <= total),
  add constraint purchase_invoices_paid_has_voucher check ((paid_amount > 0) = (payment_voucher_id is not null));

-- ---------------------------------------------------------------------
-- فاتورة المشتريات (خامات ومواد تعبئة فقط): م المخزون حسب نوع الصنف / د الموردين + المورد بكامل
-- الإجمالي، وحركات إضافة بمتوسط مرجح جديد. المدفوع الآن (صفر حتى الإجمالي) يُسجَّل بسند صرف مربوط.
-- السطور: [{"item_id": 1, "qty": "100", "unit_price": "40"}]
-- ---------------------------------------------------------------------
drop function public.post_purchase_invoice(date, bigint, jsonb, text, bigint);

create function public.post_purchase_invoice(
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
  v_qty numeric;
  v_price numeric;
  v_total numeric;
  v_items bigint[] := '{}';
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

  -- المدفوع الآن: صفر (آجل بالكامل، الافتراضي) حتى إجمالي الفاتورة، ولا يزيد عنه أبدًا
  v_paid := private.to_amount(p_paid_amount, 'المدفوع الآن: ');
  if v_paid > v_sum then
    raise exception 'المدفوع الآن % أكبر من إجمالي الفاتورة %', private.fmt_amount(v_paid), private.fmt_amount(v_sum);
  end if;
  if v_paid > 0 and p_paid_treasury_account_id is null then
    raise exception 'اختر الخزينة أو البنك المدفوع منه';
  end if;

  -- ترتيب الأقفال: الأصناف ← عدّاد الفواتير ← عدّاد سندات الصرف ← عدّاد القيود
  perform private.lock_items(v_items);
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

-- قائمة فواتير المشتريات: المدفوع عند الاعتماد (لا يتغير بسندات لاحقة غير مخصصة للفاتورة)
drop function public.purchase_invoice_list(date, date, text);

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
  paid_amount text,
  notes text,
  journal_entry_id bigint,
  payment_voucher_id bigint,
  is_cancelled boolean
)
language sql
stable
set search_path = ''
as $$
  select p.id, p.doc_no, p.doc_date, s.name, p.total::text, p.paid_amount::text, p.notes, p.journal_entry_id,
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

revoke execute on function
  public.post_purchase_invoice(date, bigint, jsonb, text, text, bigint),
  public.purchase_invoice_list(date, date, text)
from public, anon;

grant execute on function
  public.post_purchase_invoice(date, bigint, jsonb, text, text, bigint),
  public.purchase_invoice_list(date, date, text)
to authenticated;
