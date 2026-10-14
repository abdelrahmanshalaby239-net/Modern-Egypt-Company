"use server";

import { redirect } from "next/navigation";

import type { FormState } from "@/lib/errors";
import { createClient } from "@/lib/supabase/server";

export async function login(_prev: FormState, formData: FormData): Promise<FormState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!email || !password) {
    return { error: "أدخل البريد الإلكتروني وكلمة المرور." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    return {
      error:
        error.code === "invalid_credentials"
          ? "البريد الإلكتروني أو كلمة المرور غير صحيحة."
          : "تعذّر تسجيل الدخول، تأكد من الاتصال وحاول مرة أخرى.",
    };
  }

  redirect("/");
}
