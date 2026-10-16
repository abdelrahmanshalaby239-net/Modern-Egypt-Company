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
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";

export const metadata: Metadata = { title: "ميزان المراجعة" };

export default async function TrialBalancePage({ searchParams }: PageProps<"/trial-balance">) {
  const { supabase } = await requireUser();
  const params = await searchParams;
  const asOfText = typeof params.as_of === "string" ? params.as_of : "";
  const asOf = asOfText ? parseDate(asOfText) : todayIso();

  const [{ data: rows }, { data: settings }] = await Promise.all([
    asOf ? supabase.rpc("trial_balance", { p_as_of: asOf }) : Promise.resolve({ data: null }),
    supabase.from("settings").select("company_name").eq("id", 1).single(),
  ]);

  const totalDebit = sumAmounts((rows ?? []).map((r) => r.debit));
  const totalCredit = sumAmounts((rows ?? []).map((r) => r.credit));
  const balanced = totalDebit === totalCredit;

  return (
    <div className="grid max-w-4xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">ميزان المراجعة</h1>
        <ReportTools
          filename={`ميزان-المراجعة-${asOf ?? ""}.csv`}
          headers={["الكود", "الحساب", "مدين", "دائن"]}
          rows={(rows ?? []).map((r) => [r.code, r.name, r.debit, r.credit])}
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
            title="ميزان المراجعة بالأرصدة"
            subtitle={`حتى ${formatDate(asOf)}`}
          />
          {rows && rows.length > 0 && !balanced && (
            <Alert>
              تنبيه: إجمالي المدين لا يساوي إجمالي الدائن. الفرق{" "}
              {formatCents(totalDebit > totalCredit ? totalDebit - totalCredit : totalCredit - totalDebit)}
            </Alert>
          )}
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>الكود</TableHead>
                  <TableHead>الحساب</TableHead>
                  <TableHead className="text-end">مدين</TableHead>
                  <TableHead className="text-end">دائن</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(rows ?? []).map((r) => (
                  <TableRow key={r.account_id}>
                    <TableCell dir="ltr" className="text-end font-mono">
                      {r.code}
                    </TableCell>
                    <TableCell>
                      <Link
                        href={`/ledger?account=${r.account_id}&from=&to=${formatDate(asOf)}`}
                        className="underline-offset-4 hover:underline"
                      >
                        {r.name}
                      </Link>
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {r.debit !== "0.00" ? formatAmount(r.debit) : ""}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {r.credit !== "0.00" ? formatAmount(r.credit) : ""}
                    </TableCell>
                  </TableRow>
                ))}
                {(rows ?? []).length === 0 && (
                  <TableRow>
                    <TableCell colSpan={4} className="py-6 text-center text-muted-foreground">
                      لا توجد أرصدة حتى هذا التاريخ.
                    </TableCell>
                  </TableRow>
                )}
                <TableRow className="font-bold hover:bg-transparent">
                  <TableCell colSpan={2}>
                    الإجمالي{" "}
                    <span className={balanced ? "text-success" : "text-destructive"}>
                      ({balanced ? "متوازن" : "غير متوازن"})
                    </span>
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatCents(totalDebit)}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatCents(totalCredit)}
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
