"use client";

import { useState } from "react";
import { CircleUserRound, Menu, XIcon } from "lucide-react";
import { Dialog as DialogPrimitive } from "radix-ui";

import { Sidebar } from "./sidebar";

// قائمة الموبايل: درج منزلق من اليمين (RTL) يفتحه زر القائمة، ويُغلق تلقائيًا بعد اختيار صفحة
export function MobileNav({
  companyName,
  isAdmin,
  userLabel,
  roleLabel,
}: {
  companyName: string;
  isAdmin: boolean;
  userLabel: string;
  roleLabel: string;
}) {
  const [open, setOpen] = useState(false);

  return (
    <DialogPrimitive.Root open={open} onOpenChange={setOpen}>
      <DialogPrimitive.Trigger
        aria-label="فتح القائمة"
        className="-ms-1.5 flex size-10 shrink-0 items-center justify-center rounded-lg transition-colors hover:bg-muted focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none"
      >
        <Menu className="size-5" strokeWidth={1.75} aria-hidden />
      </DialogPrimitive.Trigger>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-foreground/20 backdrop-blur-[2px] data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:animate-in data-[state=open]:fade-in-0 md:hidden" />
        <DialogPrimitive.Content
          dir="rtl"
          aria-describedby={undefined}
          className="fixed inset-y-0 start-0 z-50 flex w-[min(20rem,86vw)] flex-col border-e bg-background pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)] ps-[env(safe-area-inset-right)] shadow-[0_8px_30px_rgb(0_0_0/0.08)] duration-200 data-[state=closed]:animate-out data-[state=closed]:slide-out-to-start data-[state=open]:animate-in data-[state=open]:slide-in-from-start md:hidden"
        >
          <div className="flex items-start justify-between gap-3 border-b px-5 pt-4 pb-4">
            <div className="grid min-w-0 gap-1.5">
              <DialogPrimitive.Title className="text-base leading-snug font-bold">{companyName}</DialogPrimitive.Title>
              <div className="flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground">
                <CircleUserRound className="size-4 shrink-0" strokeWidth={1.5} aria-hidden />
                <span className="truncate">
                  {userLabel} · {roleLabel}
                </span>
              </div>
            </div>
            <DialogPrimitive.Close
              aria-label="إغلاق القائمة"
              className="-me-2 flex size-9 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none"
            >
              <XIcon className="size-5" strokeWidth={1.75} aria-hidden />
            </DialogPrimitive.Close>
          </div>
          <div className="scrollbar-subtle min-h-0 flex-1 overflow-y-auto overscroll-contain">
            <Sidebar isAdmin={isAdmin} onNavigate={() => setOpen(false)} />
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
