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
import { formatAmount } from "@/lib/money";
import { formatQty, parseQty } from "@/lib/quantity";

export const metadata: Metadata = { title: "تسوية الجرد" };

export default async function StockAdjustmentsPage({ searchParams }: PageProps<"/stock-adjustments">) {
  const { supabase } = await requireUser();
  const query = await searchParams;
  const fromText = typeof query.from === "string" ? query.from : null;
  const toText = typeof query.to === "string" ? query.to : "";
  const q = typeof query.q === "string" ? query.q.trim() : "";

  // الافتراضي: من أول السنة الحالية
  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const { data: adjustments } = await supabase.rpc("stock_adjustment_list", {
    p_from: from ?? undefined,
    p_to: to ?? undefined,
    p_search: q || undefined,
  });

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">تسوية الجرد</h1>
        <Button asChild>
          <Link href="/stock-adjustments/new">تسوية جرد جديدة</Link>
        </Button>
      </div>

      <form className="filter-bar flex flex-wrap items-end gap-3">
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
          <Input id="q" name="q" defaultValue={q} placeholder="رقم التسوية أو الصنف أو البيان" className="w-60" />
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
              <TableHead>رقم التسوية</TableHead>
              <TableHead>التاريخ</TableHead>
              <TableHead>الصنف</TableHead>
              <TableHead className="text-end">رصيد النظام</TableHead>
              <TableHead className="text-end">الكمية الفعلية</TableHead>
              <TableHead>النوع</TableHead>
              <TableHead className="text-end">القيمة</TableHead>
              <TableHead>البيان</TableHead>
              <TableHead>الحالة</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(adjustments ?? []).map((a) => {
              const surplus = (parseQty(a.counted_qty) ?? 0n) > (parseQty(a.system_qty) ?? 0n);
              return (
                <TableRow key={a.id}>
                  <TableCell>
                    <Link
                      href={`/stock-adjustments/${a.id}`}
                      className="font-semibold underline-offset-4 hover:underline"
                    >
                      {a.doc_no}
                    </Link>
                  </TableCell>
                  <TableCell dir="ltr" className="text-end">
                    {formatDate(a.doc_date)}
                  </TableCell>
                  <TableCell>
                    {a.item_code} - {a.item_name}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatQty(a.system_qty)}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatQty(a.counted_qty)}
                  </TableCell>
                  <TableCell>{surplus ? "زيادة" : "عجز"}</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatAmount(a.total_cost)}
                  </TableCell>
                  <TableCell className="whitespace-normal">{a.notes}</TableCell>
                  <TableCell>{a.is_cancelled && <Badge>ملغاة</Badge>}</TableCell>
                </TableRow>
              );
            })}
            {(adjustments ?? []).length === 0 && (
              <TableRow>
                <TableCell colSpan={9} className="py-6 text-center text-muted-foreground">
                  لا توجد تسويات جرد في هذه الفترة.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
