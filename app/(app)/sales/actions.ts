"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";

// الفاتورة وقيدها وتكلفة المبيعات وحركات المخزون وسند القبض (لو المقبوض الآن أكبر من صفر) تُعتمد معًا
// داخل post_sales_invoice. الكميات والأسعار والمقبوض تبقى نصوصًا حتى قاعدة البيانات.
export async function postSalesInvoice(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const docDate = parseDate(String(formData.get("doc_date") ?? ""));
  if (!docDate) return { error: "تاريخ الفاتورة غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  let lines: { item_id: string; unit_id: string | null; qty: string; unit_price: string }[];
  try {
    const raw = JSON.parse(String(formData.get("lines") ?? "[]"));
    if (!Array.isArray(raw)) throw new Error();
    lines = raw.map((l) => ({
      item_id: String(l?.item_id ?? ""),
      // فارغ = الوحدة الأساسية
      unit_id: l?.unit_id == null || l.unit_id === "" ? null : String(l.unit_id),
      qty: String(l?.qty ?? ""),
      unit_price: String(l?.unit_price ?? ""),
    }));
  } catch {
    return { error: "سطور الفاتورة غير صالحة." };
  }

  const received = String(formData.get("received_amount") ?? "").trim();
  const receivedIn = Number(formData.get("received_treasury_account_id")) || undefined;
  const { data: invoiceId, error } = await supabase.rpc("post_sales_invoice", {
    p_doc_date: docDate,
    p_customer_id: Number(formData.get("customer_id")),
    p_lines: lines,
    p_notes: String(formData.get("notes") ?? ""),
    p_received_amount: received || undefined,
    p_received_treasury_account_id: receivedIn,
  });
  if (error) return { error: arabicError(error) };

  revalidatePath("/sales");
  revalidatePath("/inventory");
  redirect(`/sales/${invoiceId}`);
}

export async function cancelSalesInvoice(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const id = Number(formData.get("id"));

  const { error } = await supabase.rpc("cancel_sales_invoice", { p_invoice_id: id });
  if (error) return { error: arabicError(error) };

  revalidatePath("/sales");
  revalidatePath("/inventory");
  redirect(`/sales/${id}`);
}
