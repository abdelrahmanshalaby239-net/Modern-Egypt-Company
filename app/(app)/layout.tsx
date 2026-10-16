import { CircleUserRound } from "lucide-react";

import { Button } from "@/components/ui/button";
import { requireUser } from "@/lib/auth";
import { ROLE_LABELS } from "@/lib/labels";
import { signOut } from "./actions";
import { MobileNav } from "./mobile-nav";
import { Sidebar } from "./sidebar";

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
        <header className="sticky top-0 z-40 flex items-center gap-2 border-b bg-background/95 ps-[max(1rem,env(safe-area-inset-right))] pe-[max(1rem,env(safe-area-inset-left))] pt-[env(safe-area-inset-top)] backdrop-blur supports-[backdrop-filter]:bg-background/85 md:hidden print:hidden">
          <div className="flex h-14 min-w-0 flex-1 items-center gap-2">
            <MobileNav
              companyName={settings?.company_name ?? ""}
              isAdmin={isAdmin}
              userLabel={userLabel}
              roleLabel={ROLE_LABELS[profile.role]}
            />
            <span className="min-w-0 flex-1 truncate text-[0.9375rem] font-bold">{settings?.company_name}</span>
            <form action={signOut}>
              <Button type="submit" variant="outline" size="sm">
                خروج
              </Button>
            </form>
          </div>
        </header>
        {/* رأس الكمبيوتر */}
        <header className="hidden items-center justify-end gap-4 border-b px-8 text-sm md:flex md:h-16 print:hidden">
          <span className="flex min-w-0 items-center gap-2 text-muted-foreground">
            <CircleUserRound className="size-5 shrink-0" strokeWidth={1.5} aria-hidden />
            <span className="truncate">
              {userLabel} · {ROLE_LABELS[profile.role]}
            </span>
          </span>
          <form action={signOut}>
            <Button type="submit" variant="outline" size="sm">
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
