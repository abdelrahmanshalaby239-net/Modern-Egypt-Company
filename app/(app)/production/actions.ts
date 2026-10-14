"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";

// أمر الإنتاج وقيده وحركات المواد والمنتج تُعتمد معًا داخل post_production_order.
// الكميات والتكاليف تبقى نصوصًا حتى قاعدة البيانات.
export async function postProductionOrder(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const docDate = parseDate(String(formData.get("doc_date") ?? ""));
  if (!docDate) return { error: "تاريخ الإنتاج غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  let lines: { item_id: string; unit_id: string | null; qty: string }[];
  try {
    const raw = JSON.parse(String(formData.get("lines") ?? "[]"));
    if (!Array.isArray(raw)) throw new Error();
    lines = raw.map((l) => ({
      item_id: String(l?.item_id ?? ""),
      // فارغ = الوحدة الأساسية
      unit_id: l?.unit_id == null || l.unit_id === "" ? null : String(l.unit_id),
      qty: String(l?.qty ?? ""),
    }));
  } catch {
    return { error: "سطور الاستهلاك غير صالحة." };
  }

  const unitText = String(formData.get("unit_id") ?? "");
  // null = الوحدة الأساسية (الأنواع المولّدة لا تعرف أن المعامل يقبل null)
  const unitId = unitText ? Number(unitText) : null;
  const extraCost = String(formData.get("extra_cost") ?? "").trim();
  const { data: orderId, error } = await supabase.rpc("post_production_order", {
    p_doc_date: docDate,
    p_formula_id: Number(formData.get("formula_id")),
    p_batches: String(formData.get("batches") ?? ""),
    p_qty_produced: String(formData.get("qty_produced") ?? ""),
    p_unit_id: unitId as number,
    p_lines: lines,
    p_extra_cost: extraCost || undefined,
    p_extra_cost_account_id: Number(formData.get("extra_cost_account_id")) || undefined,
    p_notes: String(formData.get("notes") ?? ""),
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/production");
  revalidatePath("/inventory");
  redirect(`/production/${orderId}`);
}

export async function cancelProductionOrder(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const id = Number(formData.get("id"));

  const { error } = await supabase.rpc("cancel_production_order", { p_order_id: id });
  if (error) return { error: arabicError(error) };

  revalidatePath("/production");
  revalidatePath("/inventory");
  redirect(`/production/${id}`);
}
