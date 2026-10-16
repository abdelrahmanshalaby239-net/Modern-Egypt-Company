import type { Viewport } from "next";
import { CircleUserRound } from "lucide-react";

import { Button } from "@/components/ui/button";
import { requireUser } from "@/lib/auth";
import { ROLE_LABELS } from "@/lib/labels";
import { signOut } from "./actions";
import { MobileNav } from "./mobile-nav";
import { Sidebar } from "./sidebar";

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
  const isAdmin = profile.role === "admin";
  const userLabel = profile.full_name || profile.email || "";

  return (
    <div className="flex min-h-dvh flex-col md:flex-row">
      {/* القائمة الجانبية للكمبيوتر والتابلت */}
      <aside className="hidden bg-background md:sticky md:top-0 md:flex md:h-dvh md:w-64 md:shrink-0 md:flex-col md:border-e print:hidden">
        <div className="px-6 pt-6 pb-4 text-lg leading-snug font-bold">{settings?.company_name}</div>
        <div className="scrollbar-subtle md:min-h-0 md:flex-1 md:overflow-y-auto md:overscroll-contain">
          <Sidebar isAdmin={isAdmin} />
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        {/* رأس الموبايل: زر القائمة واسم الشركة والخروج */}
        <header className="sticky top-0 z-40 flex items-center gap-2 bg-header ps-[max(1rem,env(safe-area-inset-right))] pe-[max(1rem,env(safe-area-inset-left))] pt-[env(safe-area-inset-top)] text-header-foreground md:hidden print:hidden">
          <div className="flex h-14 min-w-0 flex-1 items-center gap-2">
            <MobileNav
              companyName={settings?.company_name ?? ""}
              isAdmin={isAdmin}
              userLabel={userLabel}
              roleLabel={ROLE_LABELS[profile.role]}
            />
            <span className="min-w-0 flex-1 truncate text-[0.9375rem] font-bold">{settings?.company_name}</span>
            <form action={signOut}>
              <Button type="submit" variant="outline" size="sm" className={HEADER_BUTTON}>
                خروج
              </Button>
            </form>
          </div>
        </header>
        {/* رأس الكمبيوتر */}
        <header className="hidden items-center justify-end gap-4 bg-header px-8 text-sm text-header-foreground md:flex md:h-16 print:hidden">
          <span className="flex min-w-0 items-center gap-2">
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
        </header>
        <main className="min-w-0 flex-1 ps-[max(1rem,env(safe-area-inset-right))] pe-[max(1rem,env(safe-area-inset-left))] pt-5 pb-[calc(1.5rem+env(safe-area-inset-bottom))] md:px-8 md:py-8 print:p-0">
          {children}
        </main>
      </div>
    </div>
  );
}
