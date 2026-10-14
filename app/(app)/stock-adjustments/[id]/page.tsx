import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { PrintButton } from "@/components/print-button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { requireUser } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import { formatAmount } from "@/lib/money";
import { formatQty, formatUnitCost, parseQty, plainQty } from "@/lib/quantity";
import { CancelAdjustmentButton } from "./cancel-adjustment-button";

export const metadata: Metadata = { title: "تسوية جرد" };

export default async function StockAdjustmentPage({ params }: PageProps<"/stock-adjustments/[id]">) {
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();

  const { supabase } = await requireUser();
  const { data: adjustment } = await supabase
    .from("stock_adjustments")
    .select(
      "id, doc_no, doc_date, system_qty::text, counted_qty::text, unit_cost::text, total_cost::text, notes, journal_entry_id, item:items(id, code, name, unit)",
    )
    .eq("id", id)
    .maybeSingle();
  if (!adjustment) notFound();

  const [{ data: entry }, { data: reversal }, { data: settings }] = await Promise.all([
    supabase.from("journal_entries").select("id, entry_no").eq("id", adjustment.journal_entry_id).single(),
    supabase
      .from("journal_entries")
      .select("id, entry_no")
      .eq("reverses_entry_id", adjustment.journal_entry_id)
      .maybeSingle(),
    supabase
      .from("settings")
      .select("company_name, company_address, company_phone, currency_symbol")
      .eq("id", 1)
      .single(),
  ]);

  const title = `تسوية الجرد رقم ${adjustment.doc_no}`;
  const diff = (parseQty(adjustment.counted_qty) ?? 0n) - (parseQty(adjustment.system_qty) ?? 0n);
  const unit = adjustment.item?.unit ?? "";

  return (
    <div className="grid max-w-3xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link href="/stock-adjustments" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
          ← تسوية الجرد
        </Link>
        <div className="flex gap-2">
          <PrintButton />
          {!reversal && <CancelAdjustmentButton id={adjustment.id} title={title} />}
        </div>
      </div>

      <Card className="print:border-0 print:shadow-none">
        <CardContent className="grid gap-6">
          <div className="border-b pb-4 text-center">
            <div className="text-lg font-bold">{settings?.company_name}</div>
            {(settings?.company_address || settings?.company_phone) && (
              <div className="text-sm text-muted-foreground">
                {[settings?.company_address, settings?.company_phone].filter(Boolean).join(" · ")}
              </div>
            )}
          </div>

          <div className="flex flex-wrap items-center justify-between gap-3">
            <h1 className="flex items-center gap-2 text-xl font-bold">
              {title}
              {reversal && <Badge>ملغاة</Badge>}
            </h1>
            <div className="text-sm">
              التاريخ: <span dir="ltr">{formatDate(adjustment.doc_date)}</span>
            </div>
          </div>

          <dl className="grid gap-3 text-sm sm:grid-cols-[10rem_1fr]">
            <dt className="text-muted-foreground">الصنف</dt>
            <dd className="font-semibold">
              {adjustment.item && (
                <Link
                  href={`/inventory/movements?item=${adjustment.item.id}`}
                  className="underline-offset-4 hover:underline print:no-underline"
                >
                  {adjustment.item.code} - {adjustment.item.name}
                </Link>
              )}
            </dd>
            <dt className="text-muted-foreground">رصيد النظام</dt>
            <dd className="tabular-nums">
              <span dir="ltr">{formatQty(adjustment.system_qty)}</span> {unit}
            </dd>
            <dt className="text-muted-foreground">الكمية الفعلية</dt>
            <dd className="tabular-nums">
              <span dir="ltr">{formatQty(adjustment.counted_qty)}</span> {unit}
            </dd>
            <dt className="text-muted-foreground">{diff < 0n ? "العجز" : "الزيادة"}</dt>
            <dd className="font-semibold tabular-nums">
              <span dir="ltr">{formatQty(plainQty(diff < 0n ? -diff : diff))}</span> {unit}
            </dd>
            <dt className="text-muted-foreground">تكلفة الوحدة</dt>
            <dd className="tabular-nums">
              <span dir="ltr">{formatUnitCost(adjustment.unit_cost)}</span>
            </dd>
            <dt className="text-muted-foreground">القيمة</dt>
            <dd className="text-lg font-bold tabular-nums">
              <span dir="ltr">{formatAmount(adjustment.total_cost)}</span> {settings?.currency_symbol}
            </dd>
            {adjustment.notes && (
              <>
                <dt className="text-muted-foreground">البيان</dt>
                <dd className="whitespace-pre-wrap">{adjustment.notes}</dd>
              </>
            )}
          </dl>

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
                أُلغيت بالقيد العكسي{" "}
                <Link href={`/journal/${reversal.id}`} className="font-semibold text-foreground underline">
                  رقم {reversal.entry_no}
                </Link>
              </div>
            )}
          </div>

          <div className="hidden grid-cols-2 gap-8 pt-10 text-center text-sm print:grid">
            <div className="border-t pt-2">أمين المخزن</div>
            <div className="border-t pt-2">المحاسب</div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
