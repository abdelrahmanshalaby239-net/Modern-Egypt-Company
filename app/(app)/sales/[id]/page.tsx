import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CompanyHeader } from "@/components/company-header";
import { PrintButton } from "@/components/print-button";
import { Alert } from "@/components/ui/alert";
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
import { PAYMENT_STATUS_LABELS, paymentStatus } from "@/lib/labels";
import { formatAmount, formatBalance, formatCents, sumAmounts } from "@/lib/money";
import { formatFactor, formatQty } from "@/lib/quantity";
import { CancelSalesButton } from "./cancel-sales-button";

export const metadata: Metadata = { title: "فاتورة مبيعات" };

// صفحة الفاتورة وطباعتها (SPEC §8)
export default async function SalesInvoicePage({ params }: PageProps<"/sales/[id]">) {
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();

  const { supabase } = await requireUser();
  const { data: invoice } = await supabase
    .from("sales_invoices")
    .select(
      "id, doc_no, doc_date, total::text, paid_amount::text, notes, journal_entry_id, receipt_voucher_id, customer:customers(id, name, phone, address)",
    )
    .eq("id", id)
    .maybeSingle();
  if (!invoice) notFound();

  const [
    { data: lines },
    { data: entry },
    { data: reversal },
    { data: voucher },
    { data: settings },
    { data: customerBalances },
  ] = await Promise.all([
    supabase
      .from("sales_invoice_lines")
      .select(
        "id, unit_name, factor::text, qty::text, base_qty::text, unit_price::text, line_total::text, cost_total::text, item:items(id, code, name, unit)",
      )
      .eq("invoice_id", id)
      .order("id"),
    supabase.from("journal_entries").select("id, entry_no").eq("id", invoice.journal_entry_id).single(),
    supabase.from("journal_entries").select("id, entry_no").eq("reverses_entry_id", invoice.journal_entry_id).maybeSingle(),
    invoice.receipt_voucher_id
      ? supabase
          .from("vouchers")
          .select("id, doc_no, amount::text, journal_entry_id")
          .eq("id", invoice.receipt_voucher_id)
          .maybeSingle()
      : Promise.resolve({ data: null }),
    supabase
      .from("settings")
      .select("company_name, company_address, company_phone, currency_symbol")
      .eq("id", 1)
      .single(),
    supabase.rpc("party_balances", { p_party_kind: "customer" }),
  ]);
  // سند «المقبوض الآن» ملغى = لقيده قيد عكسي
  const { data: voucherReversal } = voucher
    ? await supabase.from("journal_entries").select("id").eq("reverses_entry_id", voucher.journal_entry_id).maybeSingle()
    : { data: null };
  const activeVoucher =
    voucher && !voucherReversal ? { id: voucher.id, doc_no: voucher.doc_no, amount: voucher.amount } : null;

  // التحصيل كما كان عند الاعتماد (لا يتغير بسندات لاحقة)، ورصيد العميل الحالي من كل فواتيره وسنداته
  const totalCents = sumAmounts([invoice.total]);
  const paidCents = sumAmounts([invoice.paid_amount]);
  const status = paymentStatus(totalCents, paidCents);
  const costCents = sumAmounts((lines ?? []).map((l) => l.cost_total));
  const customerBalance =
    (customerBalances ?? []).find((b) => b.party_id === invoice.customer?.id)?.balance ?? "0.00";

  const title = `فاتورة مبيعات رقم ${invoice.doc_no}`;

  return (
    <div className="grid max-w-4xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link href="/sales" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
          ← فواتير المبيعات
        </Link>
        <div className="flex gap-2">
          <PrintButton />
          {!reversal && <CancelSalesButton id={invoice.id} title={title} voucher={activeVoucher} />}
        </div>
      </div>

      <Card className="print:border-0 print:shadow-none">
        <CardContent className="grid gap-6">
          <CompanyHeader settings={settings} />

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
            <dt className="text-muted-foreground">العميل</dt>
            <dd className="font-semibold">
              {invoice.customer && (
                <Link
                  href={`/ledger?customer=${invoice.customer.id}`}
                  className="underline-offset-4 hover:underline print:no-underline"
                >
                  {invoice.customer.name}
                </Link>
              )}
              {(invoice.customer?.address || invoice.customer?.phone) && (
                <div className="font-normal text-muted-foreground">
                  {[invoice.customer?.address, invoice.customer?.phone].filter(Boolean).join(" · ")}
                </div>
              )}
            </dd>
            <dt className="text-muted-foreground">حالة السداد عند الاعتماد</dt>
            <dd className="font-semibold">{PAYMENT_STATUS_LABELS[status]}</dd>
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
                    <TableCell>{l.item && `${l.item.code} - ${l.item.name}`}</TableCell>
                    <TableCell>{l.unit_name}</TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatQty(l.qty)}
                      {formatFactor(l.factor) !== "1" && (
                        <div className="text-xs text-muted-foreground print:hidden">
                          = {formatQty(l.base_qty)} {l.item?.unit}
                        </div>
                      )}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {formatAmount(l.unit_price)}
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
                <TableRow className="hover:bg-transparent">
                  <TableCell colSpan={4}>المقبوض عند الاعتماد</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatAmount(invoice.paid_amount)}
                  </TableCell>
                </TableRow>
                <TableRow className="hover:bg-transparent">
                  <TableCell colSpan={4}>المتبقي عند الاعتماد (آجل على العميل)</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatCents(totalCents - paidCents)}
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>

          {reversal && activeVoucher && (
            <Alert variant="warning" className="print:hidden">
              الفاتورة ملغاة، وسند القبض رقم {activeVoucher.doc_no} بمبلغ {formatAmount(activeVoucher.amount)} ما زال
              ساريًا: المبلغ رصيد دائن للعميل (مقبوض مقدمًا). عند إدخال الفاتورة المصححة اترك المقبوض الآن صفرًا حتى لا
              يتكرر التحصيل، أو ألغِ السند من صفحته لو لم يُقبض المبلغ فعلًا.
            </Alert>
          )}

          <div className="grid gap-1 text-sm text-muted-foreground print:hidden">
            {invoice.customer && (
              <div>
                رصيد العميل الحالي (من كل فواتيره وسنداته):{" "}
                <Link
                  href={`/ledger?customer=${invoice.customer.id}`}
                  className="font-semibold text-foreground underline"
                >
                  <span dir="ltr">{formatBalance(customerBalance)}</span>
                </Link>
                . المتبقي عند الاعتماد لا يتغير بالسندات اللاحقة لأنها لا تُخصص لفاتورة بعينها.
              </div>
            )}
            <div>
              تكلفة المبيعات (بمتوسط التكلفة وقت البيع): <span dir="ltr">{formatCents(costCents)}</span> — مجمل الربح:{" "}
              <span dir="ltr">{formatCents(totalCents - costCents)}</span>
            </div>
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
                المقبوض عند الاعتماد بـ{" "}
                <Link href={`/vouchers/receipt/${voucher.id}`} className="font-semibold text-foreground underline">
                  سند القبض رقم {voucher.doc_no}
                </Link>
                {voucherReversal ? " (السند ملغى، فالتحصيل لم يعد قائمًا)" : ""}
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
            <div className="border-t pt-2">المستلم</div>
            <div className="border-t pt-2">المحاسب</div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
