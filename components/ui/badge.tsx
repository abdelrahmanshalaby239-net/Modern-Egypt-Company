import * as React from "react";

import { cn } from "@/lib/utils";

function Badge({ className, ...props }: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="badge"
      className={cn(
        "inline-flex shrink-0 items-center rounded-md border border-primary px-2 py-0.5 text-xs font-medium whitespace-nowrap text-primary-foreground",
        className,
      )}
      {...props}
    />
  );
}

export { Badge };
