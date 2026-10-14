import type { Metadata } from "next";
import Link from "next/link";

import { getExtraCostAccounts } from "@/lib/accounts";
import { requireUser } from "@/lib/auth";
import { formatDate, todayIso } from "@/lib/format";
import { ITEM_TYPE_LABELS, isItemType } from "@/lib/labels";
import { formatQty } from "@/lib/quantity";
import { ProductionForm, type ProductionItem } from "./production-form";

export const metadata: Metadata = { title: "تسجيل إنتاج" };

export default async function NewProductionPage({ searchParams }: PageProps<"/production/new">) {
  const { supabase } = await requireUser();
  const formulaParam = (await searchParams).formula;

  const [{ data: formulas }, { data: formulaLines }, { data: items }, { data: units }, { data: balances }, extraAccounts] =
    await Promise.all([
      supabase
        .from("formulas")
        .select("id, name, finished_item_id, batch_qty::text, batch_unit_id")
        .eq("is_active", true)
        .order("name"),
      supabase.from("formula_lines").select("formula_id, item_id, unit_id, qty_per_batch::text").order("id"),
      supabase.from("items").select("id, code, name, type, unit").eq("is_active", true).order("code"),
      supabase.from("item_units").select("id, item_id, name, factor::text, is_active").order("id"),
      supabase.rpc("stock_balances"),
      getExtraCostAccounts(supabase),
    ]);
  const stockOf = new Map((balances ?? []).map((b) => [b.item_id, b]));

  const toItem = (i: NonNullable<typeof items>[number]): ProductionItem => ({
    id: i.id,
    code: i.code,
    name: i.name,
    unit: i.unit,
    type: i.type,
    typeLabel: isItemType(i.type) ? ITEM_TYPE_LABELS[i.type] : i.type,
    qty: stockOf.get(i.id)?.qty ?? "0",
    value: stockOf.get(i.id)?.value ?? "0",
    units: (units ?? [])
      .filter((u) => u.item_id === i.id)
      .map(({ id, name, factor, is_active }) => ({ id, name, factor, is_active })),
  });
  const products = (items ?? []).filter((i) => i.type === "finished_good").map(toItem);
  const materials = (items ?? []).filter((i) => i.type !== "finished_good").map(toItem);
  // وصفات منتجها نشط فقط
  const activeFormulas = (formulas ?? [])
    .filter((f) => products.some((p) => p.id === f.finished_item_id))
    .map((f) => ({
      id: f.id,
      name: f.name,
      finished_item_id: f.finished_item_id,
      batch_qty: formatQty(f.batch_qty).replace(/,/g, ""),
      batch_unit_id: f.batch_unit_id ? String(f.batch_unit_id) : "",
      lines: (formulaLines ?? [])
        .filter((l) => l.formula_id === f.id)
        .map((l) => ({
          item_id: l.item_id,
          unit_id: l.unit_id ? String(l.unit_id) : "",
          qty_per_batch: formatQty(l.qty_per_batch).replace(/,/g, ""),
        })),
    }));

  return (
    <div className="grid max-w-5xl gap-4">
      <Link href="/production" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
        ← أوامر الإنتاج
      </Link>
      <h1 className="text-xl font-bold">تسجيل إنتاج</h1>
      {activeFormulas.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          أضف{" "}
          <Link href="/formulas/new" className="font-semibold text-foreground underline">
            وصفة نشطة
          </Link>{" "}
          لمنتج تام أولًا.
        </p>
      ) : (
        <ProductionForm
          defaultDate={formatDate(todayIso())}
          formulas={activeFormulas}
          initialFormulaId={typeof formulaParam === "string" ? formulaParam : ""}
          products={products}
          materials={materials}
          extraAccounts={extraAccounts}
        />
      )}
    </div>
  );
}
