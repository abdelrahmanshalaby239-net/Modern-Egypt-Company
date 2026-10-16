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
import {
  formatFactor,
  formatQtyUnits,
  formatUnitCostUnits,
  issueCostCents,
  mulQtyUnits,
  parseFactor,
  parseQty,
  plainQty,
  toBaseUnits,
  toBaseUnitsRounded,
  unitCostUnits,
} from "@/lib/quantity";
import { postProductionOrder } from "../actions";

// الوحدات كلها (المعطّلة لحساب المعياري من وصفة قديمة، ولا تُختار)
type Unit = { id: number; name: string; factor: string; is_active: boolean };
// qty و value = الرصيد الحالي وقيمته (لمعاينة تكلفة الصرف بنفس طريقة قاعدة البيانات)
export type ProductionItem = {
  id: number;
  code: string;
  name: string;
  unit: string;
  type: string;
  typeLabel: string;
  qty: string;
  value: string;
  units: Unit[];
};
export type ProductionFormula = {
  id: number;
  name: string;
  finished_item_id: number;
  batch_qty: string;
  batch_unit_id: string;
  lines: { item_id: number; unit_id: string; qty_per_batch: string }[];
};
// unit_id فارغ = الوحدة الأساسية
type Line = { key: number; item_id: string; unit_id: string; qty: string };

const ONE = 1000n; // دفعة واحدة بالألف
const factorOf = (units: Unit[], unitId: string) => {
  const unit = units.find((u) => String(u.id) === unitId);
  return unit ? (parseFactor(unit.factor) ?? 0n) : 1000000n;
};

// الكمية المنتجة وسطور الاستهلاك من الوصفة × عدد الدفعات (اقتراح قابل للتعديل)
function fromFormula(formula: ProductionFormula | undefined, batches: bigint | null) {
  if (!formula) return { qty: "", unitId: "", lines: [] as Line[] };
  const times = (value: string) =>
    batches === null || batches <= 0n ? "" : plainQty(mulQtyUnits(parseQty(value) ?? 0n, batches));
  return {
    qty: times(formula.batch_qty),
    unitId: formula.batch_unit_id,
    lines: formula.lines.map((l, i) => ({
      key: i + 1,
      item_id: String(l.item_id),
      unit_id: l.unit_id,
      qty: times(l.qty_per_batch),
    })),
  };
}

export function ProductionForm({
  defaultDate,
  formulas,
  initialFormulaId,
  products,
  materials,
  extraAccounts,
}: {
  defaultDate: string;
  formulas: ProductionFormula[];
  initialFormulaId: string;
  products: ProductionItem[];
  materials: ProductionItem[];
  extraAccounts: PostingAccount[];
}) {
  const initial = fromFormula(
    formulas.find((f) => String(f.id) === initialFormulaId),
    ONE,
  );
  const [state, action, pending] = useActionState<FormState, FormData>(postProductionOrder, {});
  const [docDate, setDocDate] = useState(defaultDate);
  const [formulaId, setFormulaId] = useState(initial.lines.length ? initialFormulaId : "");
  const [batches, setBatches] = useState("1");
  const [qtyProduced, setQtyProduced] = useState(initial.qty);
  const [unitId, setUnitId] = useState(initial.unitId);
  const [lines, setLines] = useState<Line[]>(initial.lines);
  const [extraCost, setExtraCost] = useState("0");
  const [extraAccountId, setExtraAccountId] = useState("");
  const [notes, setNotes] = useState("");
  const [clientError, setClientError] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false);

  const formula = formulas.find((f) => String(f.id) === formulaId);
  const product = products.find((p) => p.id === formula?.finished_item_id);
  const batchesUnits = parseQty(batches);

  // تغيير الوصفة أو عدد الدفعات يعيد توليد الكمية المنتجة وسطور الاستهلاك
  const regenerate = (nextFormulaId: string, nextBatches: string) => {
    const next = fromFormula(
      formulas.find((f) => String(f.id) === nextFormulaId),
      parseQty(nextBatches),
    );
    setQtyProduced(next.qty);
    setUnitId(next.unitId);
    setLines(next.lines);
  };
  const updateLine = (key: number, field: keyof Omit<Line, "key">, value: string) =>
    setLines((ls) =>
      ls.map((l) => (l.key === key ? { ...l, [field]: value, ...(field === "item_id" ? { unit_id: "" } : {}) } : l)),
    );

  // الكمية المنتجة بالوحدة الأساسية (null لو التحويل غير دقيق)
  const productUnit = product?.units.find((u) => String(u.id) === unitId);
  const produced = parseQty(qtyProduced);
  const producedBase =
    produced === null || !product ? null : toBaseUnits(produced, factorOf(product.units, unitId));

  // سطور الاستهلاك: الكمية الأساسية، المعيارية من الوصفة، المتاح، وتكلفة الصرف بنفس طريقة قاعدة البيانات
  const parsed = lines.map((l) => {
    const item = materials.find((m) => String(m.id) === l.item_id);
    const unit = item?.units.find((u) => String(u.id) === l.unit_id);
    const qty = parseQty(l.qty);
    const base = qty === null ? null : unit ? toBaseUnits(qty, parseFactor(unit.factor) ?? 0n) : qty;
    const inactiveUnit = unit !== undefined && !unit.is_active;
    const formulaLine = formula?.lines.find((fl) => String(fl.item_id) === l.item_id);
    const standard =
      formulaLine && item && batchesUnits !== null
        ? toBaseUnitsRounded(
            mulQtyUnits(parseQty(formulaLine.qty_per_batch) ?? 0n, batchesUnits),
            factorOf(item.units, formulaLine.unit_id),
          )
        : null;
    const stock = item ? (parseQty(item.qty) ?? 0n) : 0n;
    const shortage = item && base !== null && base > stock ? base - stock : null;
    const cost =
      item && base !== null && base > 0n
        ? issueCostCents(base, stock, parseCents(item.value, { signed: true }) ?? 0n)
        : null;
    return { line: l, item, unit, inactiveUnit, qty, base, standard, stock, shortage, cost };
  });
  const used = parsed.filter((p) => p.line.item_id || p.line.qty);
  const raw = used.filter((p) => p.item?.type === "raw_material").reduce((t, p) => t + (p.cost ?? 0n), 0n);
  const packaging = used.filter((p) => p.item?.type === "packaging").reduce((t, p) => t + (p.cost ?? 0n), 0n);
  const materialsCost = raw + packaging;
  const extraCents = parseCents(extraCost);
  const extra = extraCents ?? 0n;
  const total = materialsCost + extra;
  const unitCost = producedBase && producedBase > 0n && total > 0n ? unitCostUnits(total, producedBase) : null;
  const shortages = used.filter((p) => p.shortage !== null);
  const extraAccount = extraAccounts.find((a) => String(a.id) === extraAccountId);

  const validate = (): string => {
    if (!parseDate(docDate)) return "تاريخ الإنتاج غير صحيح. اكتبه بصيغة يوم/شهر/سنة.";
    if (!formula || !product) return "اختر الوصفة.";
    if (batchesUnits === null || batchesUnits <= 0n)
      return "عدد الدفعات يجب أن يكون رقمًا أكبر من صفر (ثلاث خانات عشرية كحد أقصى).";
    if (produced === null || produced <= 0n)
      return "الكمية المنتجة يجب أن تكون رقمًا أكبر من صفر (ثلاث خانات عشرية كحد أقصى).";
    if (productUnit && !productUnit.is_active) return `وحدة الكمية المنتجة ${productUnit.name} معطّلة. اختر وحدة أخرى.`;
    if (producedBase === null)
      return "الكمية المنتجة بالوحدة الأساسية لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة.";
    if (used.length === 0) return "أضف مادة واحدة على الأقل.";
    const seen = new Set<string>();
    for (const [i, p] of used.entries()) {
      const n = i + 1;
      if (!p.item) return `السطر ${n}: اختر المادة.`;
      if (seen.has(p.line.item_id)) return `السطر ${n}: الصنف ${p.item.code} - ${p.item.name} مكرر.`;
      seen.add(p.line.item_id);
      if (p.qty === null || p.qty <= 0n)
        return `السطر ${n}: الكمية يجب أن تكون رقمًا أكبر من صفر (ثلاث خانات عشرية كحد أقصى).`;
      if (p.inactiveUnit) return `السطر ${n}: الوحدة ${p.unit?.name} معطّلة. اختر وحدة أخرى.`;
      if (p.base === null)
        return `السطر ${n}: الكمية بالوحدة الأساسية لا تزيد عن ثلاث خانات عشرية. عدّل الكمية أو الوحدة.`;
      if (p.shortage !== null)
        return `السطر ${n}: الكمية المطلوبة من الصنف ${p.item.code} - ${p.item.name} هي ${formatQtyUnits(p.base)} ${p.item.unit} والمتاح ${formatQtyUnits(p.stock)} ${p.item.unit} فقط (النقص ${formatQtyUnits(p.shortage)}).`;
    }
    if (extraCents === null)
      return "التكاليف الإضافية غير صالحة (صفر أو رقم موجب بخانتين عشريتين كحد أقصى).";
    if (extra > 0n && !extraAccount) return "اختر الحساب الدائن للتكاليف الإضافية.";
    if (total <= 0n) return "تكلفة الإنتاج صفر، ولا يُسجَّل قيد بلا قيمة.";
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
    formData.set("formula_id", formulaId);
    formData.set("batches", plainQty(batchesUnits ?? 0n));
    formData.set("qty_produced", plainQty(produced ?? 0n));
    formData.set("unit_id", unitId);
    formData.set("extra_cost", plainCents(extra));
    formData.set("extra_cost_account_id", extra > 0n ? extraAccountId : "");
    formData.set("notes", notes);
    formData.set(
      "lines",
      JSON.stringify(
        used.map((p) => ({ item_id: p.line.item_id, unit_id: p.line.unit_id || null, qty: plainQty(p.qty ?? 0n) })),
      ),
    );
    startTransition(() => action(formData));
  };

  const error = clientError || state.error;
  const producedUnitName = productUnit?.name ?? product?.unit;

  return (
    <Card>
      <CardContent className="grid gap-5">
        <div className="grid gap-3 sm:grid-cols-[10rem_1fr_8rem]">
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
            <Label htmlFor="formula">الوصفة</Label>
            <NativeSelect
              id="formula"
              value={formulaId}
              onChange={(e) => {
                setFormulaId(e.target.value);
                regenerate(e.target.value, batches);
              }}
            >
              <option value="">اختر الوصفة</option>
              {formulas.map((f) => {
                const p = products.find((x) => x.id === f.finished_item_id);
                return (
                  <option key={f.id} value={f.id}>
                    {f.name}
                    {p ? ` ← ${p.code} - ${p.name}` : ""}
                  </option>
                );
              })}
            </NativeSelect>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="batches">عدد الدفعات</Label>
            <Input
              id="batches"
              dir="ltr"
              inputMode="decimal"
              value={batches}
              aria-invalid={batchesUnits === null}
              onChange={(e) => {
                setBatches(e.target.value);
                regenerate(formulaId, e.target.value);
              }}
            />
          </div>
        </div>

        {product && (
          <div className="grid gap-3 sm:grid-cols-[1fr_10rem_12rem] sm:items-start">
            <div className="grid gap-1 text-sm">
              <span className="text-muted-foreground">المنتج التام</span>
              <span className="font-semibold">
                {product.code} - {product.name}
              </span>
              <span className="text-xs text-muted-foreground">
                الرصيد الحالي: <span dir="ltr">{formatQtyUnits(parseQty(product.qty) ?? 0n)}</span> {product.unit}
              </span>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="qty_produced">الكمية المنتجة</Label>
              <Input
                id="qty_produced"
                dir="ltr"
                inputMode="decimal"
                value={qtyProduced}
                aria-invalid={produced === null}
                onChange={(e) => setQtyProduced(e.target.value)}
              />
              {unitId && produced !== null && produced > 0n && (
                <div className={`text-xs ${producedBase === null ? "text-destructive" : "text-muted-foreground"}`}>
                  {producedBase === null ? "تحويل غير دقيق" : `= ${formatQtyUnits(producedBase)} ${product.unit}`}
                </div>
              )}
            </div>
            <div className="grid gap-2">
              <Label htmlFor="unit">الوحدة</Label>
              <NativeSelect id="unit" value={unitId} onChange={(e) => setUnitId(e.target.value)}>
                <option value="">{product.unit}</option>
                {product.units
                  .filter((u) => u.is_active || String(u.id) === unitId)
                  .map((u) => (
                    <option key={u.id} value={u.id}>
                      {u.name} ({formatFactor(u.factor)} {product.unit}){u.is_active ? "" : " (معطّلة)"}
                    </option>
                  ))}
              </NativeSelect>
            </div>
          </div>
        )}

        {formula && (
          <>
            <div className="overflow-x-auto">
              <table className="line-table w-full text-sm sm:min-w-[60rem]">
                <thead>
                  <tr className="border-b text-muted-foreground">
                    <th className="p-2 text-start font-semibold">المادة</th>
                    <th className="w-36 p-2 text-start font-semibold">الوحدة</th>
                    <th className="w-32 p-2 text-start font-semibold">الكمية المستهلكة</th>
                    <th className="w-32 p-2 text-start font-semibold">المعياري من الوصفة</th>
                    <th className="w-32 p-2 text-start font-semibold">المتاح</th>
                    <th className="w-32 p-2 text-start font-semibold">التكلفة (تقديرية)</th>
                    <th className="w-16 p-2" />
                  </tr>
                </thead>
                <tbody>
                  {parsed.map(({ line: l, item, unit, qty, base, standard, stock, shortage, cost }) => (
                    <tr key={l.key} className="border-b align-top">
                      <td data-label="المادة" className="p-2">
                        <NativeSelect
                          aria-label="المادة"
                          value={l.item_id}
                          onChange={(e) => updateLine(l.key, "item_id", e.target.value)}
                        >
                          <option value="">اختر المادة</option>
                          {materials.map((m) => (
                            <option key={m.id} value={m.id}>
                              {m.code} - {m.name} ({m.typeLabel})
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
                          {(item?.units ?? [])
                            .filter((u) => u.is_active || String(u.id) === l.unit_id)
                            .map((u) => (
                              <option key={u.id} value={u.id}>
                                {u.name} ({formatFactor(u.factor)} {item?.unit}){u.is_active ? "" : " (معطّلة)"}
                              </option>
                            ))}
                        </NativeSelect>
                      </td>
                      <td data-label="الكمية المستهلكة" className="p-2">
                        <Input
                          aria-label="الكمية المستهلكة"
                          dir="ltr"
                          inputMode="decimal"
                          value={l.qty}
                          aria-invalid={qty === null}
                          onChange={(e) => updateLine(l.key, "qty", e.target.value)}
                        />
                        {unit && qty !== null && qty > 0n && (
                          <div
                            className={`pt-1 text-xs ${base === null ? "text-destructive" : "text-muted-foreground"}`}
                          >
                            {base === null ? "تحويل غير دقيق" : `= ${formatQtyUnits(base)} ${item?.unit}`}
                          </div>
                        )}
                      </td>
                      <td data-label="المعياري من الوصفة" className="p-2 pt-4 tabular-nums">
                        {item &&
                          (standard === null ? (
                            <span className="text-muted-foreground">ليست في الوصفة</span>
                          ) : (
                            <>
                              <span dir="ltr">{formatQtyUnits(standard)}</span> {item.unit}
                              {base !== null && base !== standard && (
                                <div className="text-xs text-muted-foreground">
                                  {base > standard ? "هالك زائد" : "أقل من المعياري"}:{" "}
                                  <span dir="ltr">{formatQtyUnits(base > standard ? base - standard : standard - base)}</span>
                                </div>
                              )}
                            </>
                          ))}
                      </td>
                      <td data-label="المتاح" className="p-2 pt-4 tabular-nums">
                        {item && (
                          <>
                            <span dir="ltr">{formatQtyUnits(stock)}</span> {item.unit}
                            {shortage !== null && (
                              <div className="text-xs font-semibold text-destructive">
                                نقص <span dir="ltr">{formatQtyUnits(shortage)}</span>
                              </div>
                            )}
                          </>
                        )}
                      </td>
                      <td data-label="التكلفة (تقديرية)" dir="ltr" className="p-2 pt-4 text-start tabular-nums">
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
              </table>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button
                type="button"
                variant="outline"
                onClick={() =>
                  setLines((ls) => [
                    ...ls,
                    { key: Math.max(0, ...ls.map((x) => x.key)) + 1, item_id: "", unit_id: "", qty: "" },
                  ])
                }
              >
                إضافة مادة
              </Button>
              <Button type="button" variant="outline" onClick={() => regenerate(formulaId, batches)}>
                إعادة السطور من الوصفة
              </Button>
            </div>
            {shortages.length > 0 && (
              <Alert>
                الرصيد لا يكفي من:{" "}
                {shortages
                  .map(
                    (p) =>
                      `${p.item?.code} - ${p.item?.name} (المطلوب ${formatQtyUnits(p.base ?? 0n)} والمتاح ${formatQtyUnits(p.stock)} ${p.item?.unit})`,
                  )
                  .join("، ")}
                . لا يُسجَّل الإنتاج حتى يتوفر الرصيد أو تُعدَّل الكميات.
              </Alert>
            )}

            <div className="grid gap-3 rounded-md border p-3">
              <div className="font-semibold">تكاليف إضافية (اختياري)</div>
              <div className="grid gap-3 sm:grid-cols-[12rem_1fr] sm:items-start">
                <div className="grid gap-2">
                  <Label htmlFor="extra_cost">المبلغ (عمالة/تشغيل)</Label>
                  <Input
                    id="extra_cost"
                    dir="ltr"
                    inputMode="decimal"
                    value={extraCost}
                    aria-invalid={extraCents === null}
                    onChange={(e) => setExtraCost(e.target.value)}
                  />
                </div>
                {extra > 0n && (
                  <div className="grid gap-2">
                    <Label htmlFor="extra_account">الحساب الدائن</Label>
                    <NativeSelect
                      id="extra_account"
                      value={extraAccountId}
                      onChange={(e) => setExtraAccountId(e.target.value)}
                    >
                      <option value="">اختر الحساب</option>
                      {extraAccounts.map((a) => (
                        <option key={a.id} value={a.id}>
                          {a.code} - {a.name}
                        </option>
                      ))}
                    </NativeSelect>
                  </div>
                )}
              </div>
              <p className="text-xs text-muted-foreground">
                تُضاف لتكلفة المنتج وتُسجَّل دائنة على خزينة أو بنك (لو دُفعت الآن) أو حساب خصوم مثل المصروفات
                المستحقة. لا تسجّل نفس المبلغ كمصروف مرة أخرى حتى لا يُحسب مرتين، ولو تُرك صفرًا تبقى الأجور
                والمصروفات مصروفًا عاديًا ولا تدخل تكلفة المنتج.
              </p>
            </div>

            <dl className="grid grid-cols-2 gap-2 rounded-md border p-3 text-sm sm:grid-cols-5">
              <div>
                <dt className="text-muted-foreground">خامات مستهلكة</dt>
                <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                  {formatCents(raw)}
                </dd>
              </div>
              <div>
                <dt className="text-muted-foreground">مواد تعبئة مستهلكة</dt>
                <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                  {formatCents(packaging)}
                </dd>
              </div>
              <div>
                <dt className="text-muted-foreground">تكاليف إضافية</dt>
                <dd dir="ltr" className="text-end font-semibold tabular-nums sm:text-start">
                  {formatCents(extra)}
                </dd>
              </div>
              <div>
                <dt className="text-muted-foreground">إجمالي تكلفة الإنتاج</dt>
                <dd dir="ltr" className="text-end font-bold tabular-nums sm:text-start">
                  {formatCents(total)}
                </dd>
              </div>
              <div>
                <dt className="text-muted-foreground">تكلفة الوحدة (لكل {product?.unit})</dt>
                <dd dir="ltr" className="text-end font-bold tabular-nums sm:text-start">
                  {unitCost === null ? "—" : formatUnitCostUnits(unitCost)}
                </dd>
              </div>
            </dl>
            <p className="text-xs text-muted-foreground">
              التكلفة معاينة بمتوسط التكلفة الحالي، والمعتمد ما تحسبه قاعدة البيانات لحظة الاعتماد. الفرق بين
              المستهلك والمعياري هو الهالك، ويدخل في تكلفة المنتج.
            </p>
          </>
        )}

        <div className="grid gap-2">
          <Label htmlFor="notes">البيان (اختياري)</Label>
          <Input id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </div>

        {error && <Alert>{error}</Alert>}

        <div>
          <Button type="button" onClick={requestPost} disabled={pending}>
            {pending ? "جارٍ الاعتماد..." : "اعتماد الإنتاج"}
          </Button>
        </div>
      </CardContent>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد تسجيل الإنتاج</AlertDialogTitle>
            <AlertDialogDescription>
              إنتاج {qtyProduced} {producedUnitName} من {product?.code} - {product?.name} بتكلفة {formatCents(total)}
              {unitCost === null ? "" : ` (تكلفة الوحدة ${formatUnitCostUnits(unitCost)} لكل ${product?.unit})`}.
              تُصرف {used.length} مادة من المخزون بمتوسط تكلفتها الآن ويُضاف المنتج للمخزون
              {extra > 0n && extraAccount
                ? `، وتُسجَّل التكاليف الإضافية ${formatCents(extra)} دائنة على ${extraAccount.code} - ${extraAccount.name}`
                : ""}
              . لا يمكن تعديل أمر الإنتاج بعد الاعتماد، والتصحيح يكون بإلغائه ثم تسجيله من جديد.
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
