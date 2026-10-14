import type { Metadata } from "next";
import Link from "next/link";

import { DateInput } from "@/components/date-input";
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
import { formatDate, parseDate, yearStartIso } from "@/lib/format";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";

export const metadata: Metadata = { title: "فواتير المشتريات" };

export default async function PurchasesPage({ searchParams }: PageProps<"/purchases">) {
  const { supabase } = await requireUser();
  const query = await searchParams;
  const fromText = typeof query.from === "string" ? query.from : null;
  const toText = typeof query.to === "string" ? query.to : "";
  const q = typeof query.q === "string" ? query.q.trim() : "";

  // الافتراضي: من أول السنة الحالية
  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const { data: invoices } = await supabase.rpc("purchase_invoice_list", {
    p_from: from ?? undefined,
    p_to: to ?? undefined,
    p_search: q || undefined,
  });
  const total = sumAmounts((invoices ?? []).filter((i) => !i.is_cancelled).map((i) => i.total));

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">فواتير المشتريات</h1>
        <Button asChild>
          <Link href="/purchases/new">فاتورة مشتريات جديدة</Link>
        </Button>
      </div>

      <form className="flex flex-wrap items-end gap-3">
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
          <Input id="q" name="q" defaultValue={q} placeholder="رقم الفاتورة أو المورد أو البيان" className="w-60" />
        </div>
        <Button type="submit" variant="outline">
          عرض
        </Button>
      </form>

      {invalidDate && <Alert>التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة.</Alert>}

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>رقم الفاتورة</TableHead>
              <TableHead>التاريخ</TableHead>
              <TableHead>المورد</TableHead>
              <TableHead>البيان</TableHead>
              <TableHead>السداد</TableHead>
              <TableHead className="text-end">الإجمالي</TableHead>
              <TableHead>الحالة</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(invoices ?? []).map((i) => (
              <TableRow key={i.id}>
                <TableCell>
                  <Link href={`/purchases/${i.id}`} className="font-semibold underline-offset-4 hover:underline">
                    {i.doc_no}
                  </Link>
                </TableCell>
                <TableCell dir="ltr" className="text-end">
                  {formatDate(i.doc_date)}
                </TableCell>
                <TableCell>{i.supplier_name}</TableCell>
                <TableCell className="whitespace-normal">{i.notes}</TableCell>
                <TableCell>{i.payment_voucher_id ? "مدفوعة الآن" : "آجل"}</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(i.total)}
                </TableCell>
                <TableCell>{i.is_cancelled && <Badge>ملغاة</Badge>}</TableCell>
              </TableRow>
            ))}
            {(invoices ?? []).length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} className="py-6 text-center text-muted-foreground">
                  لا توجد فواتير مشتريات في هذه الفترة.
                </TableCell>
              </TableRow>
            ) : (
              <TableRow className="font-bold hover:bg-transparent">
                <TableCell colSpan={5}>الإجمالي (بدون الملغاة)</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(total)}
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
