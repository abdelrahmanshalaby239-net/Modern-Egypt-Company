"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";

type UnitInput = { id: string; name: string; factor: string; sale_price: string; is_active: boolean; is_default: boolean };

// حفظ بطاقة الصنف ووحداتها معًا في دالة واحدة بقاعدة البيانات (save_item): القواعد كلها هناك
export async function saveItem(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  let item: Record<string, unknown>;
  let units: UnitInput[];
  try {
    item = JSON.parse(String(formData.get("item") ?? "{}"));
    units = JSON.parse(String(formData.get("units") ?? "[]"));
  } catch {
    return { error: "بيانات الصنف غير صالحة." };
  }
  if (typeof item !== "object" || item === null || !Array.isArray(units)) {
    return { error: "بيانات الصنف غير صالحة." };
  }

  const text = (v: unknown) => (v == null ? "" : String(v).trim());
  const { data: id, error } = await supabase.rpc("save_item", {
    p_item: {
      id: text(item.id) || null,
      code: text(item.code),
      name: text(item.name),
      type: text(item.type),
      unit: text(item.unit),
      category_id: text(item.category_id) || null,
      barcode: text(item.barcode) || null,
      sale_price: text(item.sale_price) || null,
      default_cost: text(item.default_cost) || null,
      min_stock: text(item.min_stock) || null,
      is_active: item.is_active !== false,
    },
    p_units: units.map((u) => ({
      id: text(u.id) || null,
      name: text(u.name),
      factor: text(u.factor),
      sale_price: text(u.sale_price) || null,
      is_active: u.is_active !== false,
      is_default: u.is_default === true,
    })),
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/items");
  redirect(`/items/${id}?saved=1`);
}

export async function deleteItem(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const { error } = await supabase.from("items").delete().eq("id", Number(formData.get("id")));
  if (error) {
    if (error.code === "23503") {
      return { error: "لا يمكن حذف صنف عليه حركات أو مستندات أو وصفات. يمكنك تعطيله بدل الحذف." };
    }
    return { error: arabicError(error) };
  }

  revalidatePath("/items");
  return { success: "تم الحذف." };
}

// التصنيفات: اسم فقط، والحذف مسموح لتصنيف بلا أصناف
export async function saveCategory(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const id = Number(formData.get("id")) || null;
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return { error: "اسم التصنيف مطلوب." };

  const { error } = id
    ? await supabase.from("item_categories").update({ name }).eq("id", id)
    : await supabase.from("item_categories").insert({ name });
  if (error) {
    if (error.code === "23505") return { error: "يوجد تصنيف بنفس الاسم." };
    return { error: arabicError(error) };
  }

  revalidatePath("/items", "layout");
  return { success: id ? "تم حفظ التعديل." : "تمت إضافة التصنيف." };
}

export async function deleteCategory(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const { error } = await supabase.from("item_categories").delete().eq("id", Number(formData.get("id")));
  if (error) {
    if (error.code === "23503") return { error: "لا يمكن حذف تصنيف عليه أصناف. انقل أصنافه لتصنيف آخر أولًا." };
    return { error: arabicError(error) };
  }

  revalidatePath("/items", "layout");
  return { success: "تم الحذف." };
}
