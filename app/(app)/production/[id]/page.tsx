import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CompanyHeader } from "@/components/company-header";
import { PrintButton } from "@/components/print-button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import { formatAmount } from "@/lib/money";
import { formatFactor, formatQty, formatQtyUnits, formatUnitCost, parseQty, roundQtyUnits } from "@/lib/quantity";
import { CancelProductionButton } from "./cancel-production-button";

export const metadata: Metadata = { title: "أمر إنتاج" };

// صفحة أمر الإنتاج وطباعتها: المعياري من الوصفة مقابل المستهلك فعلًا، والتكلفة كما اعتُمدت
export default async function ProductionOrderPage({ params }: PageProps<"/production/[id]">) {
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();

  const { supabase } = await requireUser();
  const { data: order } = await supabase
    .from("production_orders")
    .select(
      "id, doc_no, doc_date, batches::text, unit_name, factor::text, qty_produced::text, base_qty_produced::text, materials_cost::text, extra_cost::text, total_cost::text, unit_cost::text, notes, journal_entry_id, formula:formulas(id, name), item:items!production_orders_finished_item_id_fkey(id, code, name, unit), extra_account:accounts(id, code, name)",
    )
    .eq("id", id)
    .maybeSingle();
  if (!order) notFound();

  const [{ data: lines }, { data: entry }, { data: reversal }, { data: settings }] = await Promise.all([
    supabase
      .from("production_lines")
      .select(
        "id, unit_name, factor::text, standard_base_qty::text, qty::text, base_qty::text, unit_cost::text, total_cost::text, item:items(id, code, name, unit)",
      )
      .eq("order_id", id)
      .order("id"),
    supabase.from("journal_entries").select("id, entry_no").eq("id", order.journal_entry_id).single(),
    supabase.from("journal_entries").select("id, entry_no").eq("reverses_entry_id", order.journal_entry_id).maybeSingle(),
    supabase.from("settings").select("company_name, company_address, company_phone").eq("id", 1).single(),
  ]);

  const title = `أمر إنتاج رقم ${order.doc_no}`;
  const unit = order.item?.unit ?? "";
  const hasExtra = order.extra_cost !== "0.00";

  return (
    <div className="grid max-w-5xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link href="/production" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
          ← أوامر الإنتاج
        </Link>
        <div className="flex gap-2">
          <PrintButton />
          {!reversal && (
            <CancelProductionButton
              id={order.id}
              title={title}
              extra={
                hasExtra && order.extra_account
                  ? { amount: order.extra_cost, account: `${order.extra_account.code} - ${order.extra_account.name}` }
                  : null
              }
            />
          )}
        </div>
      </div>

      <Card className="print:border-0 print:shadow-none">
        <CardContent className="grid gap-6">
          <CompanyHeader settings={settings} />

          <div className="flex flex-wrap items-center justify-between gap-3">
            <h1 className="flex items-center gap-2 text-xl font-bold">
              {title}
              {reversal && <Badge>ملغى</Badge>}
            </h1>
            <div className="text-sm">
              التاريخ: <span dir="ltr">{formatDate(order.doc_date)}</span>
            </div>
          </div>

          <dl className="grid gap-3 text-sm sm:grid-cols-[10rem_1fr]">
            <dt className="text-muted-foreground">المنتج</dt>
            <dd className="font-semibold">
              {order.item && (
                <Link
                  href={`/inventory/movements?item=${order.item.id}`}
                  className="underline-offset-4 hover:underline print:no-underline"
                >
                  {order.item.code} - {order.item.name}
                </Link>
              )}
            </dd>
            <dt className="text-muted-foreground">الوصفة</dt>
            <dd>
              {order.formula && (
                <Link
                  href={`/formulas/${order.formula.id}`}
                  className="underline-offset-4 hover:underline print:no-underline"
                >
                  {order.formula.name}
                </Link>
              )}{" "}
              — <span dir="ltr">{formatQty(order.batches)}</span> دفعة
            </dd>
            <dt className="text-muted-foreground">الكمية المنتجة</dt>
            <dd className="font-semibold">
              <span dir="ltr">{formatQty(order.qty_produced)}</span> {order.unit_name}
              {formatFactor(order.factor) !== "1" && (
                <span className="font-normal text-muted-foreground">
                  {" "}
                  (= <span dir="ltr">{formatQty(order.base_qty_produced)}</span> {unit})
                </span>
              )}
            </dd>
            {order.notes && (
              <>
                <dt className="text-muted-foreground">البيان</dt>
                <dd className="whitespace-pre-wrap">{order.notes}</dd>
              </>
            )}
          </dl>

          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>المادة</TableHead>
                  <TableHead className="text-end">المعياري من الوصفة</TableHead>
                  <TableHead className="text-end">المستهلك فعلًا</TableHead>
                  <TableHead className="text-end">الفرق (الهالك)</TableHead>
                  <TableHead className="text-end">تكلفة الوحدة</TableHead>
                  <TableHead className="text-end">التكلفة</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(lines ?? []).map((l) => {
                  const standard = roundQtyUnits(l.standard_base_qty);
                  const base = parseQty(l.base_qty) ?? 0n;
                  const diff = standard === null ? null : base - standard;
                  return (
                    <TableRow key={l.id}>
                      <TableCell>
                        {l.item && (
                          <Link
                            href={`/inventory/movements?item=${l.item.id}`}
                            className="underline-offset-4 hover:underline print:no-underline"
                          >
                            {l.item.code} - {l.item.name}
                          </Link>
                        )}
                      </TableCell>
                      <TableCell className="text-start tabular-nums">
                        {standard === null ? (
                          <span className="text-muted-foreground">ليست في الوصفة</span>
                        ) : (
                          <>
                            <span dir="ltr">{formatQtyUnits(standard)}</span> {l.item?.unit}
                          </>
                        )}
                      </TableCell>
                      <TableCell className="text-start tabular-nums">
                        <span dir="ltr">{formatQty(l.qty)}</span> {l.unit_name}
                        {formatFactor(l.factor) !== "1" && (
                          <div className="text-xs text-muted-foreground">
                            = <span dir="ltr">{formatQty(l.base_qty)}</span> {l.item?.unit}
                          </div>
                        )}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {diff === null ? `+${formatQtyUnits(base)}` : diff === 0n ? "0" : `${diff > 0n ? "+" : "-"}${formatQtyUnits(diff > 0n ? diff : -diff)}`}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {formatUnitCost(l.unit_cost)}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {formatAmount(l.total_cost)}
                      </TableCell>
                    </TableRow>
                  );
                })}
                <TableRow className="font-semibold hover:bg-transparent">
                  <TableCell colSpan={5}>تكلفة المواد</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatAmount(order.materials_cost)}
                  </TableCell>
                </TableRow>
                <TableRow className="hover:bg-transparent">
                  <TableCell colSpan={5}>
                    التكاليف الإضافية
                    {hasExtra && order.extra_account && (
                      <span className="text-muted-foreground">
                        {" "}
                        (دائن: {order.extra_account.code} - {order.extra_account.name})
                      </span>
                    )}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatAmount(order.extra_cost)}
                  </TableCell>
                </TableRow>
                <TableRow className="font-bold hover:bg-transparent">
                  <TableCell colSpan={5}>إجمالي تكلفة الإنتاج</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatAmount(order.total_cost)}
                  </TableCell>
                </TableRow>
                <TableRow className="font-bold hover:bg-transparent">
                  <TableCell colSpan={5}>تكلفة الوحدة (لكل {unit})</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatUnitCost(order.unit_cost)}
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
          <p className="text-xs text-muted-foreground">
            الكميات المعيارية والفرق بالوحدة الأساسية لكل مادة. المواد صُرفت بمتوسط تكلفتها وقت التسجيل، والهالك جزء
            من تكلفة المنتج.
          </p>

          <div className="grid gap-1 text-sm text-muted-foreground print:hidden">
            {entry && (
              <div>
                القيد المحاسبي:{" "}
                <Link href={`/journal/${entry.id}`} className="font-semibold text-foreground underline">
                  رقم {entry.entry_no}
                </Link>
              </div>
            )}
            {reversal && (
              <div>
                أُلغي بالقيد العكسي{" "}
                <Link href={`/journal/${reversal.id}`} className="font-semibold text-foreground underline">
                  رقم {reversal.entry_no}
                </Link>
              </div>
            )}
          </div>

          <div className="hidden grid-cols-2 gap-8 pt-10 text-center text-sm print:grid">
            <div className="border-t pt-2">مسؤول الإنتاج</div>
            <div className="border-t pt-2">المحاسب</div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
