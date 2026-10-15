-- =====================================================================
-- تحذير advisor (0028 و0029): الدالة public.rls_auto_enable() من Supabase (يستدعيها event trigger
-- ensure_rls ليفعّل RLS على الجداول الجديدة في public) قابلة للتنفيذ لـ PUBLIC و anon و authenticated.
-- لا يحتاجها أي مستخدم: الـ event trigger يعمل بدون صلاحية التنفيذ لمن ينفّذ الـ DDL (اختُبر)، والمالك
-- postgres و service_role يبقيان كما هما. سحب صلاحية فقط، بلا حذف ولا تعديل للدالة أو الـ trigger.
-- مشروط بوجود الدالة حتى يعمل الترحيل على قواعد لا توجد فيها.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;
