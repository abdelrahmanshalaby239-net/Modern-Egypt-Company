import type { Metadata } from "next";
import Link from "next/link";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getManualPostingAccounts } from "@/lib/accounts";
import { requireUser } from "@/lib/auth";
import { formatDate, yearStartIso } from "@/lib/format";
import { OpeningBalancesForm } from "./opening-balances-form";

export const metadata: Metadata = { title: "الأرصدة الافتتاحية" };

export default async function OpeningBalancesPage() {
  const { supabase } = await requireUser();

  // القيد الافتتاحي النشط = قيد افتتاحي لم يُلغَ بقيد عكسي
  const { data: openings } = await supabase
    .from("journal_entries")
    .select("id, entry_no, entry_date")
    .eq("source_type", "opening");
  const ids = (openings ?? []).map((o) => o.id);
  const { data: reversals } = ids.length
    ? await supabase.from("journal_entries").select("reverses_entry_id").in("reverses_entry_id", ids)
    : { data: [] };
  const reversed = new Set((reversals ?? []).map((r) => r.reverses_entry_id));
  const active = (openings ?? []).find((o) => !reversed.has(o.id));

  if (active) {
    return (
      <div className="grid max-w-2xl gap-4">
        <h1 className="text-xl font-bold">الأرصدة الافتتاحية</h1>
        <Card>
          <CardHeader>
            <CardTitle>تم تسجيل الأرصدة الافتتاحية</CardTitle>
            <CardDescription>
              سُجّلت في القيد رقم {active.entry_no} بتاريخ{" "}
              <span dir="ltr">{formatDate(active.entry_date)}</span>. هذه الشاشة تُستخدم مرة واحدة.
            </CardDescription>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            للتصحيح: افتح{" "}
            <Link href={`/journal/${active.id}`} className="font-semibold text-foreground underline">
              القيد رقم {active.entry_no}
            </Link>{" "}
            وألغِه، ثم سجّل الأرصدة من جديد.
          </CardContent>
        </Card>
      </div>
    );
  }

  const [accounts, { data: capital }] = await Promise.all([
    getManualPostingAccounts(supabase),
    supabase
      .from("system_accounts")
      .select("account:accounts(code, name)")
      .eq("key", "capital")
      .single(),
  ]);

  return (
    <div className="grid max-w-4xl gap-4">
      <h1 className="text-xl font-bold">الأرصدة الافتتاحية</h1>
      <p className="text-sm text-muted-foreground">
        أرصدة الحسابات في أول المدة. أرصدة العملاء والموردين ومخزون أول المدة تُسجَّل في شاشاتها
        لاحقًا.
      </p>
      <OpeningBalancesForm
        accounts={accounts}
        defaultDate={formatDate(yearStartIso())}
        capitalLabel={capital?.account ? `${capital.account.code} - ${capital.account.name}` : "رأس المال"}
      />
    </div>
  );
}
