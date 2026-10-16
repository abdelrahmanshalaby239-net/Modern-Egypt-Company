"use client";

import { startTransition, useActionState, useState } from "react";

import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import type { FormState } from "@/lib/errors";
import { formatCents } from "@/lib/money";
import {
  formatFactor,
  formatQtyUnits,
  formatUnitCostUnits,
  lineTotalCents,
  parseFactor,
  parseQty,
  parseUnitPrice,
  plainQty,
  toBaseUnits,
  unitCostUnits,
} from "@/lib/quantity";
import { saveFormula } from "./actions";

// units = وحدات الصنف البديلة (المعطّلة تظهر فقط لو مختارة حاليًا)
export type FormulaUnit = { id: number; name: string; factor: string; is_active: boolean };
export type FormulaItem = {
  id: number;
  code: string;
  name: string;
  unit: string;
  typeLabel: string;
  is_active: boolean;
  avg_cost: string;
  units: FormulaUnit[];
};
export type FormulaData = {
  id: number | null;
  name: string;
  finished_item_id: string;
  batch_qty: string;
  batch_unit_id: string;
  notes: string;
  is_active: boolean;
};
// unit_id فارغ = الوحدة الأساسية
export type FormulaLine = { key: number; item_id: string; unit_id: string; qty_per_batch: string };

const emptyLine = (key: number): FormulaLine => ({ key, item_id: "", unit_id: "", qty_per_batch: "" });

function unitOptions(item: FormulaItem | undefined, selected: string) {
  return (item?.units ?? []).filter((u) => u.is_active || String(u.id) === selected);
}

export function FormulaForm({
  formula,
  lines: initialLines,
  products,
  materials,
}: {
  formula: FormulaData;
  lines: FormulaLine[];
  products: FormulaItem[];
  materials: FormulaItem[];
}) {
  const [state, action, pending] = useActionState<FormState, FormData>(saveFormula, {});
  const [data, setData] = useState(formula);
  const [lines, setLines] = useState<FormulaLine[]>(initialLines.length ? initialLines : [emptyLine(1)]);
  const [clientError, setClientError] = useState("");

  const set = <K extends keyof FormulaData>(field: K, value: FormulaData[K]) =>
    setData((d) => ({ ...d, [field]: value, ...(field === "finished_item_id" ? { batch_unit_id: "" } : {}) }));
  // تغيير المادة يعيد الوحدة للأساسية
  const updateLine = (key: number, field: keyof Omit<FormulaLine, "key">, value: string) =>
    setLines((ls) =>
      ls.map((l) => (l.key === key ? { ...l, [field]: value, ...(field === "item_id" ? { unit_id: "" } : {}) } : l)),
    );

  const product = products.find((p) => String(p.id) === data.finished_item_id);
  const batchUnit = product?.units.find((u) => String(u.id) === data.batch_unit_id);
  const batchQty = parseQty(data.batch_qty);
  const batchBase =
    batchQty === null ? null : batchUnit ? toBaseUnits(batchQty, parseFactor(batchUnit.factor) ?? 0n) : batchQty;

  // تكلفة تقديرية للدفعة بمتوسط التكلفة الحالي (BigInt) — للاسترشاد فقط، والتكلفة الفعلية وقت تسجيل الإنتاج
  const parsed = lines.map((l) => {
    const item = materials.find((m) => String(m.id) === l.item_id);
    const unit = item?.units.find((u) => String(u.id) === l.unit_id);
    const qty = parseQty(l.qty_per_batch);
    const base = qty === null ? null : unit ? toBaseUnits(qty, parseFactor(unit.factor) ?? 0n) : qty;
    const cost = item && base !== null ? lineTotalCents(base, parseUnitPrice(item.avg_cost) ?? 0n) : null;
    return { line: l, item, unit, qty, base, cost };
  });
  const used = parsed.filter((p) => p.line.item_id || p.line.qty_per_batch);
  const batchCost = used.reduce((t, p) => t + (p.cost ?? 0n), 0n);

  const validate = (): string => {
    if (!data.name.trim()) return "اسم الوصفة مطلوب.";
    if (!product) return "اختر المنتج التام.";
    if (batchQty === null || batchQty <= 0n) return "كمية الدفعة يجب أن تكون رقمًا أكبر من صفر (ثلاث خانات عشرية كحد أقصى).";
    if (batchBase === null) return "كمية الدفعة بالوحدة الأساسية لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة.";
    if (used.length === 0) return "أضف مادة واحدة على الأقل.";
    const seen = new Set<string>();
    for (const [i, p] of used.entries()) {
      const n = i + 1;
      if (!p.item) return `السطر ${n}: اختر المادة.`;
      if (seen.has(p.line.item_id)) return `السطر ${n}: الصنف ${p.item.code} - ${p.item.name} مكرر في الوصفة.`;
      seen.add(p.line.item_id);
      if (p.qty === null || p.qty <= 0n)
        return `السطر ${n}: الكمية لكل دفعة يجب أن تكون رقمًا أكبر من صفر (ثلاث خانات عشرية كحد أقصى).`;
      if (p.base === null)
        return `السطر ${n}: الكمية بالوحدة الأساسية لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة.`;
    }
    return "";
  };

  const submit = () => {
    const error = validate();
    setClientError(error);
    if (error) return;
    const formData = new FormData();
    if (data.id) formData.set("id", String(data.id));
    formData.set("name", data.name);
    formData.set("finished_item_id", data.finished_item_id);
    formData.set("batch_qty", plainQty(batchQty ?? 0n));
    formData.set("batch_unit_id", data.batch_unit_id);
    formData.set("notes", data.notes);
    formData.set("is_active", String(data.is_active));
    formData.set(
      "lines",
      JSON.stringify(
        used.map((p) => ({
          item_id: p.line.item_id,
          unit_id: p.line.unit_id || null,
          qty_per_batch: plainQty(p.qty ?? 0n),
        })),
      ),
    );
    startTransition(() => action(formData));
  };

  const error = clientError || state.error;

  return (
    <div className="grid gap-4">
      <Card>
        <CardHeader>
          <CardTitle>بيانات الوصفة</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label htmlFor="name">اسم الوصفة</Label>
              <Input id="name" value={data.name} onChange={(e) => set("name", e.target.value)} />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="finished_item_id">المنتج التام</Label>
              <NativeSelect
                id="finished_item_id"
                value={data.finished_item_id}
                onChange={(e) => set("finished_item_id", e.target.value)}
              >
                <option value="">اختر المنتج</option>
                {products
                  .filter((p) => p.is_active || String(p.id) === data.finished_item_id)
                  .map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.code} - {p.name}
                      {p.is_active ? "" : " (معطّل)"}
                    </option>
                  ))}
              </NativeSelect>
            </div>
          </div>
          <div className="grid gap-3 sm:grid-cols-[12rem_14rem_1fr] sm:items-start md:max-lg:grid-cols-1">
            <div className="grid gap-2">
              <Label htmlFor="batch_qty">الكمية الناتجة من الدفعة</Label>
              <Input
                id="batch_qty"
                dir="ltr"
                inputMode="decimal"
                value={data.batch_qty}
                aria-invalid={batchQty === null}
                onChange={(e) => set("batch_qty", e.target.value)}
              />
              {batchUnit && batchBase !== null && batchQty !== null && batchQty > 0n && (
                <div className="text-xs text-muted-foreground">
                  = {formatQtyUnits(batchBase)} {product?.unit}
                </div>
              )}
            </div>
            <div className="grid gap-2">
              <Label htmlFor="batch_unit_id">الوحدة</Label>
              <NativeSelect
                id="batch_unit_id"
                value={data.batch_unit_id}
                disabled={!product}
                onChange={(e) => set("batch_unit_id", e.target.value)}
              >
                <option value="">{product?.unit ?? "—"}</option>
                {unitOptions(product, data.batch_unit_id).map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.name} ({formatFactor(u.factor)} {product?.unit}){u.is_active ? "" : " (معطّلة)"}
                  </option>
                ))}
              </NativeSelect>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="notes">ملاحظات (اختياري)</Label>
              <Input id="notes" value={data.notes} onChange={(e) => set("notes", e.target.value)} />
            </div>
          </div>
          <label className="flex items-center gap-2 text-sm">
            <Checkbox checked={data.is_active} onChange={(e) => set("is_active", e.target.checked)} />
            وصفة نشطة (تظهر في تسجيل الإنتاج)
          </label>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>المواد لكل دفعة</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4">
          <div className="overflow-x-auto">
            <table className="line-table w-full text-sm sm:min-w-[48rem]">
              <thead>
                <tr className="border-b text-muted-foreground">
                  <th className="p-2 text-start font-semibold">المادة</th>
                  <th className="w-40 p-2 text-start font-semibold">الوحدة</th>
                  <th className="w-36 p-2 text-start font-semibold">الكمية لكل دفعة</th>
                  <th className="w-36 p-2 text-start font-semibold">التكلفة التقديرية</th>
                  <th className="w-16 p-2" />
                </tr>
              </thead>
              <tbody>
                {parsed.map(({ line: l, item, unit, qty, base, cost }) => (
                  <tr key={l.key} className="border-b align-top">
                    <td data-label="المادة" className="p-2">
                      <NativeSelect
                        aria-label="المادة"
                        value={l.item_id}
                        onChange={(e) => updateLine(l.key, "item_id", e.target.value)}
                      >
                        <option value="">اختر المادة</option>
                        {materials
                          .filter((m) => m.is_active || String(m.id) === l.item_id)
                          .map((m) => (
                            <option key={m.id} value={m.id}>
                              {m.code} - {m.name} ({m.typeLabel}){m.is_active ? "" : " (معطّل)"}
                            </option>
                          ))}
                      </NativeSelect>
                    </td>
                    <td data-label="الوحدة" className="p-2">
                      <NativeSelect
                        aria-label="الوحدة"
                        value={l.unit_id}
                        disabled={!item}
                        onChange={(e) => updateLine(l.key, "unit_id", e.target.value)}
                      >
                        <option value="">{item?.unit ?? "—"}</option>
                        {unitOptions(item, l.unit_id).map((u) => (
                          <option key={u.id} value={u.id}>
                            {u.name} ({formatFactor(u.factor)} {item?.unit}){u.is_active ? "" : " (معطّلة)"}
                          </option>
                        ))}
                      </NativeSelect>
                    </td>
                    <td data-label="الكمية لكل دفعة" className="p-2">
                      <Input
                        aria-label="الكمية لكل دفعة"
                        dir="ltr"
                        inputMode="decimal"
                        value={l.qty_per_batch}
                        aria-invalid={qty === null}
                        onChange={(e) => updateLine(l.key, "qty_per_batch", e.target.value)}
                      />
                      {unit && qty !== null && qty > 0n && (
                        <div
                          className={`pt-1 text-xs ${base === null ? "text-destructive" : "text-muted-foreground"}`}
                        >
                          {base === null ? "تحويل غير دقيق" : `= ${formatQtyUnits(base)} ${item?.unit}`}
                        </div>
                      )}
                    </td>
                    <td data-label="التكلفة التقديرية" dir="ltr" className="p-2 pt-4 text-start tabular-nums">
                      {cost === null ? "" : formatCents(cost)}
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
                  <td className="p-2" colSpan={3}>
                    تكلفة الدفعة التقديرية
                  </td>
                  <td dir="ltr" className="p-2 text-start tabular-nums">
                    {formatCents(batchCost)}
                  </td>
                  <td />
                </tr>
                {batchBase !== null && batchBase > 0n && batchCost > 0n && (
                  <tr className="text-muted-foreground">
                    <td className="p-2" colSpan={3}>
                      تكلفة الوحدة التقديرية (لكل {product?.unit})
                    </td>
                    <td dir="ltr" className="p-2 text-start tabular-nums">
                      {formatUnitCostUnits(unitCostUnits(batchCost, batchBase))}
                    </td>
                    <td />
                  </tr>
                )}
              </tfoot>
            </table>
          </div>
          <div>
            <Button
              type="button"
              variant="outline"
              onClick={() => setLines((ls) => [...ls, emptyLine(Math.max(0, ...ls.map((x) => x.key)) + 1)])}
            >
              إضافة مادة
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            التكلفة التقديرية بمتوسط التكلفة الحالي للاسترشاد فقط. التكلفة الفعلية تُحسب وقت تسجيل الإنتاج بمتوسط
            التكلفة في تلك اللحظة، وتعديل الوصفة لا يغيّر أوامر إنتاج سُجّلت من قبل.
          </p>
        </CardContent>
      </Card>

      {error && <Alert>{error}</Alert>}

      <div>
        <Button type="button" onClick={submit} disabled={pending}>
          {pending ? "جارٍ الحفظ..." : "حفظ الوصفة"}
        </Button>
      </div>
    </div>
  );
}
