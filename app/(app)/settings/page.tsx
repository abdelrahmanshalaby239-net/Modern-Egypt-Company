import type { Metadata } from "next";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireAdmin } from "@/lib/auth";
import { CompanyForm } from "./settings-forms";

export const metadata: Metadata = { title: "بيانات الشركة" };

export default async function SettingsPage() {
  const { supabase } = await requireAdmin();
  const { data: settings } = await supabase.from("settings").select("*").eq("id", 1).single();
  if (!settings) return null;

  return (
    <div className="grid max-w-2xl gap-6">
      <h1 className="text-xl font-bold">بيانات الشركة</h1>
      <Card>
        <CardHeader>
          <CardTitle>بيانات الشركة</CardTitle>
          <CardDescription>تظهر في رأس فواتير المبيعات والمشتريات المطبوعة.</CardDescription>
        </CardHeader>
        <CardContent>
          <CompanyForm settings={settings} />
        </CardContent>
      </Card>
    </div>
  );
}
