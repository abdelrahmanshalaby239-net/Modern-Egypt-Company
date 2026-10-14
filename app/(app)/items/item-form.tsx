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
import { ITEM_TYPES, ITEM_TYPE_LABELS } from "@/lib/labels";
import { parseCents } from "@/lib/money";
import { formatQty, formatUnitCost, parseFactor, parseQty, parseUnitPrice } from "@/lib/quantity";
import { saveItem } from "./actions";

export type ItemCard = {
  id: number | null;
  code: string;
  name: string;
  type: string;
  unit: string;
  category_id: number | null;
  barcode: string;
  sale_price: string;
  default_cost: string;
  min_stock: string;
  is_active: boolean;
  default_sale_unit_id: number | null;
};

export type UnitRow = { key: number; id: number | null; name: string; factor: string; sale_price: string; is_active: boolean };

type Category = { id: number; name: string };
// stock = الرصيد الحالي والمتوسط الفعلي (للعرض فقط، لا يتأثر بالتكلفة الافتراضية)
type Stock = { qty: string; avg_cost: string } | null;

// قيمة "base" في اختيار وحدة البيع الافتراضية = الوحدة الأساسية
const BASE = "base";

export function ItemForm({
  item,
  units: initialUnits,
  categories,
  stock,
  used,
}: {
  item: ItemCard;
  units: UnitRow[];
  categories: Category[];
  stock: Stock;
  used: boolean;
}) {
  const [state, action, pending] = useActionState<FormState, FormData>(saveItem, {});
  const [card, setCard] = useState(item);
  const [units, setUnits] = useState<UnitRow[]>(initialUnits);
  const [defaultUnit, setDefaultUnit] = useState<string>(
    item.default_sale_unit_id ? String(initialUnits.find((u) => u.id === item.default_sale_unit_id)?.key) : BASE,
  );
  const [clientError, setClientError] = useState("");

  const set = <K extends keyof ItemCard>(field: K, value: ItemCard[K]) => setCard((c) => ({ ...c, [field]: value }));
  const setUnit = (key: number, field: keyof Omit<UnitRow, "key" | "id">, value: string | boolean) =>
    setUnits((us) => us.map((u) => (u.key === key ? { ...u, [field]: value } : u)));
  const addUnit = () =>
    setUnits((us) => [
      ...us,
      { key: Math.max(0, ...us.map((u) => u.key)) + 1, id: null, name: "", factor: "", sale_price: "", is_active: true },
    ]);
  const removeUnit = (key: number) => {
    setUnits((us) => us.filter((u) => u.key !== key));
    if (defaultUnit === String(key)) setDefaultUnit(BASE);
  };

  const isFinished = card.type === "finished_good";
  const baseUnit = card.unit.trim() || "الوحدة الأساسية";

  const validate = (): string => {
    if (!card.code.trim()) return "كود الصنف مطلوب.";
    if (!card.name.trim()) return "اسم الصنف مطلوب.";
    if (!card.unit.trim()) return "الوحدة الأساسية مطلوبة.";
    if (parseUnitPrice(card.default_cost) === null)
      return "التكلفة الافتراضية غير صالحة (رقم موجب بأربع خانات عشرية كحد أقصى).";
    if (parseQty(card.min_stock) === null) return "الحد الأدنى للمخزون غير صالح (رقم موجب بثلاث خانات عشرية كحد أقصى).";
    if (isFinished && parseCents(card.sale_price) === null) return "سعر البيع غير صالح (بخانتين عشريتين كحد أقصى).";
    const names = new Set([card.unit.trim()]);
    for (const [i, u] of units.entries()) {
      const n = i + 1;
      if (!u.name.trim()) return `الوحدة ${n}: اسم الوحدة مطلوب.`;
      if (names.has(u.name.trim())) return `الوحدة ${n}: اسم الوحدة "${u.name.trim()}" مكرر.`;
      names.add(u.name.trim());
      const factor = parseFactor(u.factor);
      if (factor === null || factor <= 0n)
        return `الوحدة ${n}: معامل التحويل رقم أكبر من صفر بست خانات عشرية كحد أقصى.`;
      if (isFinished && parseCents(u.sale_price) === null) return `الوحدة ${n}: سعر البيع غير صالح.`;
      if (isFinished && defaultUnit === String(u.key) && !u.is_active)
        return `الوحدة ${n}: وحدة البيع الافتراضية يجب أن تكون نشطة.`;
    }
    return "";
  };

  const submit = () => {
    const error = validate();
    setClientError(error);
    if (error) return;
    const formData = new FormData();
    formData.set(
      "item",
      JSON.stringify({
        id: card.id,
        code: card.code,
        name: card.name,
        type: card.type,
        unit: card.unit,
        category_id: card.category_id,
        barcode: card.barcode,
        // سعر البيع ووحدة البيع الافتراضية للمنتج التام فقط
        sale_price: isFinished ? card.sale_price : "",
        default_cost: card.default_cost,
        min_stock: card.min_stock,
        is_active: card.is_active,
      }),
    );
    formData.set(
      "units",
      JSON.stringify(
        units.map((u) => ({
          id: u.id,
          name: u.name,
          factor: u.factor,
          sale_price: isFinished ? u.sale_price : "",
          is_active: u.is_active,
          is_default: isFinished && defaultUnit === String(u.key),
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
          <CardTitle>البيانات الأساسية</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4">
          <div className="grid gap-3 sm:grid-cols-[10rem_1fr]">
            <div className="grid gap-2">
              <Label htmlFor="code">الكود</Label>
              <Input id="code" dir="ltr" className="text-end" value={card.code} onChange={(e) => set("code", e.target.value)} />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="name">الاسم</Label>
              <Input id="name" value={card.name} onChange={(e) => set("name", e.target.value)} />
            </div>
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="grid gap-2">
              <Label htmlFor="type">النوع</Label>
              <NativeSelect id="type" value={card.type} disabled={used} onChange={(e) => set("type", e.target.value)}>
                {ITEM_TYPES.map((t) => (
                  <option key={t} value={t}>
                    {ITEM_TYPE_LABELS[t]}
                  </option>
                ))}
              </NativeSelect>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="unit">الوحدة الأساسية (وحدة المخزون)</Label>
              <Input
                id="unit"
                value={card.unit}
                disabled={used}
                placeholder="كجم، لتر، قطعة، عبوة"
                onChange={(e) => set("unit", e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="category">التصنيف</Label>
              <NativeSelect
                id="category"
                value={card.category_id ?? ""}
                onChange={(e) => set("category_id", e.target.value ? Number(e.target.value) : null)}
              >
                <option value="">بدون تصنيف</option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </NativeSelect>
            </div>
          </div>
          {used && (
            <p className="text-xs text-muted-foreground">
              النوع والوحدة الأساسية لا يتغيران بعد وجود حركات أو مستندات على الصنف (حفاظًا على المخزون والمستندات
              السابقة).
            </p>
          )}
          <div className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
            <div className="grid max-w-sm gap-2">
              <Label htmlFor="barcode">الباركود (اختياري)</Label>
              <Input id="barcode" dir="ltr" className="text-end" value={card.barcode} onChange={(e) => set("barcode", e.target.value)} />
            </div>
            {card.id && (
              <Label>
                <Checkbox checked={card.is_active} onChange={(e) => set("is_active", e.target.checked)} />
                نشط (المعطّل لا يظهر في المستندات الجديدة)
              </Label>
            )}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>التكلفة والمخزون</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="grid gap-2">
              <Label htmlFor="default_cost">التكلفة الافتراضية لكل {baseUnit}</Label>
              <Input
                id="default_cost"
                dir="ltr"
                inputMode="decimal"
                value={card.default_cost}
                aria-invalid={parseUnitPrice(card.default_cost) === null}
                onChange={(e) => set("default_cost", e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                تُقترح تكلفةً لمخزون أول المدة فقط (يمكن تعديلها هناك). لا تغيّر قيمة المخزون ولا متوسط التكلفة الفعلي.
              </p>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="min_stock">الحد الأدنى للمخزون ({baseUnit})</Label>
              <Input
                id="min_stock"
                dir="ltr"
                inputMode="decimal"
                value={card.min_stock}
                aria-invalid={parseQty(card.min_stock) === null}
                onChange={(e) => set("min_stock", e.target.value)}
              />
              <p className="text-xs text-muted-foreground">يظهر الصنف في تنبيه النقص لو قل رصيده عن هذا الحد (صفر = بلا تنبيه).</p>
            </div>
          </div>
          {stock && (
            <dl className="grid gap-2 text-sm sm:grid-cols-[12rem_1fr]">
              <dt className="text-muted-foreground">الرصيد الحالي</dt>
              <dd dir="ltr" className="text-end tabular-nums sm:text-start">
                {formatQty(stock.qty)} {card.unit}
              </dd>
              <dt className="text-muted-foreground">متوسط التكلفة الفعلي</dt>
              <dd dir="ltr" className="text-end tabular-nums sm:text-start">
                {formatUnitCost(stock.avg_cost)}
              </dd>
            </dl>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>الوحدات{isFinished ? " وأسعار البيع" : ""}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3">
          <p className="text-sm text-muted-foreground">
            المخزون دائمًا بالوحدة الأساسية. لكل وحدة بديلة معامل تحويل: كم {baseUnit} فيها. المستندات تحفظ الوحدة
            ومعاملها وقت الاعتماد، ومعامل الوحدة المستخدمة لا يتغير.
          </p>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[40rem] text-sm">
              <thead>
                <tr className="border-b text-muted-foreground">
                  <th className="p-2 text-start font-semibold">الوحدة</th>
                  <th className="w-44 p-2 text-start font-semibold">معامل التحويل</th>
                  {isFinished && <th className="w-32 p-2 text-start font-semibold">سعر البيع</th>}
                  {isFinished && <th className="w-24 p-2 text-start font-semibold">افتراضية للبيع</th>}
                  <th className="w-20 p-2 text-start font-semibold">نشطة</th>
                  <th className="w-16 p-2" />
                </tr>
              </thead>
              <tbody>
                <tr className="border-b align-top">
                  <td className="p-2 pt-4 font-semibold">
                    {baseUnit} <span className="text-xs font-normal text-muted-foreground">(أساسية)</span>
                  </td>
                  <td className="p-2 pt-4 text-muted-foreground">1</td>
                  {isFinished && (
                    <td className="p-2">
                      <Input
                        aria-label="سعر بيع الوحدة الأساسية"
                        dir="ltr"
                        inputMode="decimal"
                        value={card.sale_price}
                        aria-invalid={parseCents(card.sale_price) === null}
                        onChange={(e) => set("sale_price", e.target.value)}
                      />
                    </td>
                  )}
                  {isFinished && (
                    <td className="p-2 pt-4">
                      <input
                        type="radio"
                        name="default_unit"
                        aria-label="الوحدة الأساسية افتراضية للبيع"
                        className="size-4 accent-primary"
                        checked={defaultUnit === BASE}
                        onChange={() => setDefaultUnit(BASE)}
                      />
                    </td>
                  )}
                  <td className="p-2 pt-4 text-muted-foreground">دائمًا</td>
                  <td />
                </tr>
                {units.map((u) => (
                  <tr key={u.key} className="border-b align-top">
                    <td className="p-2">
                      <Input aria-label="اسم الوحدة" value={u.name} placeholder="كرتونة، برميل..." onChange={(e) => setUnit(u.key, "name", e.target.value)} />
                    </td>
                    <td className="p-2">
                      <Input
                        aria-label="معامل التحويل"
                        dir="ltr"
                        inputMode="decimal"
                        value={u.factor}
                        aria-invalid={parseFactor(u.factor) === null}
                        onChange={(e) => setUnit(u.key, "factor", e.target.value)}
                      />
                      <div className="pt-1 text-xs text-muted-foreground">
                        1 {u.name.trim() || "وحدة"} = {u.factor.trim() || "؟"} {baseUnit}
                      </div>
                    </td>
                    {isFinished && (
                      <td className="p-2">
                        <Input
                          aria-label="سعر البيع"
                          dir="ltr"
                          inputMode="decimal"
                          value={u.sale_price}
                          aria-invalid={parseCents(u.sale_price) === null}
                          onChange={(e) => setUnit(u.key, "sale_price", e.target.value)}
                        />
                      </td>
                    )}
                    {isFinished && (
                      <td className="p-2 pt-4">
                        <input
                          type="radio"
                          name="default_unit"
                          aria-label="افتراضية للبيع"
                          className="size-4 accent-primary"
                          checked={defaultUnit === String(u.key)}
                          onChange={() => setDefaultUnit(String(u.key))}
                        />
                      </td>
                    )}
                    <td className="p-2 pt-4">
                      <Checkbox
                        aria-label="نشطة"
                        checked={u.is_active}
                        onChange={(e) => setUnit(u.key, "is_active", e.target.checked)}
                      />
                    </td>
                    <td className="p-2">
                      <Button type="button" variant="outline" size="sm" onClick={() => removeUnit(u.key)}>
                        حذف
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div>
            <Button type="button" variant="outline" onClick={addUnit}>
              إضافة وحدة
            </Button>
          </div>
        </CardContent>
      </Card>

      {error && <Alert>{error}</Alert>}
      <div>
        <Button type="button" onClick={submit} disabled={pending}>
          {pending ? "جارٍ الحفظ..." : "حفظ بطاقة الصنف"}
        </Button>
      </div>
    </div>
  );
}
