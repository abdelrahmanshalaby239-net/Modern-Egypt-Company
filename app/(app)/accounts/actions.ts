"use server";

import { revalidatePath } from "next/cache";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { ACCOUNT_TYPES, type AccountType } from "@/lib/labels";

export async function saveAccount(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const id = Number(formData.get("id")) || null;
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const parentId = Number(formData.get("parent_id")) || null;
  let type = String(formData.get("type") ?? "");

  if (!/^\d+$/.test(code)) return { error: "كود الحساب مطلوب ويجب أن يكون أرقامًا فقط." };
  if (!name) return { error: "اسم الحساب مطلوب." };

  // نوع الحساب الفرعي يُورَث من الأب
  if (parentId) {
    const { data: parent } = await supabase
      .from("accounts")
      .select("type")
      .eq("id", parentId)
      .single();
    if (!parent) return { error: "الحساب الأب غير موجود." };
    type = parent.type;
  }
  if (!ACCOUNT_TYPES.includes(type as AccountType)) return { error: "اختر نوع الحساب." };

  const values = {
    code,
    name,
    type,
    parent_id: parentId,
    is_postable: formData.get("is_postable") === "on",
    is_treasury: formData.get("is_treasury") === "on",
    is_active: id ? formData.get("is_active") === "on" : true,
  };

  const { error } = id
    ? await supabase.from("accounts").update(values).eq("id", id)
    : await supabase.from("accounts").insert(values);
  if (error) return { error: arabicError(error) };

  revalidatePath("/accounts");
  return { success: id ? "تم حفظ التعديلات." : "تمت إضافة الحساب." };
}

export async function deleteAccount(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const id = Number(formData.get("id"));

  const { error } = await supabase.from("accounts").delete().eq("id", id);
  if (error) return { error: arabicError(error) };

  revalidatePath("/accounts");
  return { success: "تم حذف الحساب." };
}
