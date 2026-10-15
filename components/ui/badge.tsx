import * as React from "react";

import { cn } from "@/lib/utils";

function Badge({ className, ...props }: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="badge"
      className={cn(
        "inline-flex shrink-0 items-center rounded-full border border-border bg-muted px-2.5 py-0.5 text-xs font-medium whitespace-nowrap text-foreground",
        className,
      )}
      {...props}
    />
  );
}

export { Badge };
