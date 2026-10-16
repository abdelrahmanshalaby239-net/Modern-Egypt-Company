import type { Viewport } from "next";
import { CircleUserRound } from "lucide-react";

import { Button } from "@/components/ui/button";
import { requireUser } from "@/lib/auth";
import { ROLE_LABELS } from "@/lib/labels";
import { signOut } from "./actions";
import { NavDrawer } from "./nav-drawer";

export const viewport: Viewport = { themeColor: "#111111" };

// زر الخروج على الرأس الداكن (نفس زر outline بألوان الرأس)
const HEADER_BUTTON =
  "border-white/20 bg-transparent text-header-foreground hover:bg-white/10 focus-visible:ring-white/40";

export default async function AppLayout({ children }: LayoutProps<"/">) {
  const { supabase, profile } = await requireUser();
  const { data: settings } = await supabase
    .from("settings")
    .select("company_name")
    .eq("id", 1)
    .single();
  const userLabel = profile.full_name || profile.email || "";

  return (
    <div className="flex min-h-dvh flex-col">
      {/* الرأس على كل الشاشات: زر القائمة (يمين) واسم الشركة، والمستخدم والخروج (يسار) */}
      <header className="sticky top-0 z-40 bg-header ps-[max(1rem,env(safe-area-inset-right))] pe-[max(1rem,env(safe-area-inset-left))] pt-[env(safe-area-inset-top)] text-header-foreground md:px-8 print:hidden">
        <div className="flex h-14 min-w-0 items-center gap-2 md:h-16 md:gap-4">
          <NavDrawer isAdmin={profile.role === "admin"} userLabel={userLabel} roleLabel={ROLE_LABELS[profile.role]} />
          <span className="min-w-0 flex-1 truncate text-[0.9375rem] font-bold md:text-base">{settings?.company_name}</span>
          <span className="hidden min-w-0 items-center gap-2 text-sm md:flex">
            <CircleUserRound className="size-5 shrink-0" strokeWidth={1.5} aria-hidden />
            <span className="truncate">
              {userLabel} <span className="text-header-muted">· {ROLE_LABELS[profile.role]}</span>
            </span>
          </span>
          <form action={signOut}>
            <Button type="submit" variant="outline" size="sm" className={HEADER_BUTTON}>
              خروج
            </Button>
          </form>
        </div>
      </header>
      <main className="min-w-0 flex-1 ps-[max(1rem,env(safe-area-inset-right))] pe-[max(1rem,env(safe-area-inset-left))] pt-5 pb-[calc(1.5rem+env(safe-area-inset-bottom))] md:px-8 md:py-8 print:p-0">
        {children}
      </main>
    </div>
  );
}
