"use client";

import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { SYSTEM_ACCOUNT_KEYS } from "@/lib/labels";
import { useFormAction } from "@/lib/use-form-action";
import { saveSystemAccounts } from "../actions";
import { FormMessage } from "../settings-forms";

type Option = { id: number; code: string; name: string; type: string };

export function SystemAccountsForm({
  mapping,
  accounts,
}: {
  mapping: Record<string, number>;
  accounts: Option[]; // الحسابات الفرعية النشطة
}) {
  const [state, onSubmit, pending] = useFormAction(saveSystemAccounts);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      {SYSTEM_ACCOUNT_KEYS.map(({ key, label, type }) => (
        <div key={key} className="grid gap-2 sm:grid-cols-[14rem_1fr] sm:items-center">
          <Label htmlFor={key}>{label}</Label>
          <NativeSelect id={key} name={key} defaultValue={mapping[key]}>
            {accounts
              .filter((a) => a.type === type)
              .map((a) => (
                <option key={a.id} value={a.id}>
                  {a.code} - {a.name}
                </option>
              ))}
          </NativeSelect>
        </div>
      ))}
      <FormMessage state={state} />
      <div>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الحفظ..." : "حفظ"}
        </Button>
      </div>
    </form>
  );
}
