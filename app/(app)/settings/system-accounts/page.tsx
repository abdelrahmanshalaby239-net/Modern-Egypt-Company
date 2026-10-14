import type { Metadata } from "next";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireAdmin } from "@/lib/auth";
import { SystemAccountsForm } from "./system-accounts-form";

export const metadata: Metadata = { title: "حسابات النظام" };

export default async function SystemAccountsPage() {
  const { supabase } = await requireAdmin();
  const [{ data: mapping }, { data: accounts }] = await Promise.all([
    supabase.from("system_accounts").select("key, account_id"),
    supabase
      .from("accounts")
      .select("id, code, name, type")
      .eq("is_postable", true)
      .eq("is_active", true)
      .order("code"),
  ]);

  return (
    <div className="grid max-w-2xl gap-6">
      <h1 className="text-xl font-bold">حسابات النظام</h1>
      <Card>
        <CardHeader>
          <CardTitle>ربط القيود التلقائية بالحسابات</CardTitle>
          <CardDescription>
            تستخدمها الفواتير والسندات والإنتاج عند إنشاء القيود. تظهر لكل بند الحسابات من النوع
            المناسب فقط.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <SystemAccountsForm
            mapping={Object.fromEntries((mapping ?? []).map((m) => [m.key, m.account_id]))}
            accounts={accounts ?? []}
          />
        </CardContent>
      </Card>
    </div>
  );
}
