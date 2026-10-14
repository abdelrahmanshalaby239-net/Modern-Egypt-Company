"use server";

import { revalidatePath } from "next/cache";

import { requireAdmin } from "@/lib/auth";
import { arabicError, NOT_ALLOWED, type FormState } from "@/lib/errors";
import { SYSTEM_ACCOUNT_KEYS } from "@/lib/labels";

// بيانات الشركة فقط (تظهر في رأس الفواتير المطبوعة). العملة ثابتة، وتاريخ القفل يحدّثه القفل الشهري وإقفال السنة (شاشة إقفال السنة).
export async function saveCompany(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireAdmin();
  const text = (name: string) => String(formData.get(name) ?? "").trim();
  const values = {
    company_name: text("company_name"),
    company_address: text("company_address") || null,
    company_phone: text("company_phone") || null,
  };
  if (!values.company_name) return { error: "اسم الشركة مطلوب." };

  const { data, error } = await supabase.from("settings").update(values).eq("id", 1).select("id");
  if (error) return { error: arabicError(error) };
  if (!data.length) return { error: NOT_ALLOWED };

  revalidatePath("/", "layout");
  return { success: "تم حفظ بيانات الشركة." };
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
