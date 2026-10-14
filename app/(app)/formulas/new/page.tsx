import type { Metadata } from "next";
import Link from "next/link";

import { requireUser } from "@/lib/auth";
import { loadFormulaItems } from "../data";
import { FormulaForm } from "../formula-form";

export const metadata: Metadata = { title: "وصفة جديدة" };

export default async function NewFormulaPage() {
  const { supabase } = await requireUser();
  const { products, materials } = await loadFormulaItems(supabase);
  const missing = !products.some((p) => p.is_active) || !materials.some((m) => m.is_active);

  return (
    <div className="grid max-w-4xl gap-4">
      <Link href="/formulas" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
        ← الوصفات
      </Link>
      <h1 className="text-xl font-bold">وصفة جديدة</h1>
      {missing ? (
        <p className="text-sm text-muted-foreground">
          أضف من{" "}
          <Link href="/items" className="font-semibold text-foreground underline">
            الأصناف
          </Link>{" "}
          منتجًا تامًا ومواد (خام أو تعبئة) أولًا.
        </p>
      ) : (
        <FormulaForm
          formula={{
            id: null,
            name: "",
            finished_item_id: "",
            batch_qty: "",
            batch_unit_id: "",
            notes: "",
            is_active: true,
          }}
          lines={[]}
          products={products}
          materials={materials}
        />
      )}
    </div>
  );
}
