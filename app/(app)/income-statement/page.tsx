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
import { formatDate, parseDate, todayIso, yearStartIso } from "@/lib/format";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";

export const metadata: Metadata = { title: "قائمة الدخل" };

const SECTIONS = [
  { key: "sales", title: "المبيعات", total: "صافي المبيعات" },
  { key: "cost_of_sales", title: "تكلفة المبيعات", total: "إجمالي تكلفة المبيعات" },
  { key: "expenses", title: "مصروفات التشغيل", total: "إجمالي المصروفات" },
  { key: "other_revenue", title: "إيرادات أخرى", total: "إجمالي الإيرادات الأخرى" },
] as const;

// قائمة الدخل لفترة (SPEC §6.7): بدون قيود الإقفال. الافتراضي من بداية السنة المالية المفتوحة حتى اليوم.
export default async function IncomeStatementPage({ searchParams }: PageProps<"/income-statement">) {
  const { supabase } = await requireUser();
  const query = await searchParams;
  const fromText = typeof query.from === "string" ? query.from : null;
  const toText = typeof query.to === "string" ? query.to : null;

  const { data: openYear } = await supabase.from("fiscal_years").select("start_date").eq("is_closed", false).maybeSingle();
  const from = fromText === null ? (openYear?.start_date ?? yearStartIso()) : fromText ? parseDate(fromText) : null;
  const to = toText === null ? todayIso() : toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const [{ data: rows }, { data: settings }] = await Promise.all([
    supabase.rpc("income_statement", { p_from: from ?? undefined, p_to: to ?? undefined }),
    supabase.from("settings").select("company_name").eq("id", 1).single(),
  ]);
  const totalOf = (key: string) => sumAmounts((rows ?? []).filter((r) => r.section === key).map((r) => r.amount));
  const sales = totalOf("sales");
  const cost = totalOf("cost_of_sales");
  const expenses = totalOf("expenses");
  const other = totalOf("other_revenue");
  const gross = sales - cost;
  const net = gross - expenses + other;

  const range = `from=${encodeURIComponent(formatDate(from))}&to=${encodeURIComponent(formatDate(to))}`;
  const period = `من ${from ? formatDate(from) : "البداية"} إلى ${to ? formatDate(to) : "اليوم"}`;
  const label = (key: string) => SECTIONS.find((s) => s.key === key)?.title ?? key;

  return (
    <div className="grid max-w-3xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">قائمة الدخل</h1>
        <ReportTools
          filename={`قائمة-الدخل-${todayIso()}.csv`}
          headers={["القسم", "الكود", "الحساب", "المبلغ"]}
          rows={[
            ...(rows ?? []).map((r) => [label(r.section), r.code, r.name, r.amount]),
            ["مجمل الربح", "", "", formatCents(gross).replace(/,/g, "")],
            ["صافي الربح", "", "", formatCents(net).replace(/,/g, "")],
          ]}
        />
      </div>

      <PrintHeader company={settings?.company_name ?? ""} title="قائمة الدخل" subtitle={period} />

      <form className="flex flex-wrap items-end gap-3 print:hidden">
        <div className="grid gap-1">
          <Label htmlFor="from">من تاريخ</Label>
          <DateInput id="from" name="from" defaultValue={from} className="w-36 text-end" />
        </div>
        <div className="grid gap-1">
          <Label htmlFor="to">إلى تاريخ</Label>
          <DateInput id="to" name="to" defaultValue={to} className="w-36 text-end" />
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
            if (section.key === "other_revenue" && sectionRows.length === 0) return null;
            return (
              <TableBody key={section.key}>
                <TableRow className="hover:bg-transparent">
                  <TableCell colSpan={2} className="pt-4 font-bold">
                    {section.title}
                  </TableCell>
                </TableRow>
                {sectionRows.map((r) => (
                  <TableRow key={r.account_id}>
                    <TableCell className="ps-6">
                      <Link
                        href={`/ledger?account=${r.account_id}&${range}`}
                        className="underline-offset-4 hover:underline print:no-underline"
                      >
                        {r.code} - {r.name}
                      </Link>
                    </TableCell>
                    <TableCell dir="ltr" className="w-40 text-start tabular-nums">
                      {formatAmount(r.amount)}
                    </TableCell>
                  </TableRow>
                ))}
                {sectionRows.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={2} className="ps-6 text-muted-foreground">
                      لا توجد حركة.
                    </TableCell>
                  </TableRow>
                )}
                <TableRow className="font-semibold hover:bg-transparent">
                  <TableCell>{section.total}</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatCents(totalOf(section.key))}
                  </TableCell>
                </TableRow>
                {section.key === "cost_of_sales" && (
                  <TableRow className="bg-accent/40 font-bold hover:bg-accent/40">
                    <TableCell>مجمل الربح (المبيعات − تكلفة المبيعات)</TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatCents(gross)}
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            );
          })}
          <TableBody>
            <TableRow className="bg-accent/40 text-base font-bold hover:bg-accent/40">
              <TableCell>{net < 0n ? "صافي الخسارة" : "صافي الربح"}</TableCell>
              <TableCell dir="ltr" className="text-start tabular-nums">
                {formatCents(net)}
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>

      <p className="text-xs text-muted-foreground">
        المبيعات حسابات الإيرادات 41، وتكلفة المبيعات حسابات المصروفات 5 (تكلفة البضاعة المباعة وفروقات الجرد)، ومصروفات
        التشغيل باقي المصروفات. تكلفة الإنتاج تدخل مخزون المنتج التام ولا تظهر هنا إلا عند البيع (تكلفة المبيعات)، فلا تتكرر.
        قيود إقفال السنة مستبعدة. صافي الربح = مجمل الربح − المصروفات + الإيرادات الأخرى.
      </p>
    </div>
  );
}
