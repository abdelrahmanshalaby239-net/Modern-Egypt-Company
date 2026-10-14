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
import { NativeSelect } from "@/components/ui/native-select";
import type { PostingAccount } from "@/lib/accounts";
import type { FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";
import { formatCents, parseCents, plainCents } from "@/lib/money";
import { postJournalEntry } from "../actions";

type Line = { key: number; account_id: string; debit: string; credit: string; description: string };

const emptyLine = (key: number): Line => ({ key, account_id: "", debit: "", credit: "", description: "" });

export function JournalEntryForm({
  accounts,
  defaultDate,
}: {
  accounts: PostingAccount[];
  defaultDate: string;
}) {
  const [state, action, pending] = useActionState<FormState, FormData>(postJournalEntry, {});
  const [entryDate, setEntryDate] = useState(defaultDate);
  const [sourceType, setSourceType] = useState("manual");
  const [description, setDescription] = useState("");
  const [lines, setLines] = useState<Line[]>([emptyLine(1), emptyLine(2)]);
  const [clientError, setClientError] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false);

  const updateLine = (key: number, field: keyof Omit<Line, "key">, value: string) =>
    setLines((ls) => ls.map((l) => (l.key === key ? { ...l, [field]: value } : l)));

  // الإجماليات بالقروش (BigInt) — لا float
  const parsed = lines.map((l) => ({
    line: l,
    debit: parseCents(l.debit),
    credit: parseCents(l.credit),
  }));
  const totalDebit = parsed.reduce((t, p) => t + (p.debit ?? 0n), 0n);
  const totalCredit = parsed.reduce((t, p) => t + (p.credit ?? 0n), 0n);
  const difference = totalDebit - totalCredit;

  const validate = (): string => {
    if (!parseDate(entryDate)) return "تاريخ القيد غير صحيح. اكتبه بصيغة يوم/شهر/سنة.";
    if (!description.trim()) return "بيان القيد مطلوب.";
    const used = parsed.filter((p) => p.line.account_id || p.line.debit || p.line.credit);
    if (used.length < 2) return "القيد يحتاج سطرين على الأقل.";
    for (const [i, p] of used.entries()) {
      if (!p.line.account_id) return `السطر ${i + 1}: اختر الحساب.`;
      if (p.debit === null || p.credit === null)
        return `السطر ${i + 1}: المبلغ غير صالح (رقم موجب بخانتين عشريتين كحد أقصى).`;
      if ((p.debit > 0n) === (p.credit > 0n))
        return `السطر ${i + 1}: أدخل مبلغًا في المدين أو في الدائن (واحدًا فقط).`;
    }
    if (difference !== 0n) return `القيد غير متوازن: الفرق ${formatCents(difference < 0n ? -difference : difference)}.`;
    return "";
  };

  const requestPost = () => {
    const error = validate();
    setClientError(error);
    if (!error) setConfirmOpen(true);
  };

  const post = () => {
    setConfirmOpen(false);
    const used = parsed.filter((p) => p.line.account_id || p.line.debit || p.line.credit);
    const formData = new FormData();
    formData.set("entry_date", entryDate);
    formData.set("source_type", sourceType);
    formData.set("description", description);
    formData.set(
      "lines",
      JSON.stringify(
        used.map((p) => ({
          account_id: p.line.account_id,
          debit: plainCents(p.debit ?? 0n),
          credit: plainCents(p.credit ?? 0n),
          description: p.line.description,
        })),
      ),
    );
    startTransition(() => action(formData));
  };

  const error = clientError || state.error;

  return (
    <Card>
      <CardContent className="grid gap-5">
        <div className="grid gap-3 sm:grid-cols-[10rem_12rem_1fr]">
          <div className="grid gap-2">
            <Label htmlFor="entry_date">التاريخ</Label>
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
          <div className="grid gap-2">
            <Label htmlFor="source_type">نوع القيد</Label>
            <NativeSelect
              id="source_type"
              value={sourceType}
              onChange={(e) => setSourceType(e.target.value)}
            >
              <option value="manual">قيد يومية</option>
              <option value="adjustment">قيد تسوية (إهلاك، مستحقات...)</option>
            </NativeSelect>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="description">البيان</Label>
            <Input
              id="description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full min-w-[44rem] text-sm">
            <thead>
              <tr className="border-b text-muted-foreground">
                <th className="p-2 text-start font-semibold">الحساب</th>
                <th className="w-36 p-2 text-start font-semibold">مدين</th>
                <th className="w-36 p-2 text-start font-semibold">دائن</th>
                <th className="p-2 text-start font-semibold">ملاحظة السطر</th>
                <th className="w-16 p-2" />
              </tr>
            </thead>
            <tbody>
              {lines.map((l) => (
                <tr key={l.key} className="border-b">
                  <td className="p-2">
                    <NativeSelect
                      aria-label="الحساب"
                      value={l.account_id}
                      onChange={(e) => updateLine(l.key, "account_id", e.target.value)}
                    >
                      <option value="">اختر الحساب</option>
                      {accounts.map((a) => (
                        <option key={a.id} value={a.id}>
                          {a.code} - {a.name}
                        </option>
                      ))}
                    </NativeSelect>
                  </td>
                  <td className="p-2">
                    <Input
                      aria-label="مدين"
                      dir="ltr"
                      inputMode="decimal"
                      value={l.debit}
                      aria-invalid={parseCents(l.debit) === null}
                      onChange={(e) => updateLine(l.key, "debit", e.target.value)}
                    />
                  </td>
                  <td className="p-2">
                    <Input
                      aria-label="دائن"
                      dir="ltr"
                      inputMode="decimal"
                      value={l.credit}
                      aria-invalid={parseCents(l.credit) === null}
                      onChange={(e) => updateLine(l.key, "credit", e.target.value)}
                    />
                  </td>
                  <td className="p-2">
                    <Input
                      aria-label="ملاحظة السطر"
                      value={l.description}
                      onChange={(e) => updateLine(l.key, "description", e.target.value)}
                    />
                  </td>
                  <td className="p-2">
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      disabled={lines.length <= 2}
                      onClick={() => setLines((ls) => ls.filter((x) => x.key !== l.key))}
                    >
                      حذف
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="font-bold">
                <td className="p-2">الإجمالي</td>
                <td dir="ltr" className="p-2 text-start tabular-nums">
                  {formatCents(totalDebit)}
                </td>
                <td dir="ltr" className="p-2 text-start tabular-nums">
                  {formatCents(totalCredit)}
                </td>
                <td className={`p-2 ${difference === 0n ? "text-success" : "text-warning"}`} colSpan={2}>
                  {difference === 0n
                    ? "متوازن"
                    : `الفرق: ${formatCents(difference < 0n ? -difference : difference)}`}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>

        <div>
          <Button
            type="button"
            variant="outline"
            onClick={() => setLines((ls) => [...ls, emptyLine(Math.max(...ls.map((x) => x.key)) + 1)])}
          >
            إضافة سطر
          </Button>
        </div>

        {error && <Alert>{error}</Alert>}

        <div>
          <Button type="button" onClick={requestPost} disabled={pending}>
            {pending ? "جارٍ الاعتماد..." : "اعتماد القيد"}
          </Button>
        </div>
      </CardContent>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد اعتماد القيد</AlertDialogTitle>
            <AlertDialogDescription>
              سيُعتمد القيد بإجمالي {formatCents(totalDebit)}. لا يمكن تعديل القيد أو حذفه بعد
              الاعتماد، والتصحيح يكون بإلغائه بقيد عكسي.
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
