import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

// ألوان الحالات للرسائل والتنبيهات فقط (SPEC §8)
const alertVariants = cva("w-full rounded-xl border px-4 py-3 text-sm", {
  variants: {
    variant: {
      error: "border-destructive/25 bg-destructive/5 text-destructive",
      success: "border-success/25 bg-success/5 text-success",
      warning: "border-warning/25 bg-warning/5 text-warning",
    },
  },
  defaultVariants: {
    variant: "error",
  },
});

function Alert({
  className,
  variant,
  ...props
}: React.ComponentProps<"div"> & VariantProps<typeof alertVariants>) {
  return (
    <div
      data-slot="alert"
      role={variant === "success" ? "status" : "alert"}
      className={cn(alertVariants({ variant }), className)}
      {...props}
    />
  );
}

export { Alert };
