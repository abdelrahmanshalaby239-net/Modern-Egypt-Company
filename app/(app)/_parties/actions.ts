"use server";

import { revalidatePath } from "next/cache";

import { requireUser } from "@/lib/auth";
import { arabicError, type FormState } from "@/lib/errors";
import { PARTY_KINDS, PARTY_LABELS, type PartyKind } from "@/lib/labels";

function readKind(formData: FormData): PartyKind | null {
  const kind = String(formData.get("kind") ?? "");
  return PARTY_KINDS.includes(kind as PartyKind) ? (kind as PartyKind) : null;
}

export async function saveParty(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const kind = readKind(formData);
  if (!kind) return { error: "نوع غير صالح." };
  const { one, table } = PARTY_LABELS[kind];

  const id = Number(formData.get("id")) || null;
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return { error: "الاسم مطلوب." };

  const text = (key: string) => String(formData.get(key) ?? "").trim() || null;
  const values = {
    name,
    phone: text("phone"),
    address: text("address"),
    notes: text("notes"),
    is_active: id ? formData.get("is_active") === "on" : true,
  };

  const { error } = id
    ? await supabase.from(table).update(values).eq("id", id)
    : await supabase.from(table).insert(values);
  if (error) {
    // الاسم فريد حتى لا ينقسم رصيد الطرف على سجلين
    if (error.code === "23505") return { error: `يوجد ${one} بنفس الاسم.` };
    return { error: arabicError(error) };
  }

  revalidatePath(`/${table}`);
  return { success: id ? "تم حفظ التعديلات." : `تمت إضافة ال${one}.` };
}

export async function deleteParty(_prev: FormState, formData: FormData): Promise<FormState> {
  const { supabase } = await requireUser();
  const kind = readKind(formData);
  if (!kind) return { error: "نوع غير صالح." };
  const { one, table } = PARTY_LABELS[kind];

  const { error } = await supabase.from(table).delete().eq("id", Number(formData.get("id")));
  if (error) {
    if (error.code === "23503") {
      return { error: `لا يمكن حذف ${one} عليه قيود أو سندات. يمكنك تعطيله بدل الحذف.` };
    }
    return { error: arabicError(error) };
  }

  revalidatePath(`/${table}`);
  return { success: "تم الحذف." };
}
