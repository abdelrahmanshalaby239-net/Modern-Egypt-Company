import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { requireUser } from "@/lib/auth";
import { formatFactor } from "@/lib/quantity";
import { ItemForm } from "../item-form";

export const metadata: Metadata = { title: "بطاقة صنف" };

// الأرقام تُقرأ نصًا (::text) حتى لا تمر بـ Number، وتُعرض بلا أصفار زائدة
const trim = (value: string | null) => (value == null ? "" : value.replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, ""));

export default async function ItemCardPage({ params, searchParams }: PageProps<"/items/[id]">) {
  const id = Number((await params).id);
  if (!Number.isInteger(id)) notFound();
  const saved = (await searchParams).saved === "1";

  const { supabase } = await requireUser();
  const { data: item } = await supabase
    .from("items")
    .select(
      "id, code, name, type, unit, category_id, barcode, sale_price::text, default_cost::text, min_stock::text, is_active, default_sale_unit_id",
    )
    .eq("id", id)
    .maybeSingle();
  if (!item) notFound();

  const [{ data: units }, { data: categories }, { data: stock }, { count: movements }, { count: formulaRefs }] =
    await Promise.all([
      supabase
        .from("item_units")
        .select("id, name, factor::text, sale_price::text, is_active")
        .eq("item_id", id)
        .order("id"),
      supabase.from("item_categories").select("id, name").order("name"),
      supabase.from("item_stock").select("qty::text, avg_cost::text").eq("item_id", id).maybeSingle(),
      supabase.from("stock_movements").select("id", { count: "exact", head: true }).eq("item_id", id),
      supabase.from("formula_lines").select("id", { count: "exact", head: true }).eq("item_id", id),
    ]);
  // للصنف حركات أو وصفات: النوع والوحدة الأساسية ثابتان (مفروض في قاعدة البيانات، وهذا تلميح فقط)
  const used = (movements ?? 0) > 0 || (formulaRefs ?? 0) > 0;

  return (
    <div className="grid max-w-4xl gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Link href="/items" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
          ← الأصناف
        </Link>
        <Button asChild variant="outline" size="sm">
          <Link href={`/inventory/movements?item=${id}`}>حركة الصنف</Link>
        </Button>
      </div>
      <h1 className="text-xl font-bold">
        بطاقة الصنف: {item.code} - {item.name}
      </h1>
      {saved && <Alert variant="success">تم حفظ بطاقة الصنف.</Alert>}
      <ItemForm
        key={JSON.stringify(item) + JSON.stringify(units)}
        item={{
          id: item.id,
          code: item.code,
          name: item.name,
          type: item.type,
          unit: item.unit,
          category_id: item.category_id,
          barcode: item.barcode ?? "",
          sale_price: trim(item.sale_price),
          default_cost: trim(item.default_cost) === "0" ? "" : trim(item.default_cost),
          min_stock: trim(item.min_stock) === "0" ? "" : trim(item.min_stock),
          is_active: item.is_active,
          default_sale_unit_id: item.default_sale_unit_id,
        }}
        units={(units ?? []).map((u, i) => ({
          key: i + 1,
          id: u.id,
          name: u.name,
          factor: formatFactor(u.factor).replace(/,/g, ""),
          sale_price: trim(u.sale_price),
          is_active: u.is_active,
        }))}
        categories={categories ?? []}
        stock={stock ? { qty: stock.qty, avg_cost: stock.avg_cost } : null}
        used={used}
      />
    </div>
  );
}
