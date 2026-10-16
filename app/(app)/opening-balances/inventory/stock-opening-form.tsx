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
import type { FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";
import { formatCents } from "@/lib/money";
import { lineTotalCents, parseQty, parseUnitPrice, plainQty, plainUnitPrice } from "@/lib/quantity";
import { postStockOpening } from "./actions";

export type OpeningItem = { id: number; code: string; name: string; unit: string; suggested_cost: string };
export type OpeningItemGroup = { title: string; items: OpeningItem[] };

type Inputs = { qty: string; unit_cost: string };

export function StockOpeningForm({
  groups,
  defaultDate,
  capitalLabel,
}: {
  groups: OpeningItemGroup[];
  defaultDate: string;
  capitalLabel: string;
}) {
  const [state, action, pending] = useActionState<FormState, FormData>(postStockOpening, {});
  const [entryDate, setEntryDate] = useState(defaultDate);
  // تكلفة الوحدة تبدأ بالتكلفة الافتراضية من بطاقة الصنف (اقتراح قابل للتعديل)
  const [inputs, setInputs] = useState<Record<number, Inputs>>(() =>
    Object.fromEntries(groups.flatMap((g) => g.items.map((i) => [i.id, { qty: "", unit_cost: i.suggested_cost }]))),
  );
  const [clientError, setClientError] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false);

  const setInput = (id: number, field: keyof Inputs, value: string) =>
    setInputs((s) => ({ ...s, [id]: { ...(s[id] ?? { qty: "", unit_cost: "" }), [field]: value } }));

  // قيمة كل صنف والإجماليات بالقروش (BigInt) — معاينة، وقاعدة البيانات تحسب القيمة المعتمدة.
  // الصنف يُحتسب فقط لو أُدخلت له كمية (التكلفة المقترحة وحدها لا تجعله سطرًا).
  const rows = groups.flatMap((g) =>
    g.items.map((item) => {
      const input = inputs[item.id] ?? { qty: "", unit_cost: "" };
      const qty = parseQty(input.qty);
      const cost = parseUnitPrice(input.unit_cost);
      return { item, input, qty, cost, value: qty !== null && cost !== null ? lineTotalCents(qty, cost) : null };
    }),
  );
  const filled = rows.filter((r) => r.input.qty.trim());
  const groupTotal = (g: OpeningItemGroup) =>
    filled.filter((r) => g.items.includes(r.item)).reduce((t, r) => t + (r.value ?? 0n), 0n);
  const total = filled.reduce((t, r) => t + (r.value ?? 0n), 0n);

  const validate = (): string => {
    if (!parseDate(entryDate)) return "التاريخ غير صحيح. اكتبه بصيغة يوم/شهر/سنة.";
    if (filled.length === 0) return "أدخل صنفًا واحدًا على الأقل.";
    for (const r of filled) {
      const label = `${r.item.code} - ${r.item.name}`;
      if (r.qty === null) return `${label}: الكمية غير صالحة (رقم موجب بثلاث خانات عشرية كحد أقصى).`;
      if (r.qty <= 0n) return `${label}: الكمية يجب أن تكون أكبر من صفر.`;
      if (r.cost === null) return `${label}: تكلفة الوحدة غير صالحة (رقم موجب بأربع خانات عشرية كحد أقصى).`;
      if ((r.value ?? 0n) <= 0n) return `${label}: قيمة الصنف يجب أن تكون أكبر من صفر.`;
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
    // جزء المخزون في جانب واحد، فقيمته كلها فرق على رأس المال بعد التأكيد
    formData.set("difference_to_capital", "true");
    formData.set(
      "lines",
      JSON.stringify(
        filled.map((r) => ({
          item_id: String(r.item.id),
          qty: plainQty(r.qty ?? 0n),
          unit_cost: plainUnitPrice(r.cost ?? 0n),
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
          <Label htmlFor="entry_date">تاريخ مخزون أول المدة</Label>
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
          <table className="line-table w-full text-sm sm:min-w-[40rem]">
            <thead>
              <tr className="border-b text-muted-foreground">
                <th className="p-2 text-start font-semibold">الصنف</th>
                <th className="w-36 p-2 text-start font-semibold">الكمية</th>
                <th className="w-36 p-2 text-start font-semibold">تكلفة الوحدة</th>
                <th className="w-36 p-2 text-start font-semibold">القيمة</th>
              </tr>
            </thead>
            {groups.map((group) =>
              group.items.length === 0 ? null : (
                <tbody key={group.title}>
                  <tr>
                    <td colSpan={4} className="px-2 pt-4 pb-1 font-bold">
                      {group.title}
                    </td>
                  </tr>
                  {group.items.map((item) => {
                    const row = rows.find((r) => r.item === item);
                    return (
                      <tr key={item.id} className="border-b">
                        <td className="p-2">
                          {item.code} - {item.name} <span className="text-muted-foreground">({item.unit})</span>
                        </td>
                        <td data-label="الكمية" className="p-2">
                          <Input
                            aria-label={`كمية ${item.name}`}
                            dir="ltr"
                            inputMode="decimal"
                            value={row?.input.qty ?? ""}
                            aria-invalid={row?.qty === null}
                            onChange={(e) => setInput(item.id, "qty", e.target.value)}
                          />
                        </td>
                        <td data-label="تكلفة الوحدة" className="p-2">
                          <Input
                            aria-label={`تكلفة وحدة ${item.name}`}
                            dir="ltr"
                            inputMode="decimal"
                            value={row?.input.unit_cost ?? ""}
                            aria-invalid={row?.cost === null}
                            onChange={(e) => setInput(item.id, "unit_cost", e.target.value)}
                          />
                          {item.suggested_cost && row?.input.unit_cost.trim() === item.suggested_cost && (
                            <div className="mt-1 text-xs text-muted-foreground">مقترح من بطاقة الصنف</div>
                          )}
                        </td>
                        <td data-label="القيمة" dir="ltr" className="p-2 text-start tabular-nums">
                          {row?.value ? formatCents(row.value) : ""}
                        </td>
                      </tr>
                    );
                  })}
                  <tr className="font-semibold">
                    <td className="p-2" colSpan={3}>
                      إجمالي {group.title}
                    </td>
                    <td dir="ltr" className="p-2 text-start tabular-nums">
                      {formatCents(groupTotal(group))}
                    </td>
                  </tr>
                </tbody>
              ),
            )}
            <tfoot>
              <tr className="font-bold">
                <td className="p-2" colSpan={3}>
                  إجمالي مخزون أول المدة
                </td>
                <td dir="ltr" className="p-2 text-start tabular-nums">
                  {formatCents(total)}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>

        {total > 0n && (
          <Alert variant="warning">
            قيمة المخزون كلها ({formatCents(total)}) تُسجَّل دائنة على حساب {capitalLabel} بعد تأكيدك، لأن هذا
            الجزء فيه حسابات المخزون فقط.
          </Alert>
        )}

        {error && <Alert>{error}</Alert>}

        <div>
          <Button type="button" onClick={requestPost} disabled={pending}>
            {pending ? "جارٍ الاعتماد..." : "اعتماد مخزون أول المدة"}
          </Button>
        </div>
      </CardContent>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد اعتماد مخزون أول المدة</AlertDialogTitle>
            <AlertDialogDescription>
              {filled.length} صنف بقيمة {formatCents(total)} تُسجَّل مدينة على حسابات المخزون ودائنة على
              حساب {capitalLabel}. لا يمكن تعديل القيد بعد الاعتماد، والتصحيح يكون بإلغائه ثم التسجيل من جديد.
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
