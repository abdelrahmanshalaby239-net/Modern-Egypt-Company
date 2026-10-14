"use server";

import { revalidatePath } from "next/cache";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { isItemType } from "@/lib/labels";
import { parseCents, plainCents } from "@/lib/money";

export async function saveItem(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const id = Number(formData.get("id")) || null;
  const text = (key: string) => String(formData.get(key) ?? "").trim();
  const code = text("code");
  const name = text("name");
  const type = text("type");
  const unit = text("unit");
  if (!code) return { error: "كود الصنف مطلوب." };
  if (!name) return { error: "اسم الصنف مطلوب." };
  if (!isItemType(type)) return { error: "اختر نوع الصنف." };
  if (!unit) return { error: "وحدة القياس مطلوبة." };

  const salePriceText = text("sale_price");
  const salePrice = salePriceText ? parseCents(salePriceText) : null;
  if (salePriceText && salePrice === null) {
    return { error: "سعر البيع غير صالح (رقم موجب بخانتين عشريتين كحد أقصى)." };
  }

  const values = {
    code,
    name,
    type,
    unit,
    // numeric(18,2) يُرسل نصًا حتى لا يمر المبلغ بـ Number (قاعدة البيانات تحوّله)
    sale_price: salePrice === null ? null : (plainCents(salePrice) as unknown as number),
    is_active: id ? formData.get("is_active") === "on" : true,
  };

  const { error } = id
    ? await supabase.from("items").update(values).eq("id", id)
    : await supabase.from("items").insert(values);
  if (error) {
    if (error.code === "23505") return { error: "يوجد صنف بنفس الكود." };
    return { error: arabicError(error) };
  }

  revalidatePath("/items");
  return { success: id ? "تم حفظ التعديلات." : "تمت إضافة الصنف." };
}

export async function deleteItem(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const { error } = await supabase.from("items").delete().eq("id", Number(formData.get("id")));
  if (error) {
    if (error.code === "23503") {
      return { error: "لا يمكن حذف صنف عليه حركات أو مستندات. يمكنك تعطيله بدل الحذف." };
    }
    return { error: arabicError(error) };
  }

  revalidatePath("/items");
  return { success: "تم الحذف." };
}
