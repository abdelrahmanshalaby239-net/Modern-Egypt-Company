"use client";

import { startTransition, useActionState, useState, type KeyboardEvent } from "react";

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
  formatQtyUnits,
  lineTotalCents,
  parseFactor,
  parseQty,
  plainQty,
  toBaseUnits,
} from "@/lib/quantity";
import { postSalesInvoice } from "../actions";

// المنتج التام: الوحدة الأساسية (سعرها sale_price) + الوحدات البديلة النشطة بأسعارها، ووحدة البيع الافتراضية
// (فارغ = الأساسية). qty = الرصيد الحالي بالوحدة الأساسية.
export type SalesItem = {
  id: number;
  code: string;
  name: string;
  unit: string;
  barcode: string;
  sale_price: string;
  qty: string;
  default_unit_id: string;
  units: { id: number; name: string; factor: string; sale_price: string }[];
};
// balance = رصيد العميل الحالي من القيود (مدين موجب = مستحق عليه، دائن سالب = مقبوض مقدمًا)
type Customer = { id: number; name: string; balance: string };
// unit_id فارغ = الوحدة الأساسية
type Line = { key: number; item_id: string; unit_id: string; qty: string; unit_price: string };

const emptyLine = (key: number): Line => ({ key, item_id: "", unit_id: "", qty: "", unit_price: "" });

// سعر الوحدة المقترح: سعر الوحدة البديلة أو سعر الوحدة الأساسية، وقابل للتعديل
function suggestedPrice(item: SalesItem | undefined, unitId: string): string {
  if (!item) return "";
  return unitId ? (item.units.find((u) => String(u.id) === unitId)?.sale_price ?? "") : item.sale_price;
}

export function SalesForm({
  defaultDate,
  customers,
  items,
  treasuries,
}: {
  defaultDate: string;
  customers: Customer[];
  items: SalesItem[];
  treasuries: PostingAccount[];
}) {
  const [state, action, pending] = useActionState<FormState, FormData>(postSalesInvoice, {});
  const [docDate, setDocDate] = useState(defaultDate);
  const [customerId, setCustomerId] = useState("");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<Line[]>([emptyLine(1)]);
  const [barcode, setBarcode] = useState("");
  const [barcodeError, setBarcodeError] = useState("");
  const [received, setReceived] = useState("0");
  const [treasuryId, setTreasuryId] = useState(String(treasuries[0]?.id ?? ""));
  const [clientError, setClientError] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false);

  // اختيار الصنف يضع وحدة البيع الافتراضية وسعرها، واختيار الوحدة يضع سعرها
  const updateLine = (key: number, field: keyof Omit<Line, "key">, value: string) =>
    setLines((ls) =>
      ls.map((l) => {
        if (l.key !== key) return l;
        if (field === "item_id") {
          const item = items.find((i) => String(i.id) === value);
          const unitId = item?.default_unit_id ?? "";
          return { ...l, item_id: value, unit_id: unitId, unit_price: suggestedPrice(item, unitId) };
        }
        if (field === "unit_id") {
          const item = items.find((i) => String(i.id) === l.item_id);
          return { ...l, unit_id: value, unit_price: suggestedPrice(item, value) };
        }
        return { ...l, [field]: value };
      }),
    );

  // الباركود يضيف الصنف بوحدة البيع الافتراضية (في أول سطر فارغ أو سطر جديد)
  const addByBarcode = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    const code = barcode.trim();
    if (!code) return;
    const item = items.find((i) => i.barcode === code);
    if (!item) {
      setBarcodeError(`لا يوجد منتج تام نشط بالباركود ${code}.`);
      return;
    }
    setBarcodeError("");
    setBarcode("");
    const filled: Line = {
      key: 0,
      item_id: String(item.id),
      unit_id: item.default_unit_id,
      qty: "1",
      unit_price: suggestedPrice(item, item.default_unit_id),
    };
    setLines((ls) => {
      const empty = ls.find((l) => !l.item_id && !l.qty && !l.unit_price);
      if (empty) return ls.map((l) => (l.key === empty.key ? { ...filled, key: l.key } : l));
      return [...ls, { ...filled, key: Math.max(0, ...ls.map((x) => x.key)) + 1 }];
    });
  };

  // إجمالي كل سطر وإجمالي الفاتورة بالقروش (BigInt) — معاينة، وقاعدة البيانات تحسب القيمة المعتمدة
  const parsed = lines.map((l) => {
    const item = items.find((i) => String(i.id) === l.item_id);
    const unit = item?.units.find((u) => String(u.id) === l.unit_id);
    const qty = parseQty(l.qty);
    const price = l.unit_price.trim() === "" ? null : parseCents(l.unit_price);
    const base = qty === null ? null : unit ? toBaseUnits(qty, parseFactor(unit.factor) ?? 0n) : qty;
    return {
      line: l,
      item,
      unit,
      qty,
      base,
      price,
      total: qty !== null && price !== null ? lineTotalCents(qty, price * 100n) : null,
    };
  });
  const used = parsed.filter((p) => p.line.item_id || p.line.qty || p.line.unit_price);
  const total = used.reduce((t, p) => t + (p.total ?? 0n), 0n);

  // الكمية المطلوبة لكل صنف بكل وحداته (بالوحدة الأساسية) مقابل رصيده
  const needOf = new Map<number, bigint>();
  for (const p of used) if (p.item && p.base) needOf.set(p.item.id, (needOf.get(p.item.id) ?? 0n) + p.base);
  const shortages = items
    .filter((i) => (needOf.get(i.id) ?? 0n) > (parseQty(i.qty) ?? 0n))
    .map((i) => ({ item: i, need: needOf.get(i.id) ?? 0n, stock: parseQty(i.qty) ?? 0n }));

  const customer = customers.find((c) => String(c.id) === customerId);
  const treasury = treasuries.find((t) => String(t.id) === treasuryId);
  const receivedCents = parseCents(received);
  const receivedValue = receivedCents ?? 0n;
  const remaining = total - receivedValue;
  const status = paymentStatus(total, receivedValue);
  // رصيد دائن للعميل = مقبوض سابق لم تقابله فاتورة (مثل تحصيل فاتورة أُلغيت)
  const balance = customer ? (parseCents(customer.balance, { signed: true }) ?? 0n) : 0n;
  const advance = balance < 0n ? -balance : 0n;

  const validate = (): string => {
    if (!parseDate(docDate)) return "تاريخ الفاتورة غير صحيح. اكتبه بصيغة يوم/شهر/سنة.";
    if (!customer) return "اختر العميل.";
    if (used.length === 0) return "أضف صنفًا واحدًا على الأقل.";
    const seen = new Set<string>();
    for (const [i, p] of used.entries()) {
      const n = i + 1;
      if (!p.item) return `السطر ${n}: اختر الصنف.`;
      const key = `${p.line.item_id}:${p.line.unit_id}`;
      if (seen.has(key)) return `السطر ${n}: الصنف ${p.item.code} - ${p.item.name} بنفس الوحدة مكرر في الفاتورة.`;
      seen.add(key);
      if (p.qty === null) return `السطر ${n}: الكمية غير صالحة (رقم موجب بثلاث خانات عشرية كحد أقصى).`;
      if (p.qty <= 0n) return `السطر ${n}: الكمية يجب أن تكون أكبر من صفر.`;
      if (p.base === null)
        return `السطر ${n}: الكمية بالوحدة الأساسية لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة.`;
      if (p.price === null) return `السطر ${n}: سعر البيع مطلوب (رقم موجب بخانتين عشريتين كحد أقصى).`;
      if ((p.total ?? 0n) <= 0n) return `السطر ${n}: إجمالي السطر يجب أن يكون أكبر من صفر.`;
    }
    const short = shortages[0];
    if (short)
      return `الكمية المطلوبة من الصنف ${short.item.code} - ${short.item.name} هي ${formatQtyUnits(short.need)} ${short.item.unit} والمتاح ${formatQtyUnits(short.stock)} ${short.item.unit} فقط (النقص ${formatQtyUnits(short.need - short.stock)}).`;
    if (receivedCents === null) return "المقبوض الآن غير صالح (صفر أو رقم موجب بخانتين عشريتين كحد أقصى).";
    if (receivedCents > total)
      return `المقبوض الآن ${formatCents(receivedCents)} أكبر من إجمالي الفاتورة ${formatCents(total)}.`;
    if (receivedCents > 0n && !treasury) return "اختر الخزينة أو البنك المقبوض فيه.";
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
    formData.set("customer_id", customerId);
    formData.set("notes", notes);
    formData.set("received_amount", plainCents(receivedValue));
    formData.set("received_treasury_account_id", receivedValue > 0n ? treasuryId : "");
    formData.set(
      "lines",
      JSON.stringify(
        used.map((p) => ({
          item_id: p.line.item_id,
          unit_id: p.unit ? p.unit.id : null,
          qty: plainQty(p.qty ?? 0n),
          unit_price: plainCents(p.price ?? 0n),
        })),
      ),
    );
    startTransition(() => action(formData));
  };

  const error = clientError || state.error;

  return (
    <Card>
      <CardContent className="grid gap-5">
        <div className="grid gap-3 sm:grid-cols-[10rem_1fr_14rem] md:max-lg:grid-cols-1">
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
            <Label htmlFor="customer">العميل</Label>
            <NativeSelect id="customer" value={customerId} onChange={(e) => setCustomerId(e.target.value)}>
              <option value="">اختر العميل</option>
              {customers.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </NativeSelect>
            {customer && (
              <div className="text-xs text-muted-foreground">
                رصيد العميل الحالي: <span dir="ltr">{formatBalance(customer.balance)}</span>
              </div>
            )}
          </div>
          <div className="grid gap-2">
            <Label htmlFor="barcode">الباركود (اختياري)</Label>
            <Input
              id="barcode"
              dir="ltr"
              placeholder="امسح ثم Enter"
              value={barcode}
              onChange={(e) => setBarcode(e.target.value)}
              onKeyDown={addByBarcode}
            />
            {barcodeError && <div className="text-xs text-destructive">{barcodeError}</div>}
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="line-table w-full text-sm sm:min-w-[56rem]">
            <thead>
              <tr className="border-b text-muted-foreground">
                <th className="p-2 text-start font-semibold">الصنف</th>
                <th className="w-40 p-2 text-start font-semibold">الوحدة</th>
                <th className="w-32 p-2 text-start font-semibold">الكمية</th>
                <th className="w-32 p-2 text-start font-semibold">سعر الوحدة</th>
                <th className="w-32 p-2 text-start font-semibold">الإجمالي</th>
                <th className="w-16 p-2" />
              </tr>
            </thead>
            <tbody>
              {parsed.map(({ line: l, item, unit, qty, base, price, total: lineTotal }) => {
                const stock = item ? (parseQty(item.qty) ?? 0n) : 0n;
                const factor = unit ? (parseFactor(unit.factor) ?? 0n) : 0n;
                return (
                  <tr key={l.key} className="border-b align-top">
                    <td data-label="الصنف" className="p-2">
                      <NativeSelect
                        aria-label="الصنف"
                        value={l.item_id}
                        onChange={(e) => updateLine(l.key, "item_id", e.target.value)}
                      >
                        <option value="">اختر الصنف</option>
                        {items.map((i) => (
                          <option key={i.id} value={i.id}>
                            {i.code} - {i.name}
                          </option>
                        ))}
                      </NativeSelect>
                      {item && (
                        <div
                          className={`pt-1 text-xs ${(needOf.get(item.id) ?? 0n) > stock ? "font-semibold text-destructive" : "text-muted-foreground"}`}
                        >
                          المتاح: <span dir="ltr">{formatQtyUnits(stock)}</span> {item.unit}
                          {unit && factor > 0n && (
                            <>
                              {" "}
                              (≈ <span dir="ltr">{formatQtyUnits((stock * 1000000n) / factor)}</span> {unit.name})
                            </>
                          )}
                        </div>
                      )}
                    </td>
                    <td data-label="الوحدة" className="p-2">
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
                    <td data-label="الكمية" className="p-2">
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
                    <td data-label="سعر الوحدة" className="p-2">
                      <Input
                        aria-label="سعر الوحدة"
                        dir="ltr"
                        inputMode="decimal"
                        value={l.unit_price}
                        aria-invalid={l.unit_price.trim() !== "" && price === null}
                        onChange={(e) => updateLine(l.key, "unit_price", e.target.value)}
                      />
                    </td>
                    <td data-label="الإجمالي" dir="ltr" className="p-2 pt-4 text-start tabular-nums">
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
                );
              })}
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
            onClick={() => setLines((ls) => [...ls, emptyLine(Math.max(0, ...ls.map((x) => x.key)) + 1)])}
          >
            إضافة صنف
          </Button>
        </div>

        {shortages.length > 0 && (
          <Alert>
            الرصيد لا يكفي من:{" "}
            {shortages
              .map(
                (s) =>
                  `${s.item.code} - ${s.item.name} (المطلوب ${formatQtyUnits(s.need)} والمتاح ${formatQtyUnits(s.stock)} ${s.item.unit})`,
              )
              .join("، ")}
            .
          </Alert>
        )}

        <div className="grid gap-2">
          <Label htmlFor="notes">البيان (اختياري)</Label>
          <Input id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </div>

        <div className="grid gap-3 rounded-md border p-3">
          <div className="font-semibold">التحصيل</div>
          <div className="grid gap-3 sm:grid-cols-[12rem_1fr] sm:items-end">
            <div className="grid gap-2">
              <Label htmlFor="received">المقبوض الآن</Label>
              <Input
                id="received"
                dir="ltr"
                inputMode="decimal"
                value={received}
                aria-invalid={receivedCents === null || receivedValue > total}
                onChange={(e) => setReceived(e.target.value)}
              />
            </div>
            <div className="flex flex-wrap gap-2">
              <Button type="button" variant="outline" size="sm" onClick={() => setReceived("0")}>
                آجل بالكامل
              </Button>
              <Button type="button" variant="outline" size="sm" onClick={() => setReceived(plainCents(total))}>
                تحصيل كامل الإجمالي
              </Button>
            </div>
          </div>
          {receivedValue > 0n && (
            <div className="grid max-w-md gap-2">
              <Label htmlFor="treasury">في الخزينة/البنك</Label>
              <NativeSelect id="treasury" value={treasuryId} onChange={(e) => setTreasuryId(e.target.value)}>
                {treasuries.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.code} - {t.name}
                  </option>
                ))}
              </NativeSelect>
            </div>
          )}
          {receivedValue > 0n && treasuries.length === 0 && (
            <Alert variant="warning">لا توجد خزينة أو بنك نشط. حدّد حساب الخزينة من دليل الحسابات أولًا.</Alert>
          )}
          <dl className="grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
            <div>
              <dt className="text-muted-foreground">إجمالي الفاتورة</dt>
              <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                {formatCents(total)}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">المقبوض الآن</dt>
              <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                {formatCents(receivedValue)}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">المتبقي (آجل على العميل)</dt>
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
              للعميل رصيد دائن {formatCents(advance)} (مقبوض سابق لم تقابله فاتورة، مثل تحصيل فاتورة ملغاة). لو هذه
              الفاتورة تصحيح لفاتورة ملغاة حُصّلت من قبل، اترك المقبوض الآن صفرًا: المقبوض السابق يُخصم من رصيد العميل
              تلقائيًا، والتحصيل مرة أخرى يكرره.
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
            <AlertDialogTitle>تأكيد اعتماد فاتورة المبيعات</AlertDialogTitle>
            <AlertDialogDescription>
              فاتورة للعميل {customer?.name} بإجمالي {formatCents(total)} ({used.length} سطر) —{" "}
              {PAYMENT_STATUS_LABELS[status]}.{" "}
              {receivedValue > 0n && treasury
                ? `سيُسجَّل معها سند قبض بمبلغ ${formatCents(receivedValue)} في ${treasury.code} - ${treasury.name}، والمتبقي ${formatCents(remaining)} آجل على العميل. `
                : "الإجمالي كله آجل على العميل بلا سند قبض. "}
              تُصرف الكميات من المخزون بمتوسط التكلفة الآن. لا يمكن تعديل الفاتورة أو حذفها بعد الاعتماد، والتصحيح
              يكون بإلغائها ثم إدخالها من جديد.
            </AlertDialogDescription>
          </AlertDialogHeader>
          {receivedValue > 0n && advance > 0n && (
            <Alert variant="warning">
              للعميل رصيد دائن {formatCents(advance)} من تحصيل سابق. تأكد أن هذا التحصيل لا يكرر مبلغًا قُبض من قبل.
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
