import type { Metadata } from "next";
import Link from "next/link";

import { requireUser } from "@/lib/auth";
import { ItemForm } from "../item-form";

export const metadata: Metadata = { title: "صنف جديد" };

export default async function NewItemPage() {
  const { supabase } = await requireUser();
  const { data: categories } = await supabase.from("item_categories").select("id, name").order("name");

  return (
    <div className="grid max-w-4xl gap-4">
      <Link href="/items" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
        ← الأصناف
      </Link>
      <h1 className="text-xl font-bold">صنف جديد</h1>
      <ItemForm
        item={{
          id: null,
          code: "",
          name: "",
          type: "raw_material",
          unit: "",
          category_id: null,
          barcode: "",
          sale_price: "",
          default_cost: "",
          min_stock: "",
          is_active: true,
          default_sale_unit_id: null,
        }}
        units={[]}
        categories={categories ?? []}
        stock={null}
        used={false}
      />
    </div>
  );
}
