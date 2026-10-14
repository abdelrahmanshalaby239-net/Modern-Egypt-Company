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
import { formatDate, parseDate, yearStartIso } from "@/lib/format";
import { MOVEMENT_KIND_LABELS } from "@/lib/labels";
import { formatAmount } from "@/lib/money";
import { formatQty, formatUnitCost } from "@/lib/quantity";

export const metadata: Metadata = { title: "حركة صنف" };

const DOCUMENT_LABELS: Record<string, string> = {
  opening: "مخزون أول المدة",
  purchase: "فاتورة مشتريات",
  stock_adjustment: "تسوية جرد",
  production: "إنتاج",
  sale: "فاتورة مبيعات",
};

// رابط المستند الذي أنشأ الحركة (مخزون أول المدة: قيده الافتتاحي)
function documentHref(sourceType: string, sourceId: number | null, entryId: number | null): string | null {
  if (sourceType === "purchase" && sourceId) return `/purchases/${sourceId}`;
  if (sourceType === "stock_adjustment" && sourceId) return `/stock-adjustments/${sourceId}`;
  if (sourceType === "production" && sourceId) return `/production/${sourceId}`;
  if (sourceType === "sale" && sourceId) return `/sales/${sourceId}`;
  return entryId ? `/journal/${entryId}` : null;
}

export default async function ItemMovementsPage({ searchParams }: PageProps<"/inventory/movements">) {
  const { supabase } = await requireUser();
  const params = await searchParams;
  const itemId = Number(params.item) || null;
  const fromText = typeof params.from === "string" ? params.from : null;
  const toText = typeof params.to === "string" ? params.to : "";

  // الافتراضي: من أول السنة الحالية
  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const [{ data: items }, { data: settings }] = await Promise.all([
    supabase.from("items").select("id, code, name, unit").order("code"),
    supabase.from("settings").select("company_name").eq("id", 1).single(),
  ]);
  const item = (items ?? []).find((i) => i.id === itemId);

  const { data: rows } = item
    ? await supabase.rpc("item_movements", { p_item_id: item.id, p_from: from ?? undefined, p_to: to ?? undefined })
    : { data: null };
  const period = [from && `من ${formatDate(from)}`, to && `إلى ${formatDate(to)}`].filter(Boolean).join(" ");

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">حركة صنف</h1>
        {item && (
          <ReportTools
            filename={`حركة-صنف-${item.code}.csv`}
            headers={["التاريخ", "الحركة", "المستند", "وارد", "منصرف", "تكلفة الوحدة", "القيمة", "رصيد الكمية", "رصيد القيمة"]}
            rows={(rows ?? []).map((r) => [
              formatDate(r.movement_date),
              r.kind ? (MOVEMENT_KIND_LABELS[r.kind] ?? r.kind) : "رصيد أول المدة",
              r.doc_no ? String(r.doc_no) : "",
              r.qty_in ?? "",
              r.qty_out ?? "",
              r.unit_cost ?? "",
              r.total_cost ?? "",
              r.balance_qty,
              r.balance_value,
            ])}
          />
        )}
      </div>

      <form className="flex flex-wrap items-end gap-3 print:hidden">
        <div className="grid gap-1">
          <Label htmlFor="item">الصنف</Label>
          <NativeSelect id="item" name="item" defaultValue={item ? String(item.id) : ""} className="w-72">
            <option value="">اختر الصنف</option>
            {(items ?? []).map((i) => (
              <option key={i.id} value={i.id}>
                {i.code} - {i.name}
              </option>
            ))}
          </NativeSelect>
        </div>
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
      {!item && !invalidDate && <p className="text-sm text-muted-foreground">اختر الصنف لعرض حركته.</p>}

      {item && !invalidDate && (
        <>
          <PrintHeader
            company={settings?.company_name ?? ""}
            title={`حركة صنف: ${item.code} - ${item.name} (${item.unit})`}
            subtitle={period}
          />
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>التاريخ</TableHead>
                  <TableHead>الحركة</TableHead>
                  <TableHead className="text-end">وارد</TableHead>
                  <TableHead className="text-end">منصرف</TableHead>
                  <TableHead className="text-end">تكلفة الوحدة</TableHead>
                  <TableHead className="text-end">القيمة</TableHead>
                  <TableHead className="text-end">رصيد الكمية</TableHead>
                  <TableHead className="text-end">رصيد القيمة</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(rows ?? []).map((r, i) => {
                  const href = r.source_type ? documentHref(r.source_type, r.source_id, r.journal_entry_id) : null;
                  const document = r.source_type
                    ? `${DOCUMENT_LABELS[r.source_type] ?? r.source_type}${r.doc_no ? ` رقم ${r.doc_no}` : ""}`
                    : "";
                  return (
                    <TableRow key={r.movement_id ?? `opening-${i}`}>
                      <TableCell dir="ltr" className="text-end">
                        {formatDate(r.movement_date)}
                      </TableCell>
                      <TableCell className="whitespace-normal">
                        {r.kind ? (
                          <>
                            {r.kind === "reversal" ? "إلغاء " : ""}
                            {href ? (
                              <Link href={href} className="underline-offset-4 hover:underline print:no-underline">
                                {document}
                              </Link>
                            ) : (
                              document
                            )}
                          </>
                        ) : (
                          <span className="font-semibold">رصيد أول المدة</span>
                        )}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {r.qty_in && r.qty_in !== "0.000" ? formatQty(r.qty_in) : ""}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {r.qty_out && r.qty_out !== "0.000" ? formatQty(r.qty_out) : ""}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {formatUnitCost(r.unit_cost)}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {formatAmount(r.total_cost)}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {formatQty(r.balance_qty)}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {formatAmount(r.balance_value)}
                      </TableCell>
                    </TableRow>
                  );
                })}
                {(rows ?? []).length <= 1 && (
                  <TableRow>
                    <TableCell colSpan={8} className="py-6 text-center text-muted-foreground">
                      لا توجد حركات في هذه الفترة.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
          <p className="text-xs text-muted-foreground print:hidden">
            الرصيد الجاري مرتب بتاريخ المستند. متوسط التكلفة يُحسب بترتيب الإدخال الفعلي، فقد يختلف الرصيد
            الجاري مؤقتًا عن الواقع عند إدخال مستند بتاريخ سابق.
          </p>
        </>
      )}
    </div>
  );
}
