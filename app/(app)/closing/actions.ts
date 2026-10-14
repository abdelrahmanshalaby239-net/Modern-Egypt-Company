"use server";

import { revalidatePath } from "next/cache";

import { requireAdmin } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { formatDate, parseDate } from "@/lib/format";

// السنة المالية والقفل والإقفال كلها في دوال قاعدة البيانات (المدير فقط، والفرض هناك)
export async function saveFiscalYear(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireAdmin();
  const start = parseDate(String(formData.get("start_date") ?? ""));
  const end = parseDate(String(formData.get("end_date") ?? ""));
  if (!start || !end) return { error: "التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  const { error } = await supabase.rpc("save_open_fiscal_year", {
    p_name: String(formData.get("name") ?? ""),
    p_start: start,
    p_end: end,
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/", "layout");
  return { success: "تم حفظ السنة المالية." };
}

export async function lockPeriod(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireAdmin();
  const date = parseDate(String(formData.get("lock_date") ?? ""));
  if (!date) return { error: "التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  const { error } = await supabase.rpc("lock_period", { p_date: date });
  if (error) return { error: arabicError(error) };

  revalidatePath("/", "layout");
  return { success: `تم قفل الفترة حتى ${formatDate(date)}.` };
}

export async function closeFiscalYear(): Promise<FormState> {
  const { supabase } = await requireAdmin();
  const { error } = await supabase.rpc("close_fiscal_year");
  if (error) return { error: arabicError(error) };

  revalidatePath("/", "layout");
  return { success: "تم إقفال السنة المالية، وفُتحت السنة التالية." };
}
