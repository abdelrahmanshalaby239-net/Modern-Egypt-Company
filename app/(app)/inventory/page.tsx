import type { Metadata } from "next";
import Link from "next/link";

import { PrintHeader } from "@/components/print-header";
import { ReportTools } from "@/components/report-tools";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { formatDate, todayIso } from "@/lib/format";
import { ITEM_TYPES, ITEM_TYPE_ACCOUNT_KEYS, ITEM_TYPE_LABELS } from "@/lib/labels";
import { formatAmount, formatCents, plainCents, sumAmounts } from "@/lib/money";
import { formatQty, formatQtyUnits, formatUnitCost, parseQty, plainQty } from "@/lib/quantity";

export const metadata: Metadata = { title: "أرصدة المخزون" };

// الرصيد الحالي لكل صنف (كمية ومتوسط تكلفة وقيمة)، ومطابقة قيمة كل نوع مع حساب المخزون في الأستاذ.
// ?low=1 يعرض الأصناف النشطة التي رصيدها أقل من الحد الأدنى فقط.
export default async function InventoryPage({ searchParams }: PageProps<"/inventory">) {
  const { supabase } = await requireUser();
  const lowOnly = (await searchParams).low === "1";

  const [{ data: balances }, { data: system }, { data: trial }, { data: settings }, { data: minimums }] =
    await Promise.all([
      supabase.rpc("stock_balances"),
      supabase.from("system_accounts").select("key, account:accounts(id, code, name)"),
      supabase.rpc("trial_balance", {}),
      supabase.from("settings").select("company_name").eq("id", 1).single(),
      supabase.from("items").select("id, min_stock::text"),
    ]);

  const minOf = new Map((minimums ?? []).map((m) => [m.id, parseQty(m.min_stock) ?? 0n]));
  const isLow = (b: { item_id: number; qty: string; is_active: boolean }) => {
    const min = minOf.get(b.item_id) ?? 0n;
    return b.is_active && min > 0n && (parseQty(b.qty) ?? 0n) < min;
  };
  // المعطّل يظهر فقط لو له رصيد
  const rows = (balances ?? []).filter((b) => (b.is_active || b.qty !== "0.000") && (!lowOnly || isLow(b)));
  const lowCount = (balances ?? []).filter(isLow).length;
  const groups = ITEM_TYPES.map((type) => {
    const items = rows.filter((r) => r.type === type);
    const account = (system ?? []).find((s) => s.key === ITEM_TYPE_ACCOUNT_KEYS[type])?.account ?? null;
    const line = account ? (trial ?? []).find((t) => t.account_id === account.id) : undefined;
    const ledger = line ? sumAmounts([line.debit]) - sumAmounts([line.credit]) : 0n;
    // قيمة المخزون من كل الأصناف (حتى المعطّلة) لتطابق الأستاذ
    const value = sumAmounts((balances ?? []).filter((b) => b.type === type).map((b) => b.value));
    return { type, items, account, ledger, value };
  });
  const totalValue = groups.reduce((t, g) => t + g.value, 0n);
  const mismatch = groups.some((g) => g.ledger !== g.value);

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">أرصدة المخزون</h1>
        <div className="flex flex-wrap gap-2">
          <Button asChild variant="outline">
            {lowOnly ? (
              <Link href="/inventory">كل الأصناف</Link>
            ) : (
              <Link href="/inventory?low=1">تحت الحد الأدنى ({lowCount})</Link>
            )}
          </Button>
          <ReportTools
            filename={`أرصدة-المخزون-${todayIso()}.csv`}
            headers={["الكود", "الصنف", "النوع", "الوحدة", "الكمية", "الحد الأدنى", "متوسط التكلفة", "القيمة"]}
            rows={groups.flatMap((g) =>
              g.items.map((r) => [
                r.code,
                r.name,
                ITEM_TYPE_LABELS[g.type],
                r.unit,
                r.qty,
                (minOf.get(r.item_id) ?? 0n) > 0n ? plainQty(minOf.get(r.item_id) ?? 0n) : "",
                r.avg_cost,
                r.value,
              ]),
            )}
          />
        </div>
      </div>

      {lowOnly && (
        <Alert variant="warning" className="print:hidden">
          عرض الأصناف النشطة التي رصيدها أقل من الحد الأدنى المسجّل في بطاقة الصنف فقط.
        </Alert>
      )}

      <PrintHeader
        company={settings?.company_name ?? ""}
        title="أرصدة المخزون"
        subtitle={`في ${formatDate(todayIso())}`}
      />

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>الكود</TableHead>
              <TableHead>الصنف</TableHead>
              <TableHead>الوحدة</TableHead>
              <TableHead className="text-end">الكمية</TableHead>
              <TableHead className="text-end">الحد الأدنى</TableHead>
              <TableHead className="text-end">متوسط التكلفة</TableHead>
              <TableHead className="text-end">القيمة</TableHead>
            </TableRow>
          </TableHeader>
          {groups.map((g) => (
            <TableBody key={g.type}>
              <TableRow className="hover:bg-transparent">
                <TableCell colSpan={7} className="pt-4 font-bold">
                  {ITEM_TYPE_LABELS[g.type]}
                </TableCell>
              </TableRow>
              {g.items.map((r) => (
                <TableRow key={r.item_id}>
                  <TableCell dir="ltr" className="text-end font-mono">
                    {r.code}
                  </TableCell>
                  <TableCell>
                    <Link
                      href={`/inventory/movements?item=${r.item_id}`}
                      className="underline-offset-4 hover:underline print:no-underline"
                    >
                      {r.name}
                    </Link>
                    {!r.is_active && <span className="text-muted-foreground"> (معطّل)</span>}
                    {isLow(r) && <Badge className="ms-2">تحت الحد الأدنى</Badge>}
                  </TableCell>
                  <TableCell>{r.unit}</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatQty(r.qty)}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {(minOf.get(r.item_id) ?? 0n) > 0n ? formatQtyUnits(minOf.get(r.item_id) ?? 0n) : ""}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatUnitCost(r.avg_cost)}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatAmount(r.value)}
                  </TableCell>
                </TableRow>
              ))}
              {g.items.length === 0 && (
                <TableRow>
                  <TableCell colSpan={7} className="text-muted-foreground">
                    {lowOnly ? "لا توجد أصناف تحت الحد الأدنى." : "لا توجد أصناف."}
                  </TableCell>
                </TableRow>
              )}
              {!lowOnly && (
                <TableRow className="font-semibold hover:bg-transparent">
                  <TableCell colSpan={6}>إجمالي {ITEM_TYPE_LABELS[g.type]}</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatCents(g.value)}
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          ))}
          {!lowOnly && (
            <TableBody>
              <TableRow className="font-bold hover:bg-transparent">
                <TableCell colSpan={6}>إجمالي قيمة المخزون</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(totalValue)}
                </TableCell>
              </TableRow>
            </TableBody>
          )}
        </Table>
      </div>

      <h2 className="pt-2 font-bold">المطابقة مع الأستاذ العام</h2>
      <div className="max-w-3xl rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>حساب المخزون</TableHead>
              <TableHead className="text-end">رصيد الأستاذ</TableHead>
              <TableHead className="text-end">قيمة الأصناف</TableHead>
              <TableHead className="text-end">الفرق</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {groups.map((g) => (
              <TableRow key={g.type}>
                <TableCell>
                  {g.account ? (
                    <Link
                      href={`/ledger?account=${g.account.id}`}
                      className="underline-offset-4 hover:underline print:no-underline"
                    >
                      {g.account.code} - {g.account.name}
                    </Link>
                  ) : (
                    ITEM_TYPE_LABELS[g.type]
                  )}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(g.ledger)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(g.value)}
                </TableCell>
                <TableCell
                  dir="ltr"
                  className={`text-start tabular-nums ${g.ledger === g.value ? "text-success" : "text-destructive"}`}
                >
                  {formatAmount(plainCents(g.ledger - g.value))}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      {mismatch && (
        <Alert>
          قيمة المخزون لا تطابق رصيد حساب المخزون في الأستاذ. هذا لا يُفترض أن يحدث لأن قاعدة البيانات تفرض
          المطابقة عند كل اعتماد؛ راجع مسؤول النظام.
        </Alert>
      )}
    </div>
  );
}
