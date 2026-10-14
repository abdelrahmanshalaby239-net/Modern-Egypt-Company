"use server";

import { revalidatePath } from "next/cache";

import { requireAdmin } from "@/lib/auth";
import { arabicError, NOT_ALLOWED, type FormState } from "@/lib/errors";
import { formatDate, parseDate } from "@/lib/format";
import { SYSTEM_ACCOUNT_KEYS } from "@/lib/labels";

export async function saveCompany(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireAdmin();
  const values = {
    company_name: String(formData.get("company_name") ?? "").trim(),
    currency_name: String(formData.get("currency_name") ?? "").trim(),
    currency_symbol: String(formData.get("currency_symbol") ?? "").trim(),
  };
  if (!values.company_name || !values.currency_name || !values.currency_symbol) {
    return { error: "اسم الشركة واسم العملة ورمزها كلها مطلوبة." };
  }

  const { data, error } = await supabase.from("settings").update(values).eq("id", 1).select("id");
  if (error) return { error: arabicError(error) };
  if (!data.length) return { error: NOT_ALLOWED };

  revalidatePath("/", "layout");
  return { success: "تم حفظ بيانات الشركة والعملة." };
}

export async function saveLockDate(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireAdmin();
  const raw = String(formData.get("lock_date") ?? "").trim();
  const lockDate = raw ? parseDate(raw) : null;
  if (raw && !lockDate) {
    return { error: "التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة، مثل 31/12/2026." };
  }

  const { data, error } = await supabase
    .from("settings")
    .update({ lock_date: lockDate })
    .eq("id", 1)
    .select("id");
  if (error) return { error: arabicError(error) };
  if (!data.length) return { error: NOT_ALLOWED };

  revalidatePath("/settings");
  return {
    success: lockDate ? `تم تحديد تاريخ القفل: ${formatDate(lockDate)}.` : "تم إلغاء تاريخ القفل.",
  };
}

export async function saveSystemAccounts(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const { supabase } = await requireAdmin();
  const { data: current } = await supabase.from("system_accounts").select("key, account_id");
  const currentByKey = new Map((current ?? []).map((s) => [s.key, s.account_id]));

  // نحدّث المفاتيح التي تغيّرت فقط
  for (const { key, label } of SYSTEM_ACCOUNT_KEYS) {
    const accountId = Number(formData.get(key));
    if (!accountId || accountId === currentByKey.get(key)) continue;

    const { data, error } = await supabase
      .from("system_accounts")
      .update({ account_id: accountId })
      .eq("key", key)
      .select("key");
    if (error) return { error: `${label}: ${arabicError(error)}` };
    if (!data.length) return { error: NOT_ALLOWED };
  }

  revalidatePath("/settings/system-accounts");
  revalidatePath("/accounts");
  return { success: "تم حفظ حسابات النظام." };
}

export async function saveRole(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireAdmin();
  const id = String(formData.get("id") ?? "");
  const role = String(formData.get("role") ?? "");
  if (role !== "admin" && role !== "accountant") return { error: "اختر دورًا صحيحًا." };

  const { data, error } = await supabase
    .from("profiles")
    .update({ role })
    .eq("id", id)
    .select("id");
  if (error) return { error: arabicError(error) };
  if (!data.length) return { error: NOT_ALLOWED };

  revalidatePath("/settings/users");
  return { success: "تم الحفظ." };
}
