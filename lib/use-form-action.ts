"use client";

import { startTransition, useActionState, type FormEvent } from "react";

import type { FormState } from "@/lib/errors";

type ServerAction = (prev: FormState, formData: FormData) => Promise<FormState>;

// مثل useActionState لكن بدون مسح الحقول بعد الإرسال، حتى لا يفقد المستخدم ما كتبه عند ظهور خطأ.
export function useFormAction(serverAction: ServerAction, onSuccess?: () => void) {
  const [state, action, pending] = useActionState(
    async (prev: FormState, formData: FormData) => {
      const result = await serverAction(prev, formData);
      if (result.success) onSuccess?.();
      return result;
    },
    {},
  );

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    startTransition(() => action(formData));
  };

  return [state, onSubmit, pending] as const;
}
