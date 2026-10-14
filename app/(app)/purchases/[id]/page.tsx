import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

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
import { formatQty, formatUnitCost } from "@/lib/quantity";
import { CancelPurchaseButton } from "./cancel-purchase-button";

export const metadata: Metadata = { title: "فاتورة مشتريات" };

// صفحة الفاتورة وطباعتها (SPEC §8)
export default async function PurchaseInvoicePage({ params }: PageProps<"/purchases/[id]">) {
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();

  const { supabase } = await requireUser();
  const { data: invoice } = await supabase
    .from("purchase_invoices")
    .select("id, doc_no, doc_date, total::text, notes, journal_entry_id, payment_voucher_id, supplier:suppliers(id, name)")
    .eq("id", id)
    .maybeSingle();
  if (!invoice) notFound();

  const [{ data: lines }, { data: entry }, { data: reversal }, { data: voucher }, { data: settings }] =
    await Promise.all([
      supabase
        .from("purchase_invoice_lines")
        .select("id, qty::text, unit_price::text, line_total::text, item:items(id, code, name, unit)")
        .eq("invoice_id", id)
        .order("id"),
      supabase.from("journal_entries").select("id, entry_no").eq("id", invoice.journal_entry_id).single(),
      supabase
        .from("journal_entries")
        .select("id, entry_no")
        .eq("reverses_entry_id", invoice.journal_entry_id)
        .maybeSingle(),
      invoice.payment_voucher_id
        ? supabase
            .from("vouchers")
            .select("id, doc_no, journal_entry_id")
            .eq("id", invoice.payment_voucher_id)
            .maybeSingle()
        : Promise.resolve({ data: null }),
      supabase
        .from("settings")
        .select("company_name, company_address, company_phone, currency_symbol")
        .eq("id", 1)
        .single(),
    ]);
  // سند «مدفوع الآن» ملغى = لقيده قيد عكسي
  const { data: voucherReversal } = voucher
    ? await supabase.from("journal_entries").select("id").eq("reverses_entry_id", voucher.journal_entry_id).maybeSingle()
    : { data: null };
  const activeVoucher = voucher && !voucherReversal ? { id: voucher.id, doc_no: voucher.doc_no } : null;

  const title = `فاتورة مشتريات رقم ${invoice.doc_no}`;

  return (
    <div className="grid max-w-4xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link href="/purchases" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
          ← فواتير المشتريات
        </Link>
        <div className="flex gap-2">
          <PrintButton />
          {!reversal && <CancelPurchaseButton id={invoice.id} title={title} voucher={activeVoucher} />}
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
              التاريخ: <span dir="ltr">{formatDate(invoice.doc_date)}</span>
            </div>
          </div>

          <dl className="grid gap-3 text-sm sm:grid-cols-[10rem_1fr]">
            <dt className="text-muted-foreground">المورد</dt>
            <dd className="font-semibold">
              {invoice.supplier && (
                <Link
                  href={`/ledger?supplier=${invoice.supplier.id}`}
                  className="underline-offset-4 hover:underline print:no-underline"
                >
                  {invoice.supplier.name}
                </Link>
              )}
            </dd>
            <dt className="text-muted-foreground">السداد</dt>
            <dd>{invoice.payment_voucher_id ? "مدفوعة الآن" : "آجل"}</dd>
            {invoice.notes && (
              <>
                <dt className="text-muted-foreground">البيان</dt>
                <dd className="whitespace-pre-wrap">{invoice.notes}</dd>
              </>
            )}
          </dl>

          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>الصنف</TableHead>
                  <TableHead>الوحدة</TableHead>
                  <TableHead className="text-end">الكمية</TableHead>
                  <TableHead className="text-end">سعر الوحدة</TableHead>
                  <TableHead className="text-end">الإجمالي</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(lines ?? []).map((l) => (
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
                    <TableCell>{l.item?.unit}</TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatQty(l.qty)}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatUnitCost(l.unit_price)}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatAmount(l.line_total)}
                    </TableCell>
                  </TableRow>
                ))}
                <TableRow className="font-bold hover:bg-transparent">
                  <TableCell colSpan={4}>إجمالي الفاتورة</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatAmount(invoice.total)} {settings?.currency_symbol}
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>

          <div className="grid gap-1 text-sm text-muted-foreground print:hidden">
            {entry && (
              <div>
                القيد المحاسبي:{" "}
                <Link href={`/journal/${entry.id}`} className="font-semibold text-foreground underline">
                  رقم {entry.entry_no}
                </Link>
              </div>
            )}
            {voucher && (
              <div>
                سُددت بـ{" "}
                <Link href={`/vouchers/payment/${voucher.id}`} className="font-semibold text-foreground underline">
                  سند الصرف رقم {voucher.doc_no}
                </Link>
                {voucherReversal ? " (ملغى)" : reversal ? " — السند ما زال ساريًا ويُلغى من صفحته عند الحاجة" : ""}
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
