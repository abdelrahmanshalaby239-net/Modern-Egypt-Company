import { cache } from "react";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

export type Role = "admin" | "accountant";

// المستخدم الحالي وملفه (مرة واحدة لكل طلب)
export const getSession = cache(async () => {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;
  if (!userId) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, email, full_name, role")
    .eq("id", userId)
    .single();
  if (!profile) return null;

  return { supabase, profile: { ...profile, role: profile.role as Role } };
});

export async function requireUser() {
  const session = await getSession();
  if (!session) redirect("/login");
  return session;
}

// الصلاحية الفعلية في RLS؛ هذا فقط لإخفاء شاشات admin عن غيره.
export async function requireAdmin() {
  const session = await requireUser();
  if (session.profile.role !== "admin") redirect("/");
  return session;
}
