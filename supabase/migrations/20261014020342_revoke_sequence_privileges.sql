-- =====================================================================
-- المرحلة 2 (تحقق): لا صلاحيات على الـ sequences لمستخدمي الـ API
-- كانت موروثة من الصلاحيات الافتراضية في Supabase (anon: USAGE/SELECT/UPDATE).
-- أعمدة identity لا تحتاج صلاحية على الـ sequence عند الإضافة.
-- =====================================================================
revoke all on sequence
  public.accounts_id_seq,
  public.journal_entries_id_seq,
  public.journal_lines_id_seq
from anon, authenticated;
