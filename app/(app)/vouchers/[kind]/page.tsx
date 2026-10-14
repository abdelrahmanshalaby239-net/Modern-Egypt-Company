import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

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
import { COUNTERPART_LABELS, VOUCHER_LABELS, isVoucherKind } from "@/lib/labels";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";

export async function generateMetadata({ params }: PageProps<"/vouchers/[kind]">): Promise<Metadata> {
  const { kind } = await params;
  return { title: isVoucherKind(kind) ? VOUCHER_LABELS[kind].many : "السندات" };
}

export default async function VouchersPage({ params, searchParams }: PageProps<"/vouchers/[kind]">) {
  const { kind } = await params;
  if (!isVoucherKind(kind)) notFound();
  const labels = VOUCHER_LABELS[kind];

  const { supabase } = await requireUser();
  const query = await searchParams;
  const fromText = typeof query.from === "string" ? query.from : null;
  const toText = typeof query.to === "string" ? query.to : "";
  const q = typeof query.q === "string" ? query.q.trim() : "";

  // الافتراضي: من أول السنة الحالية
  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const { data: vouchers } = await supabase.rpc("voucher_list", {
    p_kind: kind,
    p_from: from ?? undefined,
    p_to: to ?? undefined,
    p_search: q || undefined,
  });
  const total = sumAmounts((vouchers ?? []).filter((v) => !v.is_cancelled).map((v) => v.amount));

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">{labels.many}</h1>
        <Button asChild>
          <Link href={`/vouchers/${kind}/new`}>{labels.one} جديد</Link>
        </Button>
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
          <Input id="q" name="q" defaultValue={q} placeholder="رقم السند أو الطرف أو البيان" className="w-60" />
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
              <TableHead>رقم السند</TableHead>
              <TableHead>التاريخ</TableHead>
              <TableHead>{labels.party}</TableHead>
              <TableHead>الخزينة/البنك</TableHead>
              <TableHead>البيان</TableHead>
              <TableHead className="text-end">المبلغ</TableHead>
              <TableHead>الحالة</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(vouchers ?? []).map((v) => (
              <TableRow key={v.id}>
                <TableCell>
                  <Link href={`/vouchers/${kind}/${v.id}`} className="font-semibold underline-offset-4 hover:underline">
                    {v.doc_no}
                  </Link>
                </TableCell>
                <TableCell dir="ltr" className="text-end">
                  {formatDate(v.doc_date)}
                </TableCell>
                <TableCell className="whitespace-normal">
                  <span className="text-muted-foreground">{COUNTERPART_LABELS[v.party_kind]}: </span>
                  {v.party_name}
                </TableCell>
                <TableCell>{v.treasury}</TableCell>
                <TableCell className="whitespace-normal">{v.notes}</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(v.amount)}
                </TableCell>
                <TableCell>{v.is_cancelled && <Badge>ملغى</Badge>}</TableCell>
              </TableRow>
            ))}
            {(vouchers ?? []).length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} className="py-6 text-center text-muted-foreground">
                  لا توجد سندات في هذه الفترة.
                </TableCell>
              </TableRow>
            ) : (
              <TableRow className="font-bold hover:bg-transparent">
                <TableCell colSpan={5}>الإجمالي (بدون الملغى)</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatCents(total)}
                </TableCell>
                <TableCell />
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
