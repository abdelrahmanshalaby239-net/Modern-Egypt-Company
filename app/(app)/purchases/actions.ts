"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";

// الفاتورة وقيدها وحركات المخزون وسند الصرف (لو المدفوع الآن أكبر من صفر) تُعتمد معًا داخل
// post_purchase_invoice. الكميات والأسعار والمدفوع تبقى نصوصًا حتى قاعدة البيانات.
export async function postPurchaseInvoice(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const docDate = parseDate(String(formData.get("doc_date") ?? ""));
  if (!docDate) return { error: "تاريخ الفاتورة غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  let lines: { item_id: string; qty: string; unit_price: string }[];
  try {
    const raw = JSON.parse(String(formData.get("lines") ?? "[]"));
    if (!Array.isArray(raw)) throw new Error();
    lines = raw.map((l) => ({
      item_id: String(l?.item_id ?? ""),
      qty: String(l?.qty ?? ""),
      unit_price: String(l?.unit_price ?? ""),
    }));
  } catch {
    return { error: "سطور الفاتورة غير صالحة." };
  }

  const paidAmount = String(formData.get("paid_amount") ?? "").trim();
  const paidFrom = Number(formData.get("paid_treasury_account_id")) || undefined;
  const { data: invoiceId, error } = await supabase.rpc("post_purchase_invoice", {
    p_doc_date: docDate,
    p_supplier_id: Number(formData.get("supplier_id")),
    p_lines: lines,
    p_notes: String(formData.get("notes") ?? ""),
    p_paid_amount: paidAmount || undefined,
    p_paid_treasury_account_id: paidFrom,
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/purchases");
  revalidatePath("/inventory");
  redirect(`/purchases/${invoiceId}`);
}

export async function cancelPurchaseInvoice(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const id = Number(formData.get("id"));

  const { error } = await supabase.rpc("cancel_purchase_invoice", { p_invoice_id: id });
  if (error) return { error: arabicError(error) };

  revalidatePath("/purchases");
  revalidatePath("/inventory");
  redirect(`/purchases/${id}`);
}
