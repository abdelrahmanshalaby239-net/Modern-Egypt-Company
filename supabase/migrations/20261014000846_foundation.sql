-- =====================================================================
-- المرحلة 1: الأساس — المستخدمون والأدوار، الإعدادات، دليل الحسابات
-- =====================================================================

-- الدوال المساعدة في schema غير مكشوفة للـ API
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------
-- profiles: مستخدم لكل صف في auth.users
-- ---------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  full_name text,
  role text not null default 'accountant' check (role in ('admin', 'accountant')),
  created_at timestamptz not null default now()
);

-- ينشئ profile بدور accountant لكل مستخدم جديد
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- هل المستخدم الحالي admin؟ (security definer لتجنّب تكرار RLS على profiles)
create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

-- لا يغيّر المستخدم دوره بنفسه (يمنع أن يفقد النظام آخر admin بالخطأ)
create function private.guard_profile_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.role is distinct from old.role and new.id = (select auth.uid()) then
    raise exception 'لا يمكنك تغيير دورك بنفسك';
  end if;
  return new;
end;
$$;

create trigger guard_profile_role
  before update on public.profiles
  for each row execute function private.guard_profile_role();

-- ---------------------------------------------------------------------
-- settings: صف واحد
-- ---------------------------------------------------------------------
create table public.settings (
  id smallint primary key default 1 check (id = 1),
  company_name text not null check (btrim(company_name) <> ''),
  currency_name text not null check (btrim(currency_name) <> ''),
  currency_symbol text not null check (btrim(currency_symbol) <> ''),
  lock_date date
);

-- ---------------------------------------------------------------------
-- accounts: دليل الحسابات
-- ---------------------------------------------------------------------
create table public.accounts (
  id bigint generated always as identity primary key,
  code text not null unique,
  name text not null,
  type text not null check (type in ('asset', 'liability', 'equity', 'revenue', 'expense')),
  parent_id bigint references public.accounts (id),
  is_postable boolean not null default true,
  is_active boolean not null default true,
  is_treasury boolean not null default false,
  created_at timestamptz not null default now()
);

create index accounts_parent_id_idx on public.accounts (parent_id);

-- ---------------------------------------------------------------------
-- system_accounts: ربط مفاتيح النظام بالحسابات
-- ---------------------------------------------------------------------
create table public.system_accounts (
  key text primary key check (key in (
    'receivables', 'payables', 'inventory_raw', 'inventory_packaging',
    'inventory_finished', 'sales_revenue', 'cogs', 'capital',
    'retained_earnings', 'inventory_adjustment'
  )),
  account_id bigint not null references public.accounts (id)
);

create index system_accounts_account_id_idx on public.system_accounts (account_id);

-- قواعد دليل الحسابات برسائل عربية
create function private.validate_account()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent public.accounts;
  v_is_system boolean;
  v_has_children boolean;
begin
  if new.code is null or new.code !~ '^[0-9]+$' then
    raise exception 'كود الحساب يجب أن يكون أرقامًا فقط';
  end if;

  if new.name is null or btrim(new.name) = '' then
    raise exception 'اسم الحساب مطلوب';
  end if;

  if new.parent_id is not null then
    select * into v_parent from public.accounts where id = new.parent_id;
    if v_parent.is_postable then
      raise exception 'الحساب الأب يجب أن يكون حسابًا تجميعيًا (غير قابل للترحيل)';
    end if;
    if v_parent.type <> new.type then
      raise exception 'نوع الحساب يجب أن يطابق نوع الحساب الأب';
    end if;
  end if;

  if new.is_treasury and not (new.type = 'asset' and new.is_postable) then
    raise exception 'الخزينة أو البنك يجب أن يكون حساب أصول قابلًا للترحيل';
  end if;

  if tg_op = 'UPDATE' then
    v_has_children := exists (select 1 from public.accounts where parent_id = new.id);
    v_is_system := exists (select 1 from public.system_accounts where account_id = new.id);

    if new.parent_id is distinct from old.parent_id and new.parent_id is not null
       and exists (
         with recursive sub as (
           select id from public.accounts where id = new.id
           union all
           select a.id from public.accounts a join sub on a.parent_id = sub.id
         )
         select 1 from sub where id = new.parent_id
       ) then
      raise exception 'لا يمكن جعل الحساب تابعًا لنفسه أو لأحد حساباته الفرعية';
    end if;

    if v_has_children and new.is_postable then
      raise exception 'لا يمكن جعل حساب له حسابات فرعية قابلًا للترحيل';
    end if;

    if v_has_children and new.type <> old.type then
      raise exception 'لا يمكن تغيير نوع حساب له حسابات فرعية';
    end if;

    if v_is_system then
      if not new.is_active then
        raise exception 'لا يمكن تعطيل حساب نظام';
      end if;
      if not new.is_postable then
        raise exception 'حساب النظام يجب أن يبقى قابلًا للترحيل';
      end if;
      if new.type <> old.type then
        raise exception 'لا يمكن تغيير نوع حساب نظام';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger validate_account
  before insert or update on public.accounts
  for each row execute function private.validate_account();

create function private.guard_account_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from public.system_accounts where account_id = old.id) then
    raise exception 'لا يمكن حذف حساب نظام';
  end if;
  if exists (select 1 from public.accounts where parent_id = old.id) then
    raise exception 'لا يمكن حذف حساب له حسابات فرعية';
  end if;
  return old;
end;
$$;

create trigger guard_account_delete
  before delete on public.accounts
  for each row execute function private.guard_account_delete();

create function private.validate_system_account()
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
  return new;
end;
$$;

create trigger validate_system_account
  before insert or update on public.system_accounts
  for each row execute function private.validate_system_account();

-- ---------------------------------------------------------------------
-- صلاحيات الدوال
-- ---------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_admin() to authenticated;

-- ---------------------------------------------------------------------
-- RLS والصلاحيات: بدون سياسة = بدون وصول. anon لا يصل لشيء.
-- ---------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.settings enable row level security;
alter table public.accounts enable row level security;
alter table public.system_accounts enable row level security;

revoke all on public.profiles, public.settings, public.accounts, public.system_accounts
  from anon, authenticated;

-- profiles: المستخدم يرى صفه، وadmin يرى الكل ويغيّر الدور فقط
grant select on public.profiles to authenticated;
grant update (role) on public.profiles to authenticated;

create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));

create policy profiles_update_admin on public.profiles
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- settings: قراءة للجميع، تعديل لـ admin
grant select, update on public.settings to authenticated;

create policy settings_select on public.settings
  for select to authenticated
  using (true);

create policy settings_update_admin on public.settings
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- accounts: admin وaccountant
grant select, insert, update, delete on public.accounts to authenticated;

create policy accounts_select on public.accounts
  for select to authenticated
  using (true);

create policy accounts_insert on public.accounts
  for insert to authenticated
  with check (true);

create policy accounts_update on public.accounts
  for update to authenticated
  using (true)
  with check (true);

create policy accounts_delete on public.accounts
  for delete to authenticated
  using (true);

-- system_accounts: قراءة للجميع، تغيير الربط لـ admin
grant select on public.system_accounts to authenticated;
grant update (account_id) on public.system_accounts to authenticated;

create policy system_accounts_select on public.system_accounts
  for select to authenticated
  using (true);

create policy system_accounts_update_admin on public.system_accounts
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));
