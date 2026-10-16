import type { Metadata } from "next";
import Link from "next/link";

import { DateInput } from "@/components/date-input";
import { PrintHeader } from "@/components/print-header";
import { ReportTools } from "@/components/report-tools";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { formatDate, parseDate, todayIso } from "@/lib/format";
import { formatBalance, plainCents, sumAmounts } from "@/lib/money";

export const metadata: Metadata = { title: "أرصدة الخزائن والبنوك" };

// الرصيد من ميزان المراجعة نفسه (journal_lines فقط)، فيطابق الأستاذ العام دائمًا
export default async function TreasuryPage({ searchParams }: PageProps<"/treasury">) {
  const { supabase } = await requireUser();
  const params = await searchParams;
  const asOfText = typeof params.as_of === "string" ? params.as_of : "";
  const asOf = asOfText ? parseDate(asOfText) : todayIso();

  const [{ data: treasuries }, { data: balances }, { data: settings }] = await Promise.all([
    supabase.from("accounts").select("id, code, name, is_active").eq("is_treasury", true).order("code"),
    asOf ? supabase.rpc("trial_balance", { p_as_of: asOf }) : Promise.resolve({ data: null }),
    supabase.from("settings").select("company_name").eq("id", 1).single(),
  ]);

  const balanceOf = new Map(
    (balances ?? []).map((b) => [b.account_id, sumAmounts([b.debit]) - sumAmounts([b.credit])]),
  );
  // المعطّل يظهر فقط لو له رصيد
  const rows = (treasuries ?? [])
    .map((a) => ({ ...a, balance: balanceOf.get(a.id) ?? 0n }))
    .filter((a) => a.is_active || a.balance !== 0n);
  const total = rows.reduce((t, a) => t + a.balance, 0n);

  return (
    <div className="grid max-w-3xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">أرصدة الخزائن والبنوك</h1>
        <ReportTools
          filename={`أرصدة-الخزائن-${asOf ?? ""}.csv`}
          headers={["الكود", "الحساب", "الرصيد"]}
          rows={rows.map((a) => [a.code, a.name, plainCents(a.balance)])}
        />
      </div>

      <form className="filter-bar flex flex-wrap items-end gap-3 print:hidden">
        <div className="grid gap-1">
          <Label htmlFor="as_of">حتى تاريخ</Label>
          <DateInput id="as_of" name="as_of" defaultValue={asOf} className="w-36 text-end" />
        </div>
        <Button type="submit" variant="outline">
          عرض
        </Button>
      </form>

      {!asOf && <Alert>التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة.</Alert>}

      {asOf && (
        <>
          <PrintHeader
            company={settings?.company_name ?? ""}
            title="أرصدة الخزائن والبنوك"
            subtitle={`حتى ${formatDate(asOf)}`}
          />
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>الكود</TableHead>
                  <TableHead>الخزينة/البنك</TableHead>
                  <TableHead className="text-end">الرصيد</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((a) => (
                  <TableRow key={a.id}>
                    <TableCell dir="ltr" className="text-end font-mono">
                      {a.code}
                    </TableCell>
                    <TableCell>
                      <Link
                        href={`/ledger?account=${a.id}&to=${formatDate(asOf)}`}
                        className="underline-offset-4 hover:underline"
                      >
                        {a.name}
                      </Link>
                      {!a.is_active && <span className="text-muted-foreground"> (معطّل)</span>}
                    </TableCell>
                    <TableCell className="text-end tabular-nums whitespace-nowrap">
                      {formatBalance(plainCents(a.balance))}
                    </TableCell>
                  </TableRow>
                ))}
                {rows.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={3} className="py-6 text-center text-muted-foreground">
                      لا توجد حسابات خزينة أو بنوك. حدّدها من دليل الحسابات.
                    </TableCell>
                  </TableRow>
                )}
                <TableRow className="font-bold hover:bg-transparent">
                  <TableCell colSpan={2}>الإجمالي</TableCell>
                  <TableCell className="text-end tabular-nums whitespace-nowrap">
                    {formatBalance(plainCents(total))}
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
        </>
      )}
    </div>
  );
}
