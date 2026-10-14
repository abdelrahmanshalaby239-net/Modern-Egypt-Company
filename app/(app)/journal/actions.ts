"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";

type LineInput = { account_id: string; debit: string; credit: string; description: string };

// يقرأ سطور القيد من النموذج كنصوص (بدون أي تحويل إلى أرقام)
function readLines(formData: FormData): LineInput[] | null {
  try {
    const raw = JSON.parse(String(formData.get("lines") ?? "[]"));
    if (!Array.isArray(raw)) return null;
    return raw.map((l) => ({
      account_id: String(l?.account_id ?? ""),
      debit: String(l?.debit ?? ""),
      credit: String(l?.credit ?? ""),
      description: String(l?.description ?? ""),
    }));
  } catch {
    return null;
  }
}

export async function postJournalEntry(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const entryDate = parseDate(String(formData.get("entry_date") ?? ""));
  if (!entryDate) return { error: "تاريخ القيد غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };
  const lines = readLines(formData);
  if (!lines) return { error: "سطور القيد غير صالحة." };

  const { data: entryId, error } = await supabase.rpc("post_journal_entry", {
    p_entry_date: entryDate,
    p_description: String(formData.get("description") ?? ""),
    p_source_type: String(formData.get("source_type") ?? ""),
    p_lines: lines,
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/journal");
  redirect(`/journal/${entryId}`);
}

export async function cancelJournalEntry(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const { data: reversalId, error } = await supabase.rpc("cancel_journal_entry", {
    p_entry_id: Number(formData.get("id")),
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/journal");
  revalidatePath("/inventory"); // إلغاء مخزون أول المدة يعكس حركاته
  redirect(`/journal/${reversalId}`);
}
