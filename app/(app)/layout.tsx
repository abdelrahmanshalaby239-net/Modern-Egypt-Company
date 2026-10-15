import { CircleUserRound } from "lucide-react";

import { Button } from "@/components/ui/button";
import { requireUser } from "@/lib/auth";
import { ROLE_LABELS } from "@/lib/labels";
import { signOut } from "./actions";
import { Sidebar } from "./sidebar";

export default async function AppLayout({ children }: LayoutProps<"/">) {
  const { supabase, profile } = await requireUser();
  const { data: settings } = await supabase
    .from("settings")
    .select("company_name")
    .eq("id", 1)
    .single();

  return (
    <div className="flex min-h-dvh flex-col md:flex-row">
      <aside className="border-b bg-background md:sticky md:top-0 md:flex md:h-dvh md:w-64 md:shrink-0 md:flex-col md:border-e md:border-b-0 print:hidden">
        <div className="px-6 pt-6 pb-4 text-lg leading-snug font-bold">{settings?.company_name}</div>
        <div className="md:min-h-0 md:flex-1 md:overflow-y-auto">
          <Sidebar isAdmin={profile.role === "admin"} />
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-end gap-4 border-b px-4 py-3 text-sm md:h-16 md:px-8 print:hidden">
          <span className="flex min-w-0 items-center gap-2 text-muted-foreground">
            <CircleUserRound className="size-5 shrink-0" strokeWidth={1.5} aria-hidden />
            <span className="truncate">
              {profile.full_name || profile.email} · {ROLE_LABELS[profile.role]}
            </span>
          </span>
          <form action={signOut}>
            <Button type="submit" variant="outline" size="sm">
              خروج
            </Button>
          </form>
        </header>
        <main className="flex-1 px-4 py-6 md:px-8 md:py-8 print:p-0">{children}</main>
      </div>
    </div>
  );
}
