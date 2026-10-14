"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";

export async function postPartyOpeningBalances(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const entryDate = parseDate(String(formData.get("entry_date") ?? ""));
  if (!entryDate) return { error: "التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  let lines: { customer_id: string; supplier_id: string; debit: string; credit: string }[];
  try {
    const raw = JSON.parse(String(formData.get("lines") ?? "[]"));
    if (!Array.isArray(raw)) throw new Error();
    // المبالغ والمعرّفات تبقى نصوصًا حتى قاعدة البيانات
    lines = raw.map((l) => ({
      customer_id: String(l?.customer_id ?? ""),
      supplier_id: String(l?.supplier_id ?? ""),
      debit: String(l?.debit ?? ""),
      credit: String(l?.credit ?? ""),
    }));
  } catch {
    return { error: "الأرصدة غير صالحة." };
  }

  const { data: entryId, error } = await supabase.rpc("post_party_opening_balances", {
    p_entry_date: entryDate,
    p_lines: lines,
    p_difference_to_capital: formData.get("difference_to_capital") === "true",
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/opening-balances/parties");
  revalidatePath("/journal");
  revalidatePath("/customers");
  revalidatePath("/suppliers");
  redirect(`/journal/${entryId}`);
}
