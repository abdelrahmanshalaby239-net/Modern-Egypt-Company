import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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
import { SOURCE_TYPE_LABELS } from "@/lib/labels";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";
import { CancelEntryButton } from "./cancel-entry-button";

export const metadata: Metadata = { title: "قيد يومية" };

const CANCELLABLE = ["manual", "adjustment", "opening"];

export default async function JournalEntryPage({ params }: PageProps<"/journal/[id]">) {
  const { supabase } = await requireUser();
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();

  const { data: entry } = await supabase
    .from("journal_entries")
    .select("id, entry_no, entry_date, description, source_type, reverses_entry_id")
    .eq("id", id)
    .maybeSingle();
  if (!entry) notFound();

  const [{ data: lines }, { data: reversal }, { data: original }] = await Promise.all([
    supabase
      .from("journal_lines")
      .select("id, debit::text, credit::text, description, account:accounts(id, code, name)")
      .eq("entry_id", id)
      .order("id"),
    supabase.from("journal_entries").select("id, entry_no").eq("reverses_entry_id", id).maybeSingle(),
    entry.reverses_entry_id
      ? supabase
          .from("journal_entries")
          .select("id, entry_no")
          .eq("id", entry.reverses_entry_id)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  const totalDebit = sumAmounts((lines ?? []).map((l) => l.debit));
  const totalCredit = sumAmounts((lines ?? []).map((l) => l.credit));
  const canCancel = CANCELLABLE.includes(entry.source_type) && !reversal;

  return (
    <div className="grid max-w-4xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">قيد رقم {entry.entry_no}</h1>
        {canCancel && <CancelEntryButton id={entry.id} entryNo={entry.entry_no} />}
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex flex-wrap items-center gap-2">
            {entry.description}
            {reversal && <Badge>ملغى</Badge>}
            {original && <Badge>قيد عكسي</Badge>}
          </CardTitle>
        </CardHeader>
        <CardContent className="grid gap-1 text-sm text-muted-foreground">
          <div>
            التاريخ: <span dir="ltr">{formatDate(entry.entry_date)}</span> · النوع:{" "}
            {SOURCE_TYPE_LABELS[entry.source_type] ?? entry.source_type}
          </div>
          {reversal && (
            <div>
              أُلغي بالقيد العكسي{" "}
              <Link href={`/journal/${reversal.id}`} className="font-semibold text-foreground underline">
                رقم {reversal.entry_no}
              </Link>
            </div>
          )}
          {original && (
            <div>
              يلغي القيد{" "}
              <Link href={`/journal/${original.id}`} className="font-semibold text-foreground underline">
                رقم {original.entry_no}
              </Link>
            </div>
          )}
        </CardContent>
      </Card>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>الحساب</TableHead>
              <TableHead>ملاحظة</TableHead>
              <TableHead className="text-end">مدين</TableHead>
              <TableHead className="text-end">دائن</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(lines ?? []).map((l) => (
              <TableRow key={l.id}>
                <TableCell>
                  {l.account && (
                    <Link
                      href={`/ledger?account=${l.account.id}`}
                      className="underline-offset-4 hover:underline"
                    >
                      {l.account.code} - {l.account.name}
                    </Link>
                  )}
                </TableCell>
                <TableCell className="text-muted-foreground">{l.description}</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {l.debit === "0.00" ? "" : formatAmount(l.debit)}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {l.credit === "0.00" ? "" : formatAmount(l.credit)}
                </TableCell>
              </TableRow>
            ))}
            <TableRow className="font-bold hover:bg-transparent">
              <TableCell colSpan={2}>الإجمالي</TableCell>
              <TableCell dir="ltr" className="text-start tabular-nums">
                {formatCents(totalDebit)}
              </TableCell>
              <TableCell dir="ltr" className="text-start tabular-nums">
                {formatCents(totalCredit)}
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
