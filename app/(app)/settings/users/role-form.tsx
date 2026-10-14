"use client";

import { Button } from "@/components/ui/button";
import { NativeSelect } from "@/components/ui/native-select";
import { ROLE_LABELS } from "@/lib/labels";
import { useFormAction } from "@/lib/use-form-action";
import { saveRole } from "../actions";

export function RoleForm({ id, role, isSelf }: { id: string; role: string; isSelf: boolean }) {
  const [state, onSubmit, pending] = useFormAction(saveRole);

  return (
    <form onSubmit={onSubmit} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="id" value={id} />
      <NativeSelect
        name="role"
        defaultValue={role}
        disabled={isSelf}
        className="w-36"
        aria-label="الدور"
      >
        {Object.entries(ROLE_LABELS).map(([value, label]) => (
          <option key={value} value={value}>
            {label}
          </option>
        ))}
      </NativeSelect>
      {isSelf ? (
        <span className="text-xs text-muted-foreground">لا يمكنك تغيير دورك</span>
      ) : (
        <Button type="submit" size="sm" disabled={pending}>
          حفظ
        </Button>
      )}
      {state.error && <span className="text-xs text-destructive">{state.error}</span>}
      {state.success && <span className="text-xs text-success">{state.success}</span>}
    </form>
  );
}
