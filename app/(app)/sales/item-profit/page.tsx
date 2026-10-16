import type { Metadata } from "next";
import Link from "next/link";

import { DateInput } from "@/components/date-input";
import { PrintHeader } from "@/components/print-header";
import { ReportTools } from "@/components/report-tools";
import { Alert } from "@/components/ui/alert";
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
import { formatAmount, formatCents, formatPercent, sumAmounts } from "@/lib/money";
import { formatQty } from "@/lib/quantity";

export const metadata: Metadata = { title: "أرباح الأصناف" };

// تقرير أرباح الأصناف (SPEC §8): مجمل الربح من سطور الفواتير غير الملغاة بالتكلفة المحفوظة وقت البيع.
// ?item= يعرض الفواتير التي بيع فيها الصنف.
export default async function ItemProfitPage({ searchParams }: PageProps<"/sales/item-profit">) {
  const { supabase } = await requireUser();
  const query = await searchParams;
  const fromText = typeof query.from === "string" ? query.from : null;
  const toText = typeof query.to === "string" ? query.to : "";
  const itemParam = typeof query.item === "string" ? query.item : "";
  const customerParam = typeof query.customer === "string" ? query.customer : "";

  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);
  const itemId = Number(itemParam) || undefined;
  const customerId = Number(customerParam) || undefined;
  const filters = { p_from: from ?? undefined, p_to: to ?? undefined, p_customer_id: customerId };

  const [{ data: rows }, { data: lines }, { data: products }, { data: customers }, { data: settings }] =
    await Promise.all([
      supabase.rpc("item_profit", { ...filters, p_item_id: itemId }),
      itemId
        ? supabase.rpc("item_profit_lines", { ...filters, p_item_id: itemId })
        : Promise.resolve({ data: null }),
      supabase.from("items").select("id, code, name").eq("type", "finished_good").order("code"),
      supabase.from("customers").select("id, name").order("name"),
      supabase.from("settings").select("company_name").eq("id", 1).single(),
    ]);
  const sales = sumAmounts((rows ?? []).map((r) => r.sales));
  const cost = sumAmounts((rows ?? []).map((r) => r.cost));
  const product = (products ?? []).find((p) => p.id === itemId);
  const customer = (customers ?? []).find((c) => c.id === customerId);

  // رابط الصنف يحتفظ بفلاتر الفترة والعميل
  const linkFor = (id: number) => {
    const params = new URLSearchParams();
    if (fromText !== null) params.set("from", fromText);
    if (toText) params.set("to", toText);
    if (customerParam) params.set("customer", customerParam);
    params.set("item", String(id));
    return `/sales/item-profit?${params.toString()}`;
  };
  const period = `من ${from ? formatDate(from) : "البداية"} إلى ${to ? formatDate(to) : formatDate(todayIso())}`;

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">أرباح الأصناف</h1>
        <ReportTools
          filename={`أرباح-الأصناف-${todayIso()}.csv`}
          headers={["الكود", "الصنف", "الكمية المباعة", "الوحدة", "إجمالي المبيعات", "إجمالي التكلفة", "مجمل الربح", "هامش الربح %"]}
          rows={(rows ?? []).map((r) => [r.item_code, r.item_name, r.qty, r.base_unit, r.sales, r.cost, r.profit, r.margin])}
        />
      </div>

      <PrintHeader
        company={settings?.company_name ?? ""}
        title={`أرباح الأصناف${product ? ` - ${product.code} - ${product.name}` : ""}${customer ? ` - العميل ${customer.name}` : ""}`}
        subtitle={period}
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
          <Label htmlFor="item">الصنف</Label>
          <NativeSelect id="item" name="item" defaultValue={itemParam} className="w-56">
            <option value="">كل الأصناف</option>
            {(products ?? []).map((p) => (
              <option key={p.id} value={p.id}>
                {p.code} - {p.name}
              </option>
            ))}
          </NativeSelect>
        </div>
        <div className="grid gap-1">
          <Label htmlFor="customer">العميل</Label>
          <NativeSelect id="customer" name="customer" defaultValue={customerParam} className="w-56">
            <option value="">كل العملاء</option>
            {(customers ?? []).map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
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
              <TableHead>الصنف</TableHead>
              <TableHead className="text-end">الكمية المباعة</TableHead>
              <TableHead className="text-end">إجمالي المبيعات</TableHead>
              <TableHead className="text-end">إجمالي التكلفة</TableHead>
              <TableHead className="text-end">مجمل الربح (قبل المصروفات)</TableHead>
              <TableHead className="text-end">هامش الربح</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(rows ?? []).map((r) => (
              <TableRow key={r.item_id}>
                <TableCell className="font-semibold">
                  <Link href={linkFor(r.item_id)} className="underline-offset-4 hover:underline print:no-underline">
                    {r.item_code} - {r.item_name}
                  </Link>
                </TableCell>
                <TableCell className="text-start tabular-nums">
                  <span dir="ltr">{formatQty(r.qty)}</span> {r.base_unit}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(r.sales)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(r.cost)}
                </TableCell>
                <TableCell dir="ltr" className="text-start font-semibold tabular-nums">
                  {formatAmount(r.profit)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatPercent(sumAmounts([r.profit]), sumAmounts([r.sales]))}
                </TableCell>
              </TableRow>
            ))}
            {(rows ?? []).length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} className="py-6 text-center text-muted-foreground">
                  لا توجد مبيعات في هذه الفترة.
                </TableCell>
              </TableRow>
            ) : (
              <TableRow className="font-bold hover:bg-transparent">
                <TableCell colSpan={2}>الإجمالي</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(sales)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(cost)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(sales - cost)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatPercent(sales - cost, sales)}
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {product && lines && (
        <>
          <h2 className="pt-2 font-bold">
            فواتير الصنف {product.code} - {product.name}
          </h2>
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>الفاتورة</TableHead>
                  <TableHead>التاريخ</TableHead>
                  <TableHead>العميل</TableHead>
                  <TableHead className="text-end">الكمية</TableHead>
                  <TableHead className="text-end">سعر الوحدة</TableHead>
                  <TableHead className="text-end">المبيعات</TableHead>
                  <TableHead className="text-end">التكلفة</TableHead>
                  <TableHead className="text-end">مجمل الربح</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {lines.map((l, i) => (
                  <TableRow key={`${l.invoice_id}-${i}`}>
                    <TableCell>
                      <Link
                        href={`/sales/${l.invoice_id}`}
                        className="font-semibold underline-offset-4 hover:underline print:no-underline"
                      >
                        {l.doc_no}
                      </Link>
                    </TableCell>
                    <TableCell dir="ltr" className="text-end">
                      {formatDate(l.doc_date)}
                    </TableCell>
                    <TableCell>{l.customer_name}</TableCell>
                    <TableCell className="text-start tabular-nums">
                      <span dir="ltr">{formatQty(l.qty)}</span> {l.unit_name}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatAmount(l.unit_price)}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatAmount(l.line_total)}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatAmount(l.cost_total)}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatAmount(l.profit)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </>
      )}

      <p className="text-xs text-muted-foreground">
        هذا <strong>مجمل الربح</strong> (المبيعات − تكلفتها بمتوسط التكلفة المحفوظ وقت البيع)، قبل المصروفات. صافي الربح
        في قائمة الدخل = مجمل الربح − المصروفات (أجور، كهرباء، إهلاك...) + الإيرادات الأخرى. الأجور والمصروفات التي لم
        تُحمَّل على الإنتاج كتكاليف إضافية لا تدخل في تكلفة الصنف. الفواتير الملغاة لا تظهر.
      </p>
    </div>
  );
}
