import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CompanyHeader } from "@/components/company-header";
import { PrintButton } from "@/components/print-button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { requireUser } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import { VOUCHER_LABELS, isVoucherKind } from "@/lib/labels";
import { formatAmount } from "@/lib/money";
import { CancelVoucherButton } from "./cancel-voucher-button";

export const metadata: Metadata = { title: "سند" };

// صفحة السند وطباعته (SPEC §8: كل سند له صفحة طباعة)
export default async function VoucherPage({ params }: PageProps<"/vouchers/[kind]/[id]">) {
  const { kind, id: idText } = await params;
  const id = Number(idText);
  if (!isVoucherKind(kind) || !Number.isInteger(id)) notFound();
  const labels = VOUCHER_LABELS[kind];

  const { supabase } = await requireUser();
  const { data: voucher } = await supabase
    .from("vouchers")
    .select(
      "id, doc_no, doc_date, amount::text, notes, journal_entry_id, treasury:accounts!vouchers_treasury_account_id_fkey(id, code, name), account:accounts!vouchers_account_id_fkey(id, code, name), customer:customers(id, name), supplier:suppliers(id, name)",
    )
    .eq("id", id)
    .eq("kind", kind)
    .maybeSingle();
  if (!voucher) notFound();

  const [{ data: entry }, { data: reversal }, { data: settings }] = await Promise.all([
    supabase.from("journal_entries").select("id, entry_no").eq("id", voucher.journal_entry_id).single(),
    supabase
      .from("journal_entries")
      .select("id, entry_no")
      .eq("reverses_entry_id", voucher.journal_entry_id)
      .maybeSingle(),
    supabase
      .from("settings")
      .select("company_name, company_address, company_phone, currency_symbol")
      .eq("id", 1)
      .single(),
  ]);

  const title = `${labels.one} رقم ${voucher.doc_no}`;
  const partyName = voucher.customer?.name ?? voucher.supplier?.name ??
    (voucher.account ? `${voucher.account.code} - ${voucher.account.name}` : "");
  const partyHref = voucher.customer
    ? `/ledger?customer=${voucher.customer.id}`
    : voucher.supplier
      ? `/ledger?supplier=${voucher.supplier.id}`
      : voucher.account
        ? `/ledger?account=${voucher.account.id}`
        : null;
  const partyPrefix = voucher.customer ? "العميل: " : voucher.supplier ? "المورد: " : "حساب: ";

  return (
    <div className="grid max-w-3xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link href={`/vouchers/${kind}`} className="text-sm text-muted-foreground underline-offset-4 hover:underline">
          ← {labels.many}
        </Link>
        <div className="flex gap-2">
          <PrintButton />
          {!reversal && <CancelVoucherButton kind={kind} id={voucher.id} title={title} />}
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
              التاريخ: <span dir="ltr">{formatDate(voucher.doc_date)}</span>
            </div>
          </div>

          <dl className="grid gap-3 text-sm sm:grid-cols-[10rem_1fr]">
            <dt className="text-muted-foreground">{labels.party}</dt>
            <dd className="font-semibold">
              <span className="font-normal text-muted-foreground">{partyPrefix}</span>
              {partyHref ? (
                <Link href={partyHref} className="underline-offset-4 hover:underline print:no-underline">
                  {partyName}
                </Link>
              ) : (
                partyName
              )}
            </dd>
            <dt className="text-muted-foreground">المبلغ</dt>
            <dd className="text-lg font-bold tabular-nums">
              <span dir="ltr">{formatAmount(voucher.amount)}</span> {settings?.currency_symbol}
            </dd>
            <dt className="text-muted-foreground">{kind === "receipt" ? "إلى الخزينة/البنك" : "من الخزينة/البنك"}</dt>
            <dd>
              {voucher.treasury?.code} - {voucher.treasury?.name}
            </dd>
            {voucher.notes && (
              <>
                <dt className="text-muted-foreground">البيان</dt>
                <dd className="whitespace-pre-wrap">{voucher.notes}</dd>
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
                أُلغي بالقيد العكسي{" "}
                <Link href={`/journal/${reversal.id}`} className="font-semibold text-foreground underline">
                  رقم {reversal.entry_no}
                </Link>
              </div>
            )}
          </div>

          <div className="hidden grid-cols-2 gap-8 pt-10 text-center text-sm print:grid">
            <div className="border-t pt-2">{kind === "receipt" ? "المُسلِّم" : "المستلم"}</div>
            <div className="border-t pt-2">المحاسب</div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
