"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";
import { isVoucherKind } from "@/lib/labels";

// السند وقيده يُعتمدان معًا داخل post_voucher. المبلغ يبقى نصًا حتى قاعدة البيانات.
export async function postVoucher(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const kind = String(formData.get("kind") ?? "");
  if (!isVoucherKind(kind)) return { error: "نوع السند غير صالح." };
  const docDate = parseDate(String(formData.get("doc_date") ?? ""));
  if (!docDate) return { error: "تاريخ السند غير صحيح. اكتبه بصيغة يوم/شهر/سنة." };

  const { data: voucherId, error } = await supabase.rpc("post_voucher", {
    p_kind: kind,
    p_doc_date: docDate,
    p_treasury_account_id: Number(formData.get("treasury_account_id")),
    p_party_kind: String(formData.get("party_kind") ?? ""),
    p_party_id: Number(formData.get("party_id")),
    p_amount: String(formData.get("amount") ?? ""),
    p_notes: String(formData.get("notes") ?? ""),
  });
  if (error) return { error: arabicError(error) };

  revalidatePath(`/vouchers/${kind}`);
  redirect(`/vouchers/${kind}/${voucherId}`);
}

export async function cancelVoucher(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();

  const kind = String(formData.get("kind") ?? "");
  if (!isVoucherKind(kind)) return { error: "نوع السند غير صالح." };
  const id = Number(formData.get("id"));

  const { error } = await supabase.rpc("cancel_voucher", { p_voucher_id: id });
  if (error) return { error: arabicError(error) };

  revalidatePath(`/vouchers/${kind}`);
  redirect(`/vouchers/${kind}/${id}`);
}
