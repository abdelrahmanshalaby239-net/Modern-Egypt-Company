import type { Metadata } from "next";
import Link from "next/link";

import { Alert } from "@/components/ui/alert";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireAdmin } from "@/lib/auth";
import { formatDate, todayIso } from "@/lib/format";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";
import { CloseYearButton, FiscalYearForm, LockPeriodForm } from "./closing-forms";

export const metadata: Metadata = { title: "إقفال السنة" };

// آخر يوم في الشهر الماضي (ISO)
function previousMonthEnd(todayIsoDate: string): string {
  const [y, m] = todayIsoDate.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, 0));
  return date.toISOString().slice(0, 10);
}

// السنة المالية والقفل الشهري وإقفال السنة (SPEC §6.8، المدير فقط)
export default async function ClosingPage() {
  const { supabase } = await requireAdmin();
  const [{ data: years }, { data: settings }, { data: preview }, { data: retained }] = await Promise.all([
    supabase
      .from("fiscal_years")
      .select("id, name, start_date, end_date, is_closed, closed_at, closing_entry_id")
      .order("start_date", { ascending: false }),
    supabase.from("settings").select("lock_date").eq("id", 1).single(),
    supabase.rpc("fiscal_year_closing_preview"),
    supabase.from("system_accounts").select("account_id").eq("key", "retained_earnings").maybeSingle(),
  ]);
  const openYear = (years ?? []).find((y) => !y.is_closed) ?? null;
  const closedYears = (years ?? []).filter((y) => y.is_closed);
  const today = todayIso();
  const lockDate = settings?.lock_date ?? null;

  // صافي الربح = مجموع (مدين − دائن) لسطور الإيرادات والمصروفات في قيد الإقفال
  const plLines = (preview ?? []).filter((l) => l.account_id !== retained?.account_id);
  const netProfit = sumAmounts(plLines.map((l) => l.debit)) - sumAmounts(plLines.map((l) => l.credit));
  const ended = openYear ? openYear.end_date <= today : false;

  const suggestedLock = previousMonthEnd(today);
  const canSuggest = openYear && (!lockDate || suggestedLock > lockDate) && suggestedLock < openYear.end_date;

  return (
    <div className="grid max-w-4xl gap-4">
      <h1 className="text-xl font-bold">إقفال السنة والقفل الشهري</h1>

      <Card>
        <CardHeader>
          <CardTitle>السنة المالية الحالية</CardTitle>
          <CardDescription>
            {openYear
              ? `${openYear.name}: من ${formatDate(openYear.start_date)} إلى ${formatDate(openYear.end_date)}.`
              : "لم تُعرَّف السنة المالية بعد. أول سنة لا تبدأ بعد أي قيد مسجّل، وتاريخ القفل يصبح اليوم السابق لبدايتها."}{" "}
            تبدأ السنة أول يوم في شهر وتنتهي آخر يوم في شهر. بعد إقفال سنة تُفتح التالية تلقائيًا (12 شهرًا) ويمكن تعديل
            نهايتها واسمها.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <FiscalYearForm
            key={openYear ? `${openYear.id}-${openYear.name}-${openYear.end_date}` : "new"}
            year={openYear}
            startLocked={closedYears.length > 0}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>القفل الشهري</CardTitle>
          <CardDescription>
            الفترة مقفولة حتى: <span dir="ltr">{lockDate ? formatDate(lockDate) : "لا يوجد قفل"}</span>. القفل يمنع أي
            تسجيل أو إلغاء بتاريخ حتى التاريخ المقفول، وهو للأمام فقط، ويكون قبل نهاية السنة المفتوحة (نهايتها تُقفل
            بإقفال السنة).
          </CardDescription>
        </CardHeader>
        <CardContent>
          {openYear ? (
            <LockPeriodForm suggested={canSuggest ? formatDate(suggestedLock) : ""} />
          ) : (
            <p className="text-sm text-muted-foreground">عرّف السنة المالية أولًا.</p>
          )}
        </CardContent>
      </Card>

      {openYear && (
        <Card>
          <CardHeader>
            <CardTitle>إقفال {openYear.name}</CardTitle>
            <CardDescription>
              معاينة قيد الإقفال بتاريخ {formatDate(openYear.end_date)}: يصفّر كل حساب إيرادات ومصروفات في الأرباح المرحّلة.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4">
            <div className="rounded-lg border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>الحساب</TableHead>
                    <TableHead className="text-end">مدين</TableHead>
                    <TableHead className="text-end">دائن</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {(preview ?? []).map((l) => (
                    <TableRow key={l.line_no}>
                      <TableCell>
                        {l.code} - {l.name}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {l.debit !== "0.00" ? formatAmount(l.debit) : ""}
                      </TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {l.credit !== "0.00" ? formatAmount(l.credit) : ""}
                      </TableCell>
                    </TableRow>
                  ))}
                  {(preview ?? []).length === 0 && (
                    <TableRow>
                      <TableCell colSpan={3} className="py-6 text-center text-muted-foreground">
                        لا توجد أرصدة إيرادات أو مصروفات. الإقفال يتم بلا قيد.
                      </TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>
            </div>
            <div className="font-semibold">
              {netProfit < 0n ? "صافي الخسارة" : "صافي الربح"} للسنة:{" "}
              <span dir="ltr">{formatCents(netProfit < 0n ? -netProfit : netProfit)}</span>
            </div>
            {!ended && (
              <Alert variant="warning">السنة تنتهي في {formatDate(openYear.end_date)}، ولا تُقفل قبل انتهائها.</Alert>
            )}
            <CloseYearButton
              yearName={openYear.name}
              endDate={openYear.end_date}
              netProfit={formatCents(netProfit)}
              disabled={!ended}
            />
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>السنوات المقفلة</CardTitle>
        </CardHeader>
        <CardContent>
          {closedYears.length === 0 ? (
            <p className="text-sm text-muted-foreground">لا توجد سنوات مقفلة بعد.</p>
          ) : (
            <div className="rounded-lg border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>السنة</TableHead>
                    <TableHead>الفترة</TableHead>
                    <TableHead>قيد الإقفال</TableHead>
                    <TableHead>ميزان المراجعة بعد الإقفال</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {closedYears.map((y) => (
                    <TableRow key={y.id}>
                      <TableCell className="font-semibold">{y.name}</TableCell>
                      <TableCell dir="ltr" className="text-end">
                        {formatDate(y.start_date)} – {formatDate(y.end_date)}
                      </TableCell>
                      <TableCell>
                        {y.closing_entry_id ? (
                          <Link href={`/journal/${y.closing_entry_id}`} className="underline-offset-4 hover:underline">
                            فتح القيد
                          </Link>
                        ) : (
                          <span className="text-muted-foreground">بلا قيد (لا أرصدة)</span>
                        )}
                      </TableCell>
                      <TableCell>
                        <Link
                          href={`/trial-balance?as_of=${encodeURIComponent(formatDate(y.end_date))}`}
                          className="underline-offset-4 hover:underline"
                        >
                          في {formatDate(y.end_date)}
                        </Link>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
