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
      <aside className="border-b md:w-60 md:shrink-0 md:border-e md:border-b-0 print:hidden">
        <div className="border-b px-4 py-4 font-bold">{settings?.company_name}</div>
        <Sidebar isAdmin={profile.role === "admin"} />
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-end gap-3 border-b px-4 py-3 text-sm md:px-6 print:hidden">
          <span className="text-muted-foreground">
            {profile.full_name || profile.email} · {ROLE_LABELS[profile.role]}
          </span>
          <form action={signOut}>
            <Button type="submit" variant="outline" size="sm">
              خروج
            </Button>
          </form>
        </header>
        <main className="flex-1 px-4 py-6 md:px-6 print:p-0">{children}</main>
      </div>
    </div>
  );
}
