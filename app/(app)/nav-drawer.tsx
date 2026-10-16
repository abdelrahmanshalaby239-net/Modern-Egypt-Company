"use client";

import { useState } from "react";
import { CircleUserRound, Menu, XIcon } from "lucide-react";
import { Dialog as DialogPrimitive } from "radix-ui";

import { Sidebar } from "./sidebar";

// موضع الدرج والخلفية: تحت الرأس الداكن مباشرة (h-14 على الموبايل و h-16 من md، مع safe-area)
const BELOW_HEADER = "top-[calc(3.5rem+env(safe-area-inset-top))] md:top-[calc(4rem+env(safe-area-inset-top))]";

// القائمة على كل الشاشات: درج منزلق من اليمين (RTL) يفتحه زر ☰ في الرأس. يُغلق باختيار صفحة، أو الضغط خارجه
// (ومنه زر القائمة نفسه)، أو Esc، أو زر الإغلاق.
export function NavDrawer({
  isAdmin,
  userLabel,
  roleLabel,
}: {
  isAdmin: boolean;
  userLabel: string;
  roleLabel: string;
}) {
  const [open, setOpen] = useState(false);

  return (
    <DialogPrimitive.Root open={open} onOpenChange={setOpen}>
      <DialogPrimitive.Trigger
        aria-label="القائمة"
        className="group -ms-1.5 flex size-10 shrink-0 items-center justify-center rounded-lg text-header-foreground transition-colors hover:bg-white/10 focus-visible:ring-[3px] focus-visible:ring-white/40 focus-visible:outline-none data-[state=open]:bg-white/10"
      >
        <Menu className="size-5 group-data-[state=open]:hidden" strokeWidth={1.75} aria-hidden />
        <XIcon className="hidden size-5 group-data-[state=open]:block" strokeWidth={1.75} aria-hidden />
      </DialogPrimitive.Trigger>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay
          className={`fixed inset-x-0 bottom-0 ${BELOW_HEADER} z-50 bg-foreground/20 backdrop-blur-[2px] data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:animate-in data-[state=open]:fade-in-0`}
        />
        <DialogPrimitive.Content
          dir="rtl"
          aria-describedby={undefined}
          className={`fixed start-0 bottom-0 ${BELOW_HEADER} z-50 flex w-[min(18rem,86vw)] flex-col border-e bg-background pb-[env(safe-area-inset-bottom)] ps-[env(safe-area-inset-right)] shadow-[0_8px_30px_rgb(0_0_0/0.08)] duration-200 data-[state=closed]:animate-out data-[state=closed]:slide-out-to-start data-[state=open]:animate-in data-[state=open]:slide-in-from-start`}
        >
          <DialogPrimitive.Title className="sr-only">القائمة الرئيسية</DialogPrimitive.Title>
          <div className="flex min-h-12 items-center justify-between gap-3 border-b px-5 py-2">
            <div className="flex min-w-0 items-center gap-1.5 text-xs text-muted-foreground">
              <CircleUserRound className="size-4 shrink-0" strokeWidth={1.5} aria-hidden />
              <span className="truncate">
                {userLabel} · {roleLabel}
              </span>
            </div>
            {/* زر ☰ في الرأس يتحول إلى ✕ للإغلاق؛ هذا الزر لقارئ الشاشة ولوحة المفاتيح (يظهر عند التركيز فقط) */}
            <DialogPrimitive.Close
              aria-label="إغلاق القائمة"
              className="sr-only -me-2 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:not-sr-only focus-visible:flex focus-visible:size-9 focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none"
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
