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
import { SOURCE_TYPE_LABELS } from "@/lib/labels";
import { formatAmount, formatBalance, formatCents, sumAmounts } from "@/lib/money";

export const metadata: Metadata = { title: "كشف حساب" };

export default async function LedgerPage({ searchParams }: PageProps<"/ledger">) {
  const { supabase } = await requireUser();
  const params = await searchParams;
  const accountId = Number(params.account) || null;
  const fromText = typeof params.from === "string" ? params.from : null;
  const toText = typeof params.to === "string" ? params.to : "";

  // الافتراضي: من أول السنة الحالية
  const from = fromText === null ? yearStartIso() : fromText ? parseDate(fromText) : null;
  const to = toText ? parseDate(toText) : null;
  const invalidDate = (fromText && !from) || (toText && !to);

  const [{ data: accounts }, { data: settings }] = await Promise.all([
    supabase.from("accounts").select("id, code, name").eq("is_postable", true).order("code"),
    supabase.from("settings").select("company_name").eq("id", 1).single(),
  ]);
  const account = (accounts ?? []).find((a) => a.id === accountId);

  const { data: rows } = account
    ? await supabase.rpc("account_statement", {
        p_account_id: account.id,
        p_from: from ?? undefined,
        p_to: to ?? undefined,
      })
    : { data: null };

  const movements = (rows ?? []).filter((r) => r.entry_id !== null);
  const totalDebit = sumAmounts(movements.map((r) => r.debit));
  const totalCredit = sumAmounts(movements.map((r) => r.credit));
  const closing = rows?.length ? rows[rows.length - 1].balance : null;
  const period = `${from ? `من ${formatDate(from)}` : "من البداية"} ${to ? `إلى ${formatDate(to)}` : "حتى اليوم"}`;

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <h1 className="text-xl font-bold">كشف حساب</h1>
        {account && (
          <ReportTools
            filename={`كشف-حساب-${account.code}.csv`}
            headers={["التاريخ", "رقم القيد", "النوع", "البيان", "مدين", "دائن", "الرصيد"]}
            rows={(rows ?? []).map((r) => [
              formatDate(r.entry_date),
              r.entry_no ? String(r.entry_no) : "",
              r.source_type ? (SOURCE_TYPE_LABELS[r.source_type] ?? r.source_type) : "",
              r.description,
              r.debit ?? "",
              r.credit ?? "",
              r.balance,
            ])}
          />
        )}
      </div>

      <form className="flex flex-wrap items-end gap-3 print:hidden">
        <div className="grid gap-1">
          <Label htmlFor="account">الحساب</Label>
          <NativeSelect id="account" name="account" defaultValue={accountId ?? ""} className="w-72">
            <option value="">اختر الحساب</option>
            {(accounts ?? []).map((a) => (
              <option key={a.id} value={a.id}>
                {a.code} - {a.name}
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
      {!account && !invalidDate && (
        <p className="text-sm text-muted-foreground">اختر حسابًا لعرض كشفه.</p>
      )}

      {account && (
        <>
          <PrintHeader
            company={settings?.company_name ?? ""}
            title={`كشف حساب: ${account.code} - ${account.name}`}
            subtitle={period}
          />
          <div className="text-sm text-muted-foreground print:hidden">
            {account.code} - {account.name} · {period}
          </div>
          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>التاريخ</TableHead>
                  <TableHead>رقم القيد</TableHead>
                  <TableHead>النوع</TableHead>
                  <TableHead>البيان</TableHead>
                  <TableHead className="text-end">مدين</TableHead>
                  <TableHead className="text-end">دائن</TableHead>
                  <TableHead className="text-end">الرصيد</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(rows ?? []).map((r, i) => (
                  <TableRow key={r.entry_id ? `${r.entry_id}-${i}` : "opening"}>
                    <TableCell dir="ltr" className="text-end">
                      {formatDate(r.entry_date)}
                    </TableCell>
                    <TableCell>
                      {r.entry_id && (
                        <Link href={`/journal/${r.entry_id}`} className="font-semibold underline-offset-4 hover:underline">
                          {r.entry_no}
                        </Link>
                      )}
                    </TableCell>
                    <TableCell>
                      {r.source_type ? (SOURCE_TYPE_LABELS[r.source_type] ?? r.source_type) : ""}
                    </TableCell>
                    <TableCell className={r.entry_id ? "whitespace-normal" : "font-semibold"}>
                      {r.description}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {r.debit && r.debit !== "0.00" ? formatAmount(r.debit) : ""}
                    </TableCell>
                    <TableCell dir="ltr" className="text-start tabular-nums">
                      {r.credit && r.credit !== "0.00" ? formatAmount(r.credit) : ""}
                    </TableCell>
                    <TableCell className="text-end tabular-nums whitespace-nowrap">
                      {formatBalance(r.balance)}
                    </TableCell>
                  </TableRow>
                ))}
                <TableRow className="font-bold hover:bg-transparent">
                  <TableCell colSpan={4}>إجمالي الفترة والرصيد الختامي</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatCents(totalDebit)}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatCents(totalCredit)}
                  </TableCell>
                  <TableCell className="text-end tabular-nums whitespace-nowrap">
                    {formatBalance(closing)}
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
        </>
      )}
    </div>
  );
}
