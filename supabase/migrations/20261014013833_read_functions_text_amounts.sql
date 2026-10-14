-- =====================================================================
-- المرحلة 2: دوال القراءة العامة تُرجع المبالغ نصًا
-- PostgREST يُرجع numeric كرقم JSON فيتحول إلى float في JavaScript.
-- الحساب يبقى في الدوال الأصلية (numeric) بعد نقلها إلى private،
-- والدوال العامة بنفس الأسماء تُرجع نفس الصفوف والمبالغ نصًا بخانتين.
-- =====================================================================

alter function public.account_statement(bigint, date, date) set schema private;
alter function public.trial_balance(date) set schema private;
alter function public.journal_entry_list(date, date, text) set schema private;

-- الدوال العامة SECURITY INVOKER، فتحتاج تنفيذ الدوال الداخلية (RLS يسري كما هو)
grant execute on function
  private.account_statement(bigint, date, date),
  private.trial_balance(date),
  private.journal_entry_list(date, date, text)
to authenticated;

create function public.account_statement(
  p_account_id bigint,
  p_from date default null,
  p_to date default null
)
returns table (
  entry_id bigint,
  entry_no bigint,
  entry_date date,
  source_type text,
  description text,
  debit text,
  credit text,
  balance text
)
language sql
stable
set search_path = ''
as $$
  select s.entry_id, s.entry_no, s.entry_date, s.source_type, s.description,
         round(s.debit, 2)::text, round(s.credit, 2)::text, round(s.balance, 2)::text
  from private.account_statement(p_account_id, p_from, p_to)
       with ordinality as s (entry_id, entry_no, entry_date, source_type, description,
                             debit, credit, balance, ord)
  order by s.ord;
$$;

create function public.trial_balance(p_as_of date default null)
returns table (
  account_id bigint,
  code text,
  name text,
  type text,
  debit text,
  credit text
)
language sql
stable
set search_path = ''
as $$
  select t.account_id, t.code, t.name, t.type, round(t.debit, 2)::text, round(t.credit, 2)::text
  from private.trial_balance(p_as_of)
       with ordinality as t (account_id, code, name, type, debit, credit, ord)
  order by t.ord;
$$;

create function public.journal_entry_list(
  p_from date default null,
  p_to date default null,
  p_search text default null
)
returns table (
  id bigint,
  entry_no bigint,
  entry_date date,
  source_type text,
  description text,
  total text,
  reverses_entry_id bigint,
  reversed_by_entry_id bigint
)
language sql
stable
set search_path = ''
as $$
  select j.id, j.entry_no, j.entry_date, j.source_type, j.description, round(j.total, 2)::text,
         j.reverses_entry_id, j.reversed_by_entry_id
  from private.journal_entry_list(p_from, p_to, p_search)
       with ordinality as j (id, entry_no, entry_date, source_type, description, total,
                             reverses_entry_id, reversed_by_entry_id, ord)
  order by j.ord;
$$;

revoke execute on function
  public.account_statement(bigint, date, date),
  public.trial_balance(date),
  public.journal_entry_list(date, date, text)
from public, anon;

grant execute on function
  public.account_statement(bigint, date, date),
  public.trial_balance(date),
  public.journal_entry_list(date, date, text)
to authenticated;
