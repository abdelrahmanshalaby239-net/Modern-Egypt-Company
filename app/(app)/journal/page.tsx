import type { Metadata } from "next";
import Link from "next/link";

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
import { SOURCE_TYPE_LABELS } from "@/lib/labels";
import { formatAmount } from "@/lib/money";

export const metadata: Metadata = { title: "قيود اليومية" };

export default async function JournalPage({ searchParams }: PageProps<"/journal">) {
  const { supabase } = await requireUser();
  const params = await searchParams;
  const fromText = typeof params.from === "string" ? params.from : null;
  const toText = typeof params.to === "string" ? params.to : "";
  const q = typeof params.q === "string" ? params.q.trim() : "";

  // الافتراضي: من أول السنة الحالية
  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const { data: entries } = await supabase.rpc("journal_entry_list", {
    p_from: from ?? undefined,
    p_to: to ?? undefined,
    p_search: q || undefined,
  });

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">قيود اليومية</h1>
        <Button asChild>
          <Link href="/journal/new">قيد يدوي جديد</Link>
        </Button>
      </div>

      <form className="filter-bar flex flex-wrap items-end gap-3">
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
          <Input id="q" name="q" defaultValue={q} placeholder="رقم القيد أو البيان" className="w-56" />
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
              <TableHead>رقم القيد</TableHead>
              <TableHead>التاريخ</TableHead>
              <TableHead>النوع</TableHead>
              <TableHead>البيان</TableHead>
              <TableHead className="text-end">المبلغ</TableHead>
              <TableHead>الحالة</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(entries ?? []).map((e) => (
              <TableRow key={e.id}>
                <TableCell>
                  <Link href={`/journal/${e.id}`} className="font-semibold underline-offset-4 hover:underline">
                    {e.entry_no}
                  </Link>
                </TableCell>
                <TableCell dir="ltr" className="text-end">
                  {formatDate(e.entry_date)}
                </TableCell>
                <TableCell>{SOURCE_TYPE_LABELS[e.source_type] ?? e.source_type}</TableCell>
                <TableCell className="whitespace-normal">{e.description}</TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {formatAmount(e.total)}
                </TableCell>
                <TableCell>
                  {e.reversed_by_entry_id && <Badge>ملغى</Badge>}
                  {e.reverses_entry_id && <Badge>قيد عكسي</Badge>}
                </TableCell>
              </TableRow>
            ))}
            {(entries ?? []).length === 0 && (
              <TableRow>
                <TableCell colSpan={6} className="py-6 text-center text-muted-foreground">
                  لا توجد قيود في هذه الفترة.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
