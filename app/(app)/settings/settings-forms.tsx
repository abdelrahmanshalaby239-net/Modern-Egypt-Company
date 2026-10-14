"use client";

import { DateInput } from "@/components/date-input";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { Tables } from "@/lib/database.types";
import type { FormState } from "@/lib/errors";
import { useFormAction } from "@/lib/use-form-action";
import { saveCompany, saveLockDate } from "./actions";

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
      <div className="grid grid-cols-2 gap-3">
        <div className="grid gap-2">
          <Label htmlFor="currency_name">اسم العملة</Label>
          <Input
            id="currency_name"
            name="currency_name"
            defaultValue={settings.currency_name}
            required
          />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="currency_symbol">رمز العملة</Label>
          <Input
            id="currency_symbol"
            name="currency_symbol"
            defaultValue={settings.currency_symbol}
            required
          />
        </div>
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

export function LockDateForm({ lockDate }: { lockDate: string | null }) {
  const [state, onSubmit, pending] = useFormAction(saveLockDate);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      <div className="grid max-w-xs gap-2">
        <Label htmlFor="lock_date">تاريخ القفل</Label>
        <DateInput id="lock_date" name="lock_date" defaultValue={lockDate} />
        <p className="text-xs text-muted-foreground">
          أي مستند أو قيد بتاريخ يساوي هذا التاريخ أو قبله سيُرفض. اتركه فارغًا لإلغاء القفل.
        </p>
      </div>
      <FormMessage state={state} />
      <div>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الحفظ..." : "حفظ تاريخ القفل"}
        </Button>
      </div>
    </form>
  );
}

export { FormMessage };
