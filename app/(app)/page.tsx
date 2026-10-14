import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireUser } from "@/lib/auth";
import { ROLE_LABELS } from "@/lib/labels";

export default async function HomePage() {
  const { supabase, profile } = await requireUser();
  const { data: settings } = await supabase
    .from("settings")
    .select("company_name")
    .eq("id", 1)
    .single();

  return (
    <Card className="max-w-xl">
      <CardHeader>
        <CardTitle className="text-xl">مرحبًا {profile.full_name || profile.email}</CardTitle>
        <CardDescription>{settings?.company_name}</CardDescription>
      </CardHeader>
      <CardContent className="text-sm text-muted-foreground">
        دورك في النظام: {ROLE_LABELS[profile.role]}
      </CardContent>
    </Card>
  );
}
