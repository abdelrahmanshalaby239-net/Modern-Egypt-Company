"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";

// الوصفة وسطورها تُحفظ معًا داخل save_formula. الكميات تبقى نصوصًا حتى قاعدة البيانات.
export async function saveFormula(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const idText = String(formData.get("id") ?? "");
  const unitText = String(formData.get("batch_unit_id") ?? "");

  let lines: { item_id: string; unit_id: string | null; qty_per_batch: string }[];
  try {
    const raw = JSON.parse(String(formData.get("lines") ?? "[]"));
    if (!Array.isArray(raw)) throw new Error();
    lines = raw.map((l) => ({
      item_id: String(l?.item_id ?? ""),
      // فارغ = الوحدة الأساسية
      unit_id: l?.unit_id == null || l.unit_id === "" ? null : String(l.unit_id),
      qty_per_batch: String(l?.qty_per_batch ?? ""),
    }));
  } catch {
    return { error: "سطور الوصفة غير صالحة." };
  }

  // null = وصفة جديدة / الوحدة الأساسية (الأنواع المولّدة لا تعرف أن المعامل يقبل null)
  const id = idText ? Number(idText) : null;
  const batchUnitId = unitText ? Number(unitText) : null;
  const { data: formulaId, error } = await supabase.rpc("save_formula", {
    p_id: id as number,
    p_name: String(formData.get("name") ?? ""),
    p_finished_item_id: Number(formData.get("finished_item_id")),
    p_batch_qty: String(formData.get("batch_qty") ?? ""),
    p_batch_unit_id: batchUnitId as number,
    p_lines: lines,
    p_notes: String(formData.get("notes") ?? ""),
    p_is_active: formData.get("is_active") === "true",
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/formulas");
  redirect(`/formulas/${formulaId}?saved=1`);
}

// الوصفة المستخدمة في الإنتاج لا تُحذف (تُعطَّل بدل الحذف)
export async function deleteFormula(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("delete_formula", { p_id: Number(formData.get("id")) });
  if (error) return { error: arabicError(error) };

  revalidatePath("/formulas");
  redirect("/formulas");
}
