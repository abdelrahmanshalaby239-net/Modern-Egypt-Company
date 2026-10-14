import * as React from "react";

import { Input } from "@/components/ui/input";
import { formatDate } from "@/lib/format";

// إدخال تاريخ بصيغة يوم/شهر/سنة. القيمة تُحلَّل على الخادم بـ parseDate.
function DateInput({
  defaultValue,
  ...props
}: Omit<React.ComponentProps<"input">, "defaultValue" | "type"> & {
  defaultValue?: string | null; // ISO yyyy-mm-dd
}) {
  return (
    <Input
      type="text"
      inputMode="numeric"
      dir="ltr"
      placeholder="يوم/شهر/سنة"
      autoComplete="off"
      defaultValue={formatDate(defaultValue)}
      className="text-end"
      {...props}
    />
  );
}

export { DateInput };
