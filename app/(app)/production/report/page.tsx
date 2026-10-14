import type { Metadata } from "next";
import Link from "next/link";

import { DateInput } from "@/components/date-input";
import { PrintHeader } from "@/components/print-header";
import { ReportTools } from "@/components/report-tools";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
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
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";
import { formatQty, formatQtyUnits, formatUnitCost, formatUnitCostUnits, parseQty, unitCostUnits } from "@/lib/quantity";

export const metadata: Metadata = { title: "تقرير الإنتاج" };

// تقرير الإنتاج (SPEC §7): لكل تسجيل التاريخ والمنتج والكمية وتكلفة المواد والإضافية وتكلفة الوحدة،
// وإجماليات الفترة بدون الملغى (الكميات تُجمع لكل منتج بوحدته الأساسية)
export default async function ProductionReportPage({ searchParams }: PageProps<"/production/report">) {
  const { supabase } = await requireUser();
  const query = await searchParams;
  const fromText = typeof query.from === "string" ? query.from : null;
  const toText = typeof query.to === "string" ? query.to : "";
  const itemParam = typeof query.item === "string" ? query.item : "";

  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);
  const itemId = Number(itemParam) || undefined;

  const [{ data: orders }, { data: products }, { data: settings }] = await Promise.all([
    supabase.rpc("production_list", { p_from: from ?? undefined, p_to: to ?? undefined, p_item_id: itemId }),
    supabase.from("items").select("id, code, name").eq("type", "finished_good").order("code"),
    supabase.from("settings").select("company_name").eq("id", 1).single(),
  ]);
  const active = (orders ?? []).filter((o) => !o.is_cancelled);
  const totals = {
    materials: sumAmounts(active.map((o) => o.materials_cost)),
    extra: sumAmounts(active.map((o) => o.extra_cost)),
    total: sumAmounts(active.map((o) => o.total_cost)),
  };

  // ملخص لكل منتج: الكمية بالوحدة الأساسية والتكلفة ومتوسط تكلفة الوحدة للفترة
  const summary = new Map<number, { code: string; name: string; unit: string; qty: bigint; cost: bigint; count: number }>();
  for (const o of active) {
    const s = summary.get(o.item_id) ?? { code: o.item_code, name: o.item_name, unit: o.base_unit, qty: 0n, cost: 0n, count: 0 };
    s.qty += parseQty(o.base_qty_produced) ?? 0n;
    s.cost += sumAmounts([o.total_cost]);
    s.count += 1;
    summary.set(o.item_id, s);
  }

  const period = `من ${from ? formatDate(from) : "البداية"} إلى ${to ? formatDate(to) : formatDate(todayIso())}`;
  const product = (products ?? []).find((p) => p.id === itemId);

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">تقرير الإنتاج</h1>
        <ReportTools
          filename={`تقرير-الإنتاج-${todayIso()}.csv`}
          headers={[
            "رقم الأمر",
            "التاريخ",
            "المنتج",
            "الكمية",
            "الوحدة",
            "الكمية بالوحدة الأساسية",
            "تكلفة المواد",
            "التكاليف الإضافية",
            "إجمالي التكلفة",
            "تكلفة الوحدة الأساسية",
            "الحالة",
          ]}
          rows={(orders ?? []).map((o) => [
            String(o.doc_no),
            o.doc_date,
            `${o.item_code} - ${o.item_name}`,
            o.qty_produced,
            o.unit_name,
            o.base_qty_produced,
            o.materials_cost,
            o.extra_cost,
            o.total_cost,
            o.unit_cost,
            o.is_cancelled ? "ملغى" : "",
          ])}
        />
      </div>

      <PrintHeader
        company={settings?.company_name ?? ""}
        title={`تقرير الإنتاج${product ? ` - ${product.code} - ${product.name}` : ""}`}
        subtitle={period}
      />

      <form className="flex flex-wrap items-end gap-3 print:hidden">
        <div className="grid gap-1">
          <Label htmlFor="from">من تاريخ</Label>
          <DateInput id="from" name="from" defaultValue={from} className="w-36 text-end" />
        </div>
        <div className="grid gap-1">
          <Label htmlFor="to">إلى تاريخ</Label>
          <DateInput id="to" name="to" defaultValue={to} className="w-36 text-end" />
        </div>
        <div className="grid gap-1">
          <Label htmlFor="item">المنتج</Label>
          <NativeSelect id="item" name="item" defaultValue={itemParam} className="w-60">
            <option value="">كل المنتجات</option>
            {(products ?? []).map((p) => (
              <option key={p.id} value={p.id}>
                {p.code} - {p.name}
              </option>
            ))}
          </NativeSelect>
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
              <TableHead className="text-end">الكمية</TableHead>
              <TableHead className="text-end">تكلفة المواد</TableHead>
              <TableHead className="text-end">التكاليف الإضافية</TableHead>
              <TableHead className="text-end">إجمالي التكلفة</TableHead>
              <TableHead className="text-end">تكلفة الوحدة</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {(orders ?? []).map((o) => (
              <TableRow key={o.id} className={o.is_cancelled ? "text-muted-foreground" : ""}>
                <TableCell>
                  <Link
                    href={`/production/${o.id}`}
                    className="font-semibold underline-offset-4 hover:underline print:no-underline"
                  >
                    {o.doc_no}
                  </Link>
                </TableCell>
                <TableCell dir="ltr" className="text-end">
                  {formatDate(o.doc_date)}
                </TableCell>
                <TableCell>
                  {o.item_code} - {o.item_name}
                </TableCell>
                <TableCell className="text-start tabular-nums">
                  <span dir="ltr">{formatQty(o.qty_produced)}</span> {o.unit_name}
                  {o.unit_name !== o.base_unit && (
                    <div className="text-xs text-muted-foreground">
                      = <span dir="ltr">{formatQty(o.base_qty_produced)}</span> {o.base_unit}
                    </div>
                  )}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(o.materials_cost)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(o.extra_cost)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(o.total_cost)}
                </TableCell>
                <TableCell className="text-start tabular-nums">
                  <span dir="ltr">{formatUnitCost(o.unit_cost)}</span>
                  <span className="text-xs text-muted-foreground"> / {o.base_unit}</span>
                </TableCell>
                <TableCell>{o.is_cancelled && <Badge>ملغى</Badge>}</TableCell>
              </TableRow>
            ))}
            {(orders ?? []).length === 0 ? (
              <TableRow>
                <TableCell colSpan={9} className="py-6 text-center text-muted-foreground">
                  لا يوجد إنتاج في هذه الفترة.
                </TableCell>
              </TableRow>
            ) : (
              <TableRow className="font-bold hover:bg-transparent">
                <TableCell colSpan={4}>إجمالي الفترة (بدون الملغى)</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(totals.materials)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(totals.extra)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(totals.total)}
                </TableCell>
                <TableCell colSpan={2} />
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {summary.size > 0 && (
        <>
          <h2 className="pt-2 font-bold">ملخص الفترة حسب المنتج</h2>
          <div className="max-w-3xl rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>المنتج</TableHead>
                  <TableHead className="text-end">عدد الأوامر</TableHead>
                  <TableHead className="text-end">الكمية المنتجة</TableHead>
                  <TableHead className="text-end">إجمالي التكلفة</TableHead>
                  <TableHead className="text-end">متوسط تكلفة الوحدة</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {[...summary.entries()].map(([id, s]) => (
                  <TableRow key={id}>
                    <TableCell>
                      {s.code} - {s.name}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {s.count}
                    </TableCell>
                    <TableCell className="text-start tabular-nums">
                      <span dir="ltr">{formatQtyUnits(s.qty)}</span> {s.unit}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatCents(s.cost)}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {s.qty > 0n ? formatUnitCostUnits(unitCostUnits(s.cost, s.qty)) : ""}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </>
      )}
      <p className="text-xs text-muted-foreground print:hidden">
        تكلفة الإنتاج تدخل مخزون المنتج التام ولا تظهر مصروفًا في قائمة الدخل إلا عند البيع (تكلفة المبيعات).
      </p>
    </div>
  );
}
