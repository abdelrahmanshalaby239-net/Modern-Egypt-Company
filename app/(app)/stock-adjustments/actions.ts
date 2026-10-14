"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";

// التسوية وقيدها وحركة المخزون تُعتمد معًا داخل post_stock_adjustment. الكمية تبقى نصًا.
export async function postStockAdjustment(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const docDate = parseDate(String(formData.get("doc_date") ?? ""));
  if (!docDate) return { error: "تاريخ التسوية غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  const { data: adjustmentId, error } = await supabase.rpc("post_stock_adjustment", {
    p_doc_date: docDate,
    p_item_id: Number(formData.get("item_id")),
    p_counted_qty: String(formData.get("counted_qty") ?? ""),
    p_notes: String(formData.get("notes") ?? ""),
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/stock-adjustments");
  revalidatePath("/inventory");
  redirect(`/stock-adjustments/${adjustmentId}`);
}

export async function cancelStockAdjustment(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const id = Number(formData.get("id"));

  const { error } = await supabase.rpc("cancel_stock_adjustment", { p_adjustment_id: id });
  if (error) return { error: arabicError(error) };

  revalidatePath("/stock-adjustments");
  revalidatePath("/inventory");
  redirect(`/stock-adjustments/${id}`);
}
