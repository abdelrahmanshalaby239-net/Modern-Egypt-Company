import type { Metadata } from "next";
import Link from "next/link";

import { DateInput } from "@/components/date-input";
import { PrintHeader } from "@/components/print-header";
import { ReportTools } from "@/components/report-tools";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableRow } from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { formatDate, parseDate, todayIso } from "@/lib/format";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";

export const metadata: Metadata = { title: "الميزانية العمومية" };

const SECTIONS = [
  { key: "asset", title: "الأصول", total: "إجمالي الأصول" },
  { key: "liability", title: "الخصوم", total: "إجمالي الخصوم" },
  { key: "equity", title: "حقوق الملكية", total: "إجمالي حقوق الملكية" },
] as const;

// الميزانية العمومية بتاريخ (SPEC §6.7): تشمل ربح الفترة الجارية (غير المقفل) ضمن حقوق الملكية
export default async function BalanceSheetPage({ searchParams }: PageProps<"/balance-sheet">) {
  const { supabase } = await requireUser();
  const query = await searchParams;
  const asOfText = typeof query.as_of === "string" ? query.as_of : null;
  const asOf = asOfText === null ? todayIso() : asOfText ? parseDate(asOfText) : null;
  const invalidDate = asOfText && !asOf;

  const [{ data: rows }, { data: settings }] = await Promise.all([
    supabase.rpc("balance_sheet", { p_as_of: asOf ?? undefined }),
    supabase.from("settings").select("company_name").eq("id", 1).single(),
  ]);
  const totalOf = (key: string) => sumAmounts((rows ?? []).filter((r) => r.section === key).map((r) => r.amount));
  const assets = totalOf("asset");
  const liabilities = totalOf("liability");
  const equity = totalOf("equity");
  const balanced = assets === liabilities + equity;

  return (
    <div className="grid max-w-3xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">الميزانية العمومية</h1>
        <ReportTools
          filename={`الميزانية-العمومية-${todayIso()}.csv`}
          headers={["القسم", "الكود", "الحساب", "المبلغ"]}
          rows={(rows ?? []).map((r) => [
            SECTIONS.find((s) => s.key === r.section)?.title ?? r.section,
            r.code ?? "",
            r.name,
            r.amount,
          ])}
        />
      </div>

      <PrintHeader
        company={settings?.company_name ?? ""}
        title="الميزانية العمومية"
        subtitle={`في ${asOf ? formatDate(asOf) : formatDate(todayIso())}`}
      />

      <form className="flex flex-wrap items-end gap-3 print:hidden">
        <div className="grid gap-1">
          <Label htmlFor="as_of">في تاريخ</Label>
          <DateInput id="as_of" name="as_of" defaultValue={asOf} className="w-36 text-end" />
        </div>
        <Button type="submit" variant="outline">
          عرض
        </Button>
      </form>

      {invalidDate && <Alert>التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة.</Alert>}

      <div className="rounded-lg border">
        <Table>
          {SECTIONS.map((section) => {
            const sectionRows = (rows ?? []).filter((r) => r.section === section.key);
            return (
              <TableBody key={section.key}>
                <TableRow className="hover:bg-transparent">
                  <TableCell colSpan={2} className="pt-4 font-bold">
                    {section.title}
                  </TableCell>
                </TableRow>
                {sectionRows.map((r) => (
                  <TableRow key={r.account_id ?? "profit"}>
                    <TableCell className="ps-6">
                      {r.account_id ? (
                        <Link
                          href={`/ledger?account=${r.account_id}&from=&to=${encodeURIComponent(formatDate(asOf))}`}
                          className="underline-offset-4 hover:underline print:no-underline"
                        >
                          {r.code} - {r.name}
                        </Link>
                      ) : (
                        <Link
                          href={`/income-statement?to=${encodeURIComponent(formatDate(asOf))}`}
                          className="underline-offset-4 hover:underline print:no-underline"
                        >
                          {r.name}
                        </Link>
                      )}
                    </TableCell>
                    <TableCell dir="ltr" className="w-40 text-start tabular-nums">
                      {formatAmount(r.amount)}
                    </TableCell>
                  </TableRow>
                ))}
                {sectionRows.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={2} className="ps-6 text-muted-foreground">
                      لا توجد أرصدة.
                    </TableCell>
                  </TableRow>
                )}
                <TableRow className="font-semibold hover:bg-transparent">
                  <TableCell>{section.total}</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatCents(totalOf(section.key))}
                  </TableCell>
                </TableRow>
              </TableBody>
            );
          })}
          <TableBody>
            <TableRow className="bg-accent/40 font-bold hover:bg-accent/40">
              <TableCell>إجمالي الخصوم وحقوق الملكية</TableCell>
              <TableCell dir="ltr" className="text-start tabular-nums">
                {formatCents(liabilities + equity)}
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>

      {balanced ? (
        <Alert variant="success" className="print:hidden">
          الأصول ({formatCents(assets)}) = الخصوم وحقوق الملكية ({formatCents(liabilities + equity)}).
        </Alert>
      ) : (
        <Alert>
          الأصول لا تساوي الخصوم وحقوق الملكية (الفرق {formatCents(assets - liabilities - equity)}). هذا لا يُفترض أن يحدث
          لأن كل قيد متوازن؛ راجع مسؤول النظام.
        </Alert>
      )}
      <p className="text-xs text-muted-foreground">
        الأصول بأرصدتها المدينة (مجمع الإهلاك سالب)، والخصوم وحقوق الملكية بأرصدتها الدائنة. «أرباح لم تُقفل بعد» =
        صافي الإيرادات والمصروفات حتى التاريخ، ويصبح صفرًا بعد إقفال السنة لأن قيد الإقفال ينقله للأرباح المرحّلة.
      </p>
    </div>
  );
}
