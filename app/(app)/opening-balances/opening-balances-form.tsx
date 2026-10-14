"use client";

import { startTransition, useActionState, useState } from "react";

import { Alert } from "@/components/ui/alert";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { PostingAccount } from "@/lib/accounts";
import type { FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";
import { ACCOUNT_TYPES, ACCOUNT_TYPE_LABELS } from "@/lib/labels";
import { formatCents, parseCents, plainCents } from "@/lib/money";
import { postOpeningBalances } from "./actions";

type Amounts = { debit: string; credit: string };

export function OpeningBalancesForm({
  accounts,
  defaultDate,
  capitalLabel,
}: {
  accounts: PostingAccount[];
  defaultDate: string;
  capitalLabel: string;
}) {
  const [state, action, pending] = useActionState<FormState, FormData>(postOpeningBalances, {});
  const [entryDate, setEntryDate] = useState(defaultDate);
  const [amounts, setAmounts] = useState<Record<number, Amounts>>({});
  const [clientError, setClientError] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false);

  const setAmount = (id: number, field: keyof Amounts, value: string) =>
    setAmounts((a) => ({ ...a, [id]: { ...(a[id] ?? { debit: "", credit: "" }), [field]: value } }));

  // الإجماليات بالقروش (BigInt) — لا float
  const rows = accounts.map((account) => {
    const a = amounts[account.id] ?? { debit: "", credit: "" };
    return { account, a, debit: parseCents(a.debit), credit: parseCents(a.credit) };
  });
  const filled = rows.filter((r) => r.a.debit.trim() || r.a.credit.trim());
  const totalDebit = filled.reduce((t, r) => t + (r.debit ?? 0n), 0n);
  const totalCredit = filled.reduce((t, r) => t + (r.credit ?? 0n), 0n);
  const difference = totalDebit - totalCredit;
  const absDifference = difference < 0n ? -difference : difference;

  const validate = (): string => {
    if (!parseDate(entryDate)) return "التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة.";
    if (filled.length === 0) return "أدخل رصيدًا واحدًا على الأقل.";
    for (const r of filled) {
      const name = `${r.account.code} - ${r.account.name}`;
      if (r.debit === null || r.credit === null)
        return `${name}: المبلغ غير صالح (رقم موجب بخانتين عشريتين كحد أقصى).`;
      if ((r.debit > 0n) === (r.credit > 0n))
        return `${name}: أدخل الرصيد في المدين أو في الدائن (واحدًا فقط).`;
    }
    return "";
  };

  const requestPost = () => {
    const error = validate();
    setClientError(error);
    if (!error) setConfirmOpen(true);
  };

  const post = () => {
    setConfirmOpen(false);
    const formData = new FormData();
    formData.set("entry_date", entryDate);
    formData.set("difference_to_capital", String(difference !== 0n));
    formData.set(
      "lines",
      JSON.stringify(
        filled.map((r) => ({
          account_id: String(r.account.id),
          debit: plainCents(r.debit ?? 0n),
          credit: plainCents(r.credit ?? 0n),
        })),
      ),
    );
    startTransition(() => action(formData));
  };

  const error = clientError || state.error;

  return (
    <Card>
      <CardContent className="grid gap-5">
        <div className="grid max-w-xs gap-2">
          <Label htmlFor="entry_date">تاريخ الأرصدة الافتتاحية</Label>
          <Input
            id="entry_date"
            dir="ltr"
            inputMode="numeric"
            placeholder="يوم/شهر/سنة"
            className="text-end"
            value={entryDate}
            onChange={(e) => setEntryDate(e.target.value)}
          />
        </div>

        <div className="overflow-x-auto">
          <table className="w-full min-w-[36rem] text-sm">
            <thead>
              <tr className="border-b text-muted-foreground">
                <th className="p-2 text-start font-semibold">الحساب</th>
                <th className="w-40 p-2 text-start font-semibold">مدين</th>
                <th className="w-40 p-2 text-start font-semibold">دائن</th>
              </tr>
            </thead>
            {ACCOUNT_TYPES.map((type) => {
              const typeRows = rows.filter((r) => r.account.type === type);
              if (typeRows.length === 0) return null;
              return (
                <tbody key={type}>
                  <tr>
                    <td colSpan={3} className="px-2 pt-4 pb-1 font-bold">
                      {ACCOUNT_TYPE_LABELS[type]}
                    </td>
                  </tr>
                  {typeRows.map(({ account, a, debit, credit }) => (
                    <tr key={account.id} className="border-b">
                      <td className="p-2">
                        {account.code} - {account.name}
                      </td>
                      <td className="p-2">
                        <Input
                          aria-label={`مدين ${account.name}`}
                          dir="ltr"
                          inputMode="decimal"
                          value={a.debit}
                          aria-invalid={debit === null}
                          onChange={(e) => setAmount(account.id, "debit", e.target.value)}
                        />
                      </td>
                      <td className="p-2">
                        <Input
                          aria-label={`دائن ${account.name}`}
                          dir="ltr"
                          inputMode="decimal"
                          value={a.credit}
                          aria-invalid={credit === null}
                          onChange={(e) => setAmount(account.id, "credit", e.target.value)}
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              );
            })}
            <tfoot>
              <tr className="font-bold">
                <td className="p-2">الإجمالي</td>
                <td dir="ltr" className="p-2 text-start tabular-nums">
                  {formatCents(totalDebit)}
                </td>
                <td dir="ltr" className="p-2 text-start tabular-nums">
                  {formatCents(totalCredit)}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>

        {difference !== 0n && (
          <Alert variant="warning">
            الأرصدة غير متوازنة بفرق {formatCents(absDifference)}. عند الاعتماد يُسجَّل الفرق{" "}
            {difference > 0n ? "دائنًا" : "مدينًا"} على حساب {capitalLabel} بعد تأكيدك.
          </Alert>
        )}

        {error && <Alert>{error}</Alert>}

        <div>
          <Button type="button" onClick={requestPost} disabled={pending}>
            {pending ? "جارٍ الاعتماد..." : "اعتماد الأرصدة الافتتاحية"}
          </Button>
        </div>
      </CardContent>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد اعتماد الأرصدة الافتتاحية</AlertDialogTitle>
            <AlertDialogDescription>
              {difference !== 0n
                ? `سيُسجَّل فرق ${formatCents(absDifference)} ${difference > 0n ? "دائنًا" : "مدينًا"} على حساب ${capitalLabel}. `
                : ""}
              لا يمكن تعديل القيد الافتتاحي بعد الاعتماد، والتصحيح يكون بإلغائه ثم التسجيل من جديد.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <Button type="button" onClick={post}>
              اعتماد
            </Button>
            <AlertDialogCancel>رجوع</AlertDialogCancel>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}
