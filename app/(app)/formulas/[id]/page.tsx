import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { requireUser } from "@/lib/auth";
import { formatQty } from "@/lib/quantity";
import { loadFormulaItems } from "../data";
import { FormulaForm } from "../formula-form";
import { DeleteFormulaButton } from "./delete-formula-button";

export const metadata: Metadata = { title: "وصفة" };

export default async function FormulaPage({ params, searchParams }: PageProps<"/formulas/[id]">) {
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();
  const saved = (await searchParams).saved === "1";

  const { supabase } = await requireUser();
  const { data: formula } = await supabase
    .from("formulas")
    .select("id, name, finished_item_id, batch_qty::text, batch_unit_id, notes, is_active")
    .eq("id", id)
    .maybeSingle();
  if (!formula) notFound();

  const [{ data: lines }, { count: orders }, { products, materials }] = await Promise.all([
    supabase.from("formula_lines").select("item_id, unit_id, qty_per_batch::text").eq("formula_id", id).order("id"),
    supabase.from("production_orders").select("id", { count: "exact", head: true }).eq("formula_id", id),
    loadFormulaItems(supabase),
  ]);
  const usedCount = orders ?? 0;

  return (
    <div className="grid max-w-4xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Link href="/formulas" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
          ← الوصفات
        </Link>
        <div className="flex gap-2">
          {formula.is_active && (
            <Button asChild size="sm">
              <Link href={`/production/new?formula=${id}`}>تسجيل إنتاج بهذه الوصفة</Link>
            </Button>
          )}
          {usedCount === 0 && <DeleteFormulaButton id={id} name={formula.name} />}
        </div>
      </div>
      <h1 className="text-xl font-bold">الوصفة: {formula.name}</h1>
      {saved && <Alert variant="success">تم حفظ الوصفة.</Alert>}
      {usedCount > 0 && (
        <p className="text-sm text-muted-foreground">
          استُخدمت في{" "}
          <Link href={`/production?q=${encodeURIComponent(formula.name)}`} className="underline">
            {usedCount} أمر إنتاج
          </Link>
          ، فلا تُحذف (عطّلها بدل الحذف). تعديلها يسري على الإنتاج القادم فقط.
        </p>
      )}
      <FormulaForm
        key={JSON.stringify(formula) + JSON.stringify(lines)}
        formula={{
          id: formula.id,
          name: formula.name,
          finished_item_id: String(formula.finished_item_id),
          batch_qty: formatQty(formula.batch_qty).replace(/,/g, ""),
          batch_unit_id: formula.batch_unit_id ? String(formula.batch_unit_id) : "",
          notes: formula.notes ?? "",
          is_active: formula.is_active,
        }}
        lines={(lines ?? []).map((l, i) => ({
          key: i + 1,
          item_id: String(l.item_id),
          unit_id: l.unit_id ? String(l.unit_id) : "",
          qty_per_batch: formatQty(l.qty_per_batch).replace(/,/g, ""),
        }))}
        products={products}
        materials={materials}
      />
    </div>
  );
}
