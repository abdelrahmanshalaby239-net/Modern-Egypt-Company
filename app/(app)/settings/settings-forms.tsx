"use client";

import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { Tables } from "@/lib/database.types";
import type { FormState } from "@/lib/errors";
import { useFormAction } from "@/lib/use-form-action";
import { saveCompany } from "./actions";

function FormMessage({ state }: { state: FormState }) {
  if (state.error) return <Alert>{state.error}</Alert>;
  if (state.success) return <Alert variant="success">{state.success}</Alert>;
  return null;
}

type Settings = Tables<"settings">;

export function CompanyForm({ settings }: { settings: Settings }) {
  const [state, onSubmit, pending] = useFormAction(saveCompany);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      <div className="grid gap-2">
        <Label htmlFor="company_name">اسم الشركة</Label>
        <Input
          id="company_name"
          name="company_name"
          defaultValue={settings.company_name}
          required
        />
      </div>
      <div className="grid gap-2">
        <Label htmlFor="company_address">العنوان</Label>
        <Input
          id="company_address"
          name="company_address"
          defaultValue={settings.company_address ?? ""}
        />
      </div>
      <div className="grid max-w-xs gap-2">
        <Label htmlFor="company_phone">رقم الهاتف</Label>
        <Input
          id="company_phone"
          name="company_phone"
          type="tel"
          dir="ltr"
          className="text-end"
          defaultValue={settings.company_phone ?? ""}
        />
      </div>
      <FormMessage state={state} />
      <div>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الحفظ..." : "حفظ"}
        </Button>
      </div>
    </form>
  );
}

export { FormMessage };
