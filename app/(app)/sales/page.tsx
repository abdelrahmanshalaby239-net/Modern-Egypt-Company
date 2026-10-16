import type { Metadata } from "next";
import Link from "next/link";

import { DateInput } from "@/components/date-input";
import { PrintHeader } from "@/components/print-header";
import { ReportTools } from "@/components/report-tools";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
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
import { formatDate, parseDate, todayIso, yearStartIso } from "@/lib/format";
import { PAYMENT_STATUS_LABELS, paymentStatus } from "@/lib/labels";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";

export const metadata: Metadata = { title: "فواتير المبيعات" };

export default async function SalesPage({ searchParams }: PageProps<"/sales">) {
  const { supabase } = await requireUser();
  const query = await searchParams;
  const fromText = typeof query.from === "string" ? query.from : null;
  const toText = typeof query.to === "string" ? query.to : "";
  const q = typeof query.q === "string" ? query.q.trim() : "";

  // الافتراضي: من أول السنة الحالية
  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const [{ data: invoices }, { data: settings }] = await Promise.all([
    supabase.rpc("sales_invoice_list", { p_from: from ?? undefined, p_to: to ?? undefined, p_search: q || undefined }),
    supabase.from("settings").select("company_name").eq("id", 1).single(),
  ]);
  const active = (invoices ?? []).filter((i) => !i.is_cancelled);
  const total = sumAmounts(active.map((i) => i.total));
  const paid = sumAmounts(active.map((i) => i.paid_amount));
  const cost = sumAmounts(active.map((i) => i.cost_total));

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">فواتير المبيعات</h1>
        <div className="flex flex-wrap gap-2">
          <ReportTools
            filename={`فواتير-المبيعات-${todayIso()}.csv`}
            headers={["رقم الفاتورة", "التاريخ", "العميل", "الإجمالي", "المقبوض عند الاعتماد", "التكلفة", "مجمل الربح", "البيان", "الحالة"]}
            rows={(invoices ?? []).map((i) => [
              String(i.doc_no),
              i.doc_date,
              i.customer_name,
              i.total,
              i.paid_amount,
              i.cost_total,
              i.gross_profit,
              i.notes ?? "",
              i.is_cancelled ? "ملغاة" : "",
            ])}
          />
          <Button asChild>
            <Link href="/sales/new">فاتورة مبيعات جديدة</Link>
          </Button>
        </div>
      </div>

      <PrintHeader
        company={settings?.company_name ?? ""}
        title="فواتير المبيعات"
        subtitle={`من ${from ? formatDate(from) : "البداية"} إلى ${to ? formatDate(to) : formatDate(todayIso())}`}
      />

      <form className="filter-bar flex flex-wrap items-end gap-3 print:hidden">
        <div className="grid gap-1">
          <Label htmlFor="from">من تاريخ</Label>
          <DateInput id="from" name="from" defaultValue={from} className="w-36 text-end" />
        </div>
        <div className="grid gap-1">
          <Label htmlFor="to">إلى تاريخ</Label>
          <DateInput id="to" name="to" defaultValue={to} className="w-36 text-end" />
        </div>
        <div className="grid gap-1">
          <Label htmlFor="q">بحث</Label>
          <Input id="q" name="q" defaultValue={q} placeholder="رقم الفاتورة أو العميل أو البيان" className="w-60" />
        </div>
        <Button type="submit" variant="outline">
          عرض
        </Button>
      </form>

      {invalidDate && <Alert>التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة.</Alert>}

      <p className="text-xs text-muted-foreground print:hidden">
        المقبوض وحالة السداد كما كانا عند اعتماد الفاتورة. سندات القبض اللاحقة لا تُخصص لفواتير بعينها، فالرصيد
        الحالي لكل عميل يظهر في شاشة العملاء وكشف حسابه. مجمل الربح = المبيعات − تكلفتها (قبل المصروفات).
      </p>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>رقم الفاتورة</TableHead>
              <TableHead>التاريخ</TableHead>
              <TableHead>العميل</TableHead>
              <TableHead>البيان</TableHead>
              <TableHead className="text-end">الإجمالي</TableHead>
              <TableHead className="text-end">المقبوض عند الاعتماد</TableHead>
              <TableHead>السداد عند الاعتماد</TableHead>
              <TableHead className="text-end">مجمل الربح</TableHead>
              <TableHead>الحالة</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(invoices ?? []).map((i) => (
              <TableRow key={i.id} className={i.is_cancelled ? "text-muted-foreground" : ""}>
                <TableCell>
                  <Link
                    href={`/sales/${i.id}`}
                    className="font-semibold underline-offset-4 hover:underline print:no-underline"
                  >
                    {i.doc_no}
                  </Link>
                </TableCell>
                <TableCell dir="ltr" className="text-end">
                  {formatDate(i.doc_date)}
                </TableCell>
                <TableCell>{i.customer_name}</TableCell>
                <TableCell className="whitespace-normal">{i.notes}</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(i.total)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(i.paid_amount)}
                </TableCell>
                <TableCell>
                  {PAYMENT_STATUS_LABELS[paymentStatus(sumAmounts([i.total]), sumAmounts([i.paid_amount]))]}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(i.gross_profit)}
                </TableCell>
                <TableCell>{i.is_cancelled && <Badge>ملغاة</Badge>}</TableCell>
              </TableRow>
            ))}
            {(invoices ?? []).length === 0 ? (
              <TableRow>
                <TableCell colSpan={9} className="py-6 text-center text-muted-foreground">
                  لا توجد فواتير مبيعات في هذه الفترة.
                </TableCell>
              </TableRow>
            ) : (
              <TableRow className="font-bold hover:bg-transparent">
                <TableCell colSpan={4}>الإجمالي (بدون الملغاة)</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(total)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(paid)}
                </TableCell>
                <TableCell />
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(total - cost)}
                </TableCell>
                <TableCell />
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
