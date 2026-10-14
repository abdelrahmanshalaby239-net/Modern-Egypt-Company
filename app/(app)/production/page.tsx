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
import { formatQty, formatUnitCost } from "@/lib/quantity";

export const metadata: Metadata = { title: "أوامر الإنتاج" };

export default async function ProductionPage({ searchParams }: PageProps<"/production">) {
  const { supabase } = await requireUser();
  const query = await searchParams;
  const fromText = typeof query.from === "string" ? query.from : null;
  const toText = typeof query.to === "string" ? query.to : "";
  const q = typeof query.q === "string" ? query.q.trim() : "";

  // الافتراضي: من أول السنة الحالية
  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const { data: orders } = await supabase.rpc("production_list", {
    p_from: from ?? undefined,
    p_to: to ?? undefined,
    p_search: q || undefined,
  });
  const active = (orders ?? []).filter((o) => !o.is_cancelled);
  const total = sumAmounts(active.map((o) => o.total_cost));

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">أوامر الإنتاج</h1>
        <div className="flex gap-2">
          <Button asChild variant="outline">
            <Link href="/production/report">تقرير الإنتاج</Link>
          </Button>
          <Button asChild>
            <Link href="/production/new">تسجيل إنتاج</Link>
          </Button>
        </div>
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
          <Input id="q" name="q" defaultValue={q} placeholder="رقم الأمر أو المنتج أو الوصفة" className="w-60" />
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
              <TableHead>رقم الأمر</TableHead>
              <TableHead>التاريخ</TableHead>
              <TableHead>المنتج</TableHead>
              <TableHead>الوصفة</TableHead>
              <TableHead className="text-end">الكمية</TableHead>
              <TableHead className="text-end">إجمالي التكلفة</TableHead>
              <TableHead className="text-end">تكلفة الوحدة</TableHead>
              <TableHead>الحالة</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(orders ?? []).map((o) => (
              <TableRow key={o.id}>
                <TableCell>
                  <Link href={`/production/${o.id}`} className="font-semibold underline-offset-4 hover:underline">
                    {o.doc_no}
                  </Link>
                </TableCell>
                <TableCell dir="ltr" className="text-end">
                  {formatDate(o.doc_date)}
                </TableCell>
                <TableCell>
                  {o.item_code} - {o.item_name}
                </TableCell>
                <TableCell>{o.formula_name}</TableCell>
                <TableCell className="text-start tabular-nums">
                  <span dir="ltr">{formatQty(o.qty_produced)}</span> {o.unit_name}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(o.total_cost)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatUnitCost(o.unit_cost)}
                </TableCell>
                <TableCell>{o.is_cancelled && <Badge>ملغى</Badge>}</TableCell>
              </TableRow>
            ))}
            {(orders ?? []).length === 0 ? (
              <TableRow>
                <TableCell colSpan={8} className="py-6 text-center text-muted-foreground">
                  لا توجد أوامر إنتاج في هذه الفترة.
                </TableCell>
              </TableRow>
            ) : (
              <TableRow className="font-bold hover:bg-transparent">
                <TableCell colSpan={5}>الإجمالي (بدون الملغاة)</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(total)}
                </TableCell>
                <TableCell colSpan={2} />
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
