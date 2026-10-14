"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";

export async function postStockOpening(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const entryDate = parseDate(String(formData.get("entry_date") ?? ""));
  if (!entryDate) return { error: "التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  let lines: { item_id: string; qty: string; unit_cost: string }[];
  try {
    const raw = JSON.parse(String(formData.get("lines") ?? "[]"));
    if (!Array.isArray(raw)) throw new Error();
    // الكميات والتكاليف تبقى نصوصًا حتى قاعدة البيانات
    lines = raw.map((l) => ({
      item_id: String(l?.item_id ?? ""),
      qty: String(l?.qty ?? ""),
      unit_cost: String(l?.unit_cost ?? ""),
    }));
  } catch {
    return { error: "الأرصدة غير صالحة." };
  }

  const { data: entryId, error } = await supabase.rpc("post_stock_opening", {
    p_entry_date: entryDate,
    p_lines: lines,
    p_difference_to_capital: formData.get("difference_to_capital") === "true",
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/opening-balances/inventory");
  revalidatePath("/journal");
  revalidatePath("/inventory");
  redirect(`/journal/${entryId}`);
}
