-- =====================================================================
-- المرحلة 1 (تعديل): بيانات الشركة للمطبوعات، عملة واحدة ثابتة،
-- وتاريخ القفل لا يُعدَّل من الواجهة (يحدّثه إقفال السنة في المرحلة 7)
-- =====================================================================

alter table public.settings
  add column company_address text,
  add column company_phone text,
  alter column currency_name set default 'جنيه مصري',
  alter column currency_symbol set default 'ج.م';

-- المستخدم يعدّل بيانات الشركة فقط. العملة وتاريخ القفل لا تُعدَّل من الـ API.
revoke update on public.settings from authenticated;
grant update (company_name, company_address, company_phone) on public.settings to authenticated;
