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
import { PAYMENT_STATUS_LABELS, paymentStatus } from "@/lib/labels";
import { formatBalance, formatCents, parseCents, plainCents } from "@/lib/money";
import {
  formatFactor,
  formatQty,
  formatQtyUnits,
  lineTotalCents,
  parseFactor,
  parseQty,
  parseUnitPrice,
  plainQty,
  plainUnitPrice,
  toBaseUnits,
} from "@/lib/quantity";
import { postPurchaseInvoice } from "../actions";

// units = الوحدات البديلة النشطة للصنف (الوحدة الأساسية دائمًا متاحة بمعامل 1)
export type PurchaseItem = {
  id: number;
  code: string;
  name: string;
  unit: string;
  typeLabel: string;
  qty: string;
  units: { id: number; name: string; factor: string }[];
};
// balance = رصيد المورد الحالي من القيود (مدين موجب = دفعة مقدمة، دائن سالب = مستحق له)
type Supplier = { id: number; name: string; balance: string };
// unit_id فارغ = الوحدة الأساسية
type Line = { key: number; item_id: string; unit_id: string; qty: string; unit_price: string };

const emptyLine = (key: number): Line => ({ key, item_id: "", unit_id: "", qty: "", unit_price: "" });

export function PurchaseForm({
  defaultDate,
  suppliers,
  items,
  treasuries,
}: {
  defaultDate: string;
  suppliers: Supplier[];
  items: PurchaseItem[];
  treasuries: PostingAccount[];
}) {
  const [state, action, pending] = useActionState<FormState, FormData>(postPurchaseInvoice, {});
  const [docDate, setDocDate] = useState(defaultDate);
  const [supplierId, setSupplierId] = useState("");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<Line[]>([emptyLine(1)]);
  const [paid, setPaid] = useState("0");
  const [treasuryId, setTreasuryId] = useState(String(treasuries[0]?.id ?? ""));
  const [clientError, setClientError] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false);

  // تغيير الصنف يعيد الوحدة للأساسية
  const updateLine = (key: number, field: keyof Omit<Line, "key">, value: string) =>
    setLines((ls) =>
      ls.map((l) => (l.key === key ? { ...l, [field]: value, ...(field === "item_id" ? { unit_id: "" } : {}) } : l)),
    );

  // إجمالي كل سطر وإجمالي الفاتورة بالقروش (BigInt) — معاينة، وقاعدة البيانات تحسب القيمة المعتمدة
  const parsed = lines.map((l) => {
    const item = items.find((i) => String(i.id) === l.item_id);
    const unit = item?.units.find((u) => String(u.id) === l.unit_id);
    const qty = parseQty(l.qty);
    const price = parseUnitPrice(l.unit_price);
    // الكمية بالوحدة الأساسية (null لو التحويل غير دقيق بثلاث خانات)
    const base = qty === null ? null : unit ? toBaseUnits(qty, parseFactor(unit.factor) ?? 0n) : qty;
    return {
      line: l,
      item,
      unit,
      qty,
      base,
      price,
      total: qty !== null && price !== null ? lineTotalCents(qty, price) : null,
    };
  });
  const used = parsed.filter((p) => p.line.item_id || p.line.qty || p.line.unit_price);
  const total = used.reduce((t, p) => t + (p.total ?? 0n), 0n);
  const supplier = suppliers.find((s) => String(s.id) === supplierId);
  const treasury = treasuries.find((t) => String(t.id) === treasuryId);

  // المدفوع الآن: من صفر (آجل بالكامل) حتى إجمالي الفاتورة، والباقي على حساب المورد
  const paidCents = parseCents(paid);
  const paidValue = paidCents ?? 0n;
  const remaining = total - paidValue;
  const status = paymentStatus(total, paidValue);
  // رصيد مدين للمورد = سداد سابق لم تقابله فاتورة (مثل سداد فاتورة أُلغيت)
  const advance = supplier ? (parseCents(supplier.balance, { signed: true }) ?? 0n) : 0n;

  const validate = (): string => {
    if (!parseDate(docDate)) return "تاريخ الفاتورة غير صحيح. اكتبه بصيغة يوم/شهر/سنة.";
    if (!supplier) return "اختر المورد.";
    if (used.length === 0) return "أضف صنفًا واحدًا على الأقل.";
    const seen = new Set<string>();
    for (const [i, p] of used.entries()) {
      const n = i + 1;
      if (!p.item) return `السطر ${n}: اختر الصنف.`;
      if (seen.has(p.line.item_id)) return `السطر ${n}: الصنف ${p.item.code} - ${p.item.name} مكرر في الفاتورة.`;
      seen.add(p.line.item_id);
      if (p.qty === null) return `السطر ${n}: الكمية غير صالحة (رقم موجب بثلاث خانات عشرية كحد أقصى).`;
      if (p.qty <= 0n) return `السطر ${n}: الكمية يجب أن تكون أكبر من صفر.`;
      if (p.base === null)
        return `السطر ${n}: الكمية بالوحدة الأساسية لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة.`;
      if (p.price === null) return `السطر ${n}: سعر الوحدة غير صالح (رقم موجب بأربع خانات عشرية كحد أقصى).`;
      if ((p.total ?? 0n) <= 0n) return `السطر ${n}: إجمالي السطر يجب أن يكون أكبر من صفر.`;
    }
    if (paidCents === null) return "المدفوع الآن غير صالح (صفر أو رقم موجب بخانتين عشريتين كحد أقصى).";
    if (paidCents > total)
      return `المدفوع الآن ${formatCents(paidCents)} أكبر من إجمالي الفاتورة ${formatCents(total)}.`;
    if (paidCents > 0n && !treasury) return "اختر الخزينة أو البنك المدفوع منه.";
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
    formData.set("supplier_id", supplierId);
    formData.set("notes", notes);
    formData.set("paid_amount", plainCents(paidValue));
    formData.set("paid_treasury_account_id", paidValue > 0n ? treasuryId : "");
    formData.set(
      "lines",
      JSON.stringify(
        used.map((p) => ({
          item_id: p.line.item_id,
          unit_id: p.unit ? p.unit.id : null,
          qty: plainQty(p.qty ?? 0n),
          unit_price: plainUnitPrice(p.price ?? 0n),
        })),
      ),
    );
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
            <Label htmlFor="supplier">المورد</Label>
            <NativeSelect id="supplier" value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
              <option value="">اختر المورد</option>
              {suppliers.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </NativeSelect>
            {supplier && (
              <div className="text-xs text-muted-foreground">
                رصيد المورد الحالي: <span dir="ltr">{formatBalance(supplier.balance)}</span>
              </div>
            )}
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full min-w-[56rem] text-sm">
            <thead>
              <tr className="border-b text-muted-foreground">
                <th className="p-2 text-start font-semibold">الصنف</th>
                <th className="w-36 p-2 text-start font-semibold">الوحدة</th>
                <th className="w-32 p-2 text-start font-semibold">الكمية</th>
                <th className="w-32 p-2 text-start font-semibold">سعر الوحدة</th>
                <th className="w-32 p-2 text-start font-semibold">الإجمالي</th>
                <th className="w-16 p-2" />
              </tr>
            </thead>
            <tbody>
              {parsed.map(({ line: l, item, unit, qty, base, price, total: lineTotal }) => (
                <tr key={l.key} className="border-b align-top">
                  <td className="p-2">
                    <NativeSelect
                      aria-label="الصنف"
                      value={l.item_id}
                      onChange={(e) => updateLine(l.key, "item_id", e.target.value)}
                    >
                      <option value="">اختر الصنف</option>
                      {items.map((i) => (
                        <option key={i.id} value={i.id}>
                          {i.code} - {i.name} ({i.typeLabel})
                        </option>
                      ))}
                    </NativeSelect>
                    {item && (
                      <div className="pt-1 text-xs text-muted-foreground">
                        الرصيد الحالي: <span dir="ltr">{formatQty(item.qty)}</span> {item.unit}
                      </div>
                    )}
                  </td>
                  <td className="p-2">
                    <NativeSelect
                      aria-label="الوحدة"
                      value={l.unit_id}
                      disabled={!item}
                      onChange={(e) => updateLine(l.key, "unit_id", e.target.value)}
                    >
                      <option value="">{item?.unit ?? "—"}</option>
                      {(item?.units ?? []).map((u) => (
                        <option key={u.id} value={u.id}>
                          {u.name} ({formatFactor(u.factor)} {item?.unit})
                        </option>
                      ))}
                    </NativeSelect>
                  </td>
                  <td className="p-2">
                    <Input
                      aria-label="الكمية"
                      dir="ltr"
                      inputMode="decimal"
                      value={l.qty}
                      aria-invalid={qty === null}
                      onChange={(e) => updateLine(l.key, "qty", e.target.value)}
                    />
                    {unit && qty !== null && qty > 0n && (
                      <div className={`pt-1 text-xs ${base === null ? "text-destructive" : "text-muted-foreground"}`}>
                        {base === null ? "تحويل غير دقيق" : `= ${formatQtyUnits(base)} ${item?.unit}`}
                      </div>
                    )}
                  </td>
                  <td className="p-2">
                    <Input
                      aria-label="سعر الوحدة"
                      dir="ltr"
                      inputMode="decimal"
                      value={l.unit_price}
                      aria-invalid={price === null}
                      onChange={(e) => updateLine(l.key, "unit_price", e.target.value)}
                    />
                  </td>
                  <td dir="ltr" className="p-2 pt-4 text-start tabular-nums">
                    {lineTotal === null ? "" : formatCents(lineTotal)}
                  </td>
                  <td className="p-2">
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      disabled={lines.length <= 1}
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
                <td className="p-2" colSpan={4}>
                  إجمالي الفاتورة
                </td>
                <td dir="ltr" className="p-2 text-start tabular-nums">
                  {formatCents(total)}
                </td>
                <td />
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
            إضافة صنف
          </Button>
        </div>

        <div className="grid gap-2">
          <Label htmlFor="notes">البيان (اختياري)</Label>
          <Input id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </div>

        <div className="grid gap-3 rounded-md border p-3">
          <div className="font-semibold">السداد</div>
          <div className="grid gap-3 sm:grid-cols-[12rem_1fr] sm:items-end">
            <div className="grid gap-2">
              <Label htmlFor="paid">المدفوع الآن</Label>
              <Input
                id="paid"
                dir="ltr"
                inputMode="decimal"
                value={paid}
                aria-invalid={paidCents === null || paidValue > total}
                onChange={(e) => setPaid(e.target.value)}
              />
            </div>
            <div className="flex flex-wrap gap-2">
              <Button type="button" variant="outline" size="sm" onClick={() => setPaid("0")}>
                آجل بالكامل
              </Button>
              <Button type="button" variant="outline" size="sm" onClick={() => setPaid(plainCents(total))}>
                سداد كامل الإجمالي
              </Button>
            </div>
          </div>
          {paidValue > 0n && (
            <div className="grid max-w-md gap-2">
              <Label htmlFor="treasury">من الخزينة/البنك</Label>
              <NativeSelect id="treasury" value={treasuryId} onChange={(e) => setTreasuryId(e.target.value)}>
                {treasuries.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.code} - {t.name}
                  </option>
                ))}
              </NativeSelect>
            </div>
          )}
          {paidValue > 0n && treasuries.length === 0 && (
            <Alert variant="warning">لا توجد خزينة أو بنك نشط. حدّد حساب الخزينة من دليل الحسابات أولًا.</Alert>
          )}
          <dl className="grid gap-2 text-sm sm:grid-cols-4">
            <div>
              <dt className="text-muted-foreground">إجمالي الفاتورة</dt>
              <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                {formatCents(total)}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">المدفوع الآن</dt>
              <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                {formatCents(paidValue)}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">المتبقي (آجل على المورد)</dt>
              <dd
                dir="ltr"
                className={`text-end font-semibold tabular-nums sm:text-start ${remaining < 0n ? "text-destructive" : ""}`}
              >
                {formatCents(remaining)}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">حالة السداد</dt>
              <dd className="font-semibold">{PAYMENT_STATUS_LABELS[status]}</dd>
            </div>
          </dl>
          {advance > 0n && (
            <Alert variant="warning">
              للمورد رصيد مدين {formatCents(advance)} (سداد سابق لم تقابله فاتورة، مثل سداد فاتورة ملغاة). لو هذه
              الفاتورة تصحيح لفاتورة ملغاة سُددت من قبل، اترك المدفوع الآن صفرًا: السداد السابق يُخصم من رصيد المورد
              تلقائيًا، والدفع مرة أخرى يكرر السداد.
            </Alert>
          )}
        </div>

        {error && <Alert>{error}</Alert>}

        <div>
          <Button type="button" onClick={requestPost} disabled={pending}>
            {pending ? "جارٍ الاعتماد..." : "اعتماد الفاتورة"}
          </Button>
        </div>
      </CardContent>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد اعتماد فاتورة المشتريات</AlertDialogTitle>
            <AlertDialogDescription>
              فاتورة من المورد {supplier?.name} بإجمالي {formatCents(total)} ({used.length} صنف) —{" "}
              {PAYMENT_STATUS_LABELS[status]}.{" "}
              {paidValue > 0n && treasury
                ? `سيُسجَّل معها سند صرف بمبلغ ${formatCents(paidValue)} من ${treasury.code} - ${treasury.name}، والمتبقي ${formatCents(remaining)} آجل على حساب المورد. `
                : "الإجمالي كله آجل على حساب المورد بلا سند صرف. "}
              لا يمكن تعديل الفاتورة أو حذفها بعد الاعتماد، والتصحيح يكون بإلغائها ثم إدخالها من جديد.
            </AlertDialogDescription>
          </AlertDialogHeader>
          {paidValue > 0n && advance > 0n && (
            <Alert variant="warning">
              للمورد رصيد مدين {formatCents(advance)} من سداد سابق. تأكد أن هذا السداد لا يكرر دفعة سابقة.
            </Alert>
          )}
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
