-- =====================================================================
-- البيانات الأولية: الإعدادات + دليل الحسابات الافتتاحي + حسابات النظام
-- آمن لإعادة التشغيل (on conflict do nothing)
-- =====================================================================

insert into public.settings (id, company_name, currency_name, currency_symbol)
values (1, 'شركة مصر الحديثة للمبيدات والمنظفات', 'جنيه مصري', 'ج.م')
on conflict (id) do nothing;

-- المجموعات الرئيسية (غير قابلة للترحيل)
insert into public.accounts (code, name, type, is_postable)
values
  ('1000', 'الأصول', 'asset', false),
  ('2000', 'الخصوم', 'liability', false),
  ('3000', 'حقوق الملكية', 'equity', false),
  ('4000', 'الإيرادات', 'revenue', false),
  ('5000', 'تكلفة المبيعات', 'expense', false),
  ('6000', 'المصروفات', 'expense', false)
on conflict (code) do nothing;

-- الحسابات الفرعية (قابلة للترحيل)، والنوع يُورَث من المجموعة
insert into public.accounts (code, name, type, parent_id, is_treasury)
select v.code, v.name, p.type, p.id, v.is_treasury
from (
  values
    ('1101', 'الخزينة الرئيسية', '1000', true),
    ('1102', 'البنك', '1000', true),
    ('1201', 'العملاء', '1000', false),
    ('1301', 'مخزون مواد خام', '1000', false),
    ('1302', 'مخزون مواد تعبئة وتغليف', '1000', false),
    ('1303', 'مخزون منتج تام', '1000', false),
    ('1401', 'مصروفات مدفوعة مقدمًا', '1000', false),
    ('1501', 'آلات ومعدات', '1000', false),
    ('1502', 'سيارات ووسائل نقل', '1000', false),
    ('1503', 'أثاث وتجهيزات', '1000', false),
    ('1509', 'مجمع إهلاك الأصول الثابتة', '1000', false),
    ('2101', 'الموردين', '2000', false),
    ('2201', 'مصروفات وأجور مستحقة', '2000', false),
    ('2301', 'قروض', '2000', false),
    ('3101', 'رأس المال', '3000', false),
    ('3201', 'جاري الشركاء', '3000', false),
    ('3301', 'الأرباح المرحّلة', '3000', false),
    ('4101', 'إيرادات المبيعات', '4000', false),
    ('4201', 'إيرادات أخرى', '4000', false),
    ('5101', 'تكلفة البضاعة المباعة', '5000', false),
    ('5201', 'فروقات جرد المخزون', '5000', false),
    ('6101', 'أجور ومرتبات', '6000', false),
    ('6201', 'كهرباء ومياه وغاز', '6000', false),
    ('6301', 'إيجارات', '6000', false),
    ('6401', 'صيانة', '6000', false),
    ('6501', 'نقل وشحن', '6000', false),
    ('6601', 'تسويق ودعاية', '6000', false),
    ('6701', 'مصروفات إدارية وعمومية', '6000', false),
    ('6801', 'مصروف الإهلاك', '6000', false),
    ('6901', 'مصروفات أخرى', '6000', false)
) as v (code, name, parent_code, is_treasury)
join public.accounts p on p.code = v.parent_code
on conflict (code) do nothing;

-- ربط مفاتيح النظام
insert into public.system_accounts (key, account_id)
select v.key, a.id
from (
  values
    ('receivables', '1201'),
    ('payables', '2101'),
    ('inventory_raw', '1301'),
    ('inventory_packaging', '1302'),
    ('inventory_finished', '1303'),
    ('sales_revenue', '4101'),
    ('cogs', '5101'),
    ('capital', '3101'),
    ('retained_earnings', '3301'),
    ('inventory_adjustment', '5201')
) as v (key, code)
join public.accounts a on a.code = v.code
on conflict (key) do nothing;
