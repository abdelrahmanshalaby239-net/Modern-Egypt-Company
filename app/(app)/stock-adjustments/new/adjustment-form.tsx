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
import type { FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";
import { formatAmount, formatCents, parseCents } from "@/lib/money";
import { formatQty, formatUnitCost, lineTotalCents, parseQty, parseUnitPrice, plainQty } from "@/lib/quantity";
import { postStockAdjustment } from "../actions";

export type AdjustmentItem = {
  id: number;
  code: string;
  name: string;
  unit: string;
  typeLabel: string;
  qty: string;
  value: string;
  avg_cost: string;
};

// معاينة قيمة الفرق بنفس قاعدة قاعدة البيانات (BigInt): العجز = الكمية × القيمة ÷ الرصيد مقربًا للقرش
// (وصرف كل الرصيد = القيمة كلها)، والزيادة = الكمية × آخر متوسط. القيمة المعتمدة تُحسب عند الاعتماد.
function previewCents(item: AdjustmentItem, diff: bigint): bigint {
  const system = parseQty(item.qty) ?? 0n;
  const value = parseCents(item.value) ?? 0n;
  if (diff < 0n) {
    const q = -diff;
    if (q >= system) return value;
    return (2n * q * value + system) / (2n * system);
  }
  return lineTotalCents(diff, parseUnitPrice(item.avg_cost) ?? 0n);
}

export function AdjustmentForm({ defaultDate, items }: { defaultDate: string; items: AdjustmentItem[] }) {
  const [state, action, pending] = useActionState<FormState, FormData>(postStockAdjustment, {});
  const [docDate, setDocDate] = useState(defaultDate);
  const [itemId, setItemId] = useState("");
  const [counted, setCounted] = useState("");
  const [notes, setNotes] = useState("");
  const [clientError, setClientError] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false);

  const item = items.find((i) => String(i.id) === itemId);
  const countedUnits = counted.trim() ? parseQty(counted) : null;
  const diff = item && countedUnits !== null ? countedUnits - (parseQty(item.qty) ?? 0n) : null;
  const value = item && diff !== null && diff !== 0n ? previewCents(item, diff) : null;
  const absDiff = diff !== null && diff < 0n ? -diff : (diff ?? 0n);

  const validate = (): string => {
    if (!parseDate(docDate)) return "تاريخ التسوية غير صحيح. اكتبه بصيغة يوم/شهر/سنة.";
    if (!item) return "اختر الصنف.";
    if (!counted.trim()) return "أدخل الكمية الفعلية من الجرد.";
    if (countedUnits === null) return "الكمية الفعلية غير صالحة (صفر أو رقم موجب بثلاث خانات عشرية كحد أقصى).";
    if (diff === 0n) return `لا فرق بين الكمية الفعلية ورصيد النظام (${formatQty(item.qty)}).`;
    if (diff !== null && diff > 0n && item.avg_cost === "0.0000")
      return `لا توجد تكلفة حالية للصنف ${item.code} - ${item.name}. سجّل مخزون أول المدة أو فاتورة مشتريات أولًا.`;
    if (value === 0n) return "قيمة الفرق أقل من قرش، ولا يُسجَّل قيد بلا قيمة.";
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
    formData.set("doc_date", docDate);
    formData.set("item_id", itemId);
    formData.set("counted_qty", plainQty(countedUnits ?? 0n));
    formData.set("notes", notes);
    startTransition(() => action(formData));
  };

  const error = clientError || state.error;

  return (
    <Card>
      <CardContent className="grid gap-5">
        <div className="grid gap-3 sm:grid-cols-[10rem_1fr]">
          <div className="grid gap-2">
            <Label htmlFor="doc_date">التاريخ</Label>
            <Input
              id="doc_date"
              dir="ltr"
              inputMode="numeric"
              placeholder="يوم/شهر/سنة"
              className="text-end"
              value={docDate}
              onChange={(e) => setDocDate(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="item">الصنف</Label>
            <NativeSelect id="item" value={itemId} onChange={(e) => setItemId(e.target.value)}>
              <option value="">اختر الصنف</option>
              {items.map((i) => (
                <option key={i.id} value={i.id}>
                  {i.code} - {i.name} ({i.typeLabel})
                </option>
              ))}
            </NativeSelect>
          </div>
        </div>

        {item && (
          <dl className="grid gap-2 rounded-md border p-3 text-sm sm:grid-cols-3">
            <div>
              <dt className="text-muted-foreground">رصيد النظام</dt>
              <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                {formatQty(item.qty)} <span dir="rtl">{item.unit}</span>
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">متوسط التكلفة</dt>
              <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                {formatUnitCost(item.avg_cost)}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">القيمة</dt>
              <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                {formatAmount(item.value)}
              </dd>
            </div>
          </dl>
        )}

        <div className="grid gap-3 sm:grid-cols-[12rem_1fr]">
          <div className="grid gap-2">
            <Label htmlFor="counted">الكمية الفعلية (من الجرد)</Label>
            <Input
              id="counted"
              dir="ltr"
              inputMode="decimal"
              value={counted}
              aria-invalid={counted.trim() !== "" && countedUnits === null}
              onChange={(e) => setCounted(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="notes">البيان (اختياري)</Label>
            <Input id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
        </div>

        {item && diff !== null && diff !== 0n && value !== null && (
          <Alert variant="warning">
            {diff < 0n ? "عجز" : "زيادة"} {formatQty(plainQty(absDiff))} {item.unit} بقيمة تقريبية{" "}
            {formatCents(value)}:{" "}
            {diff < 0n
              ? "م فروقات جرد المخزون / د حساب المخزون بمتوسط التكلفة الحالي."
              : "م حساب المخزون / د فروقات جرد المخزون بآخر متوسط تكلفة."}
          </Alert>
        )}

        {error && <Alert>{error}</Alert>}

        <div>
          <Button type="button" onClick={requestPost} disabled={pending}>
            {pending ? "جارٍ الاعتماد..." : "اعتماد التسوية"}
          </Button>
        </div>
      </CardContent>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد اعتماد تسوية الجرد</AlertDialogTitle>
            <AlertDialogDescription>
              {item ? `${item.code} - ${item.name}: ` : ""}
              {diff !== null && diff < 0n ? "عجز" : "زيادة"} {formatQty(plainQty(absDiff))} بقيمة تقريبية{" "}
              {formatCents(value ?? 0n)}. الفرق يُحسب من الرصيد لحظة الاعتماد. لا يمكن تعديل التسوية أو حذفها
              بعد الاعتماد، والتصحيح يكون بإلغائها ثم إدخالها من جديد.
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
